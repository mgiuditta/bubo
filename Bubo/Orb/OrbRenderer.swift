import AppKit
import MetalKit
import QuartzCore

/// Draws the Orb into any `MTKView`; the Panel uses it now, the HUD will in phase 3.
final class OrbRenderer: NSObject, MTKViewDelegate {
    /// Creates a renderer and configures `view` for a transparent, premultiplied Orb.
    ///
    /// - Parameters:
    ///   - view: The view to draw into.
    ///   - controls: Where the Stato and the Variante come from and where frame measurements go.
    /// - Throws: An error if the Blob's pipeline cannot be built.
    init(view: MTKView, controls: OrbControls = .shared) throws {
        guard let device = view.device ?? MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary()
        else { throw OrbRendererError.metalUnavailable }

        self.queue = queue
        self.controls = controls
        pipelines = try OrbPipelines(device: device, library: library)
        super.init()

        view.device = device
        view.colorPixelFormat = .bgra8Unorm
        view.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        view.layer?.isOpaque = false
        view.delegate = self
    }

    private let queue: MTLCommandQueue
    private let pipelines: OrbPipelines
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
        // No Morph yet: a ready Forma shows at once; one still loading leaves the Orb Blob.
        let forma = controls.variante.flatMap { Forma(rawValue: $0.forma) } ?? .blob
        let formaPipeline = pipelines.pipeline(for: forma)
        uniforms.morph = formaPipeline == nil || forma == .blob ? 0 : 1

        guard let pass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commands = queue.makeCommandBuffer(),
              let encoder = commands.makeRenderCommandEncoder(descriptor: pass)
        else { return }
        encoder.setRenderPipelineState(formaPipeline ?? pipelines.blob)
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
