import AppKit
import MetalKit
import QuartzCore

/// Draws the Orb into any `MTKView`; the Panel uses it now, the HUD will in phase 3.
final class OrbRenderer: NSObject, MTKViewDelegate {
    /// Creates a renderer and configures `view` for a transparent, premultiplied Orb.
    ///
    /// - Parameters:
    ///   - view: The view to draw into.
    ///   - controls: Where the Stato comes from and where frame measurements go.
    /// - Throws: An error if the Metal pipeline cannot be built.
    init(view: MTKView, controls: OrbControls = .shared) throws {
        guard let device = view.device ?? MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary()
        else { throw OrbRendererError.metalUnavailable }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "orbVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "orbFragment")
        let color = descriptor.colorAttachments[0]!
        color.pixelFormat = .bgra8Unorm
        color.isBlendingEnabled = true
        color.sourceRGBBlendFactor = .one
        color.sourceAlphaBlendFactor = .one
        color.destinationRGBBlendFactor = .oneMinusSourceAlpha
        color.destinationAlphaBlendFactor = .oneMinusSourceAlpha

        self.queue = queue
        self.controls = controls
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        super.init()

        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.layer?.isOpaque = false
        view.delegate = self
    }

    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let controls: OrbControls
    private var uniforms = OrbUniforms()
    private var animation = OrbAnimation()
    private var lastFrameTime = CACurrentMediaTime()
    #if DEBUG
    private var meter = FrameMeter()
    #endif

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        animation.state = controls.state
        animation.reducesMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        animation.advance(by: now - lastFrameTime)
        lastFrameTime = now
        uniforms.apply(animation)
        uniforms.resolution = SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height))

        guard let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commands = queue.makeCommandBuffer(),
              let encoder = commands.makeRenderCommandEncoder(descriptor: pass)
        else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<OrbUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        #if DEBUG
        measure(commands, drawnAt: now)
        #endif
        commands.present(drawable)
        commands.commit()
    }

    #if DEBUG
    /// Counts the frame and, once it completes, its GPU time; publishes a reading every window.
    private func measure(_ commands: MTLCommandBuffer, drawnAt time: CFTimeInterval) {
        commands.addCompletedHandler { @Sendable [weak self] buffer in
            let gpuTime = buffer.gpuEndTime - buffer.gpuStartTime
            Task { @MainActor in self?.meter.recordGPUTime(gpuTime) }
        }
        if let reading = meter.recordFrame(at: time) {
            controls.frameReading = reading
        }
    }
    #endif
}

/// Why the Orb could not be drawn.
enum OrbRendererError: Error {
    /// No Metal device, command queue or compiled shader library.
    case metalUnavailable
}
