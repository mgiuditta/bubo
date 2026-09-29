import MetalKit
import QuartzCore

/// Draws the Orb into any `MTKView`; the Panel uses it now, the HUD will in phase 3.
final class OrbRenderer: NSObject, MTKViewDelegate {
    /// Creates a renderer and configures `view` for a transparent, premultiplied Orb.
    ///
    /// - Throws: An error if the Metal pipeline cannot be built.
    init(view: MTKView) throws {
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
    private var uniforms = OrbUniforms()
    private var lastFrameTime = CACurrentMediaTime()

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        // Clamped so a resume after a pause does not jump the animation.
        uniforms.time += Float(min(0.05, now - lastFrameTime))
        lastFrameTime = now
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
        commands.present(drawable)
        commands.commit()
    }
}

/// Why the Orb could not be drawn.
enum OrbRendererError: Error {
    /// No Metal device, command queue or compiled shader library.
    case metalUnavailable
}
