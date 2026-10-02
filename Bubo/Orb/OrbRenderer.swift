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
    ///   - isMonochrome: Whether to draw in greys instead of the Tinta, as the Galleria del Catalogo does.
    ///   - frameLog: Where to write the GPU time of every frame, for the performance tests.
    /// - Throws: An error if the Blob's pipeline cannot be built.
    init(view: MTKView, controls: OrbControls = .shared, isMonochrome: Bool = false,
         frameLog: OrbFrameLog? = nil) throws {
        guard let device = view.device ?? MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary()
        else { throw OrbRendererError.metalUnavailable }

        self.queue = queue
        self.controls = controls
        self.frameLog = frameLog
        animation = OrbAnimation(tinta: Tinta(for: controls.provider))
        pipelines = try OrbPipelines(device: device, library: library)
        super.init()
        if isMonochrome { uniforms.applyMonochromeTinta() }

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
    private let frameLog: OrbFrameLog?
    private var uniforms = OrbUniforms()
    private var animation: OrbAnimation
    private var director = MorphDirector()
    /// The Variante last passed to the Regia, to request each choice once.
    private var requestedVariante: Variante?
    /// When the Orbite was last requested, the start of its diagram's clock.
    private var orbiteStart: CFTimeInterval = 0
    private var lastFrameTime = CACurrentMediaTime()
    #if DEBUG
    private var meter = FrameMeter()
    #endif

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let reducesMotion = Motion.isReduced
        animation.state = controls.displayedState
        animation.targetTinta = Tinta(for: controls.provider)
        animation.reducesMotion = reducesMotion
        animation.voiceLevel = controls.voiceLevel
        animation.advance(by: now - lastFrameTime)
        lastFrameTime = now
        uniforms.apply(animation)
        uniforms.resolution = SIMD2(Float(view.drawableSize.width), Float(view.drawableSize.height))

        if controls.variante != requestedVariante {
            requestedVariante = controls.variante
            if controls.variante == Orbite.variante { orbiteStart = now }
            if let forma = controls.variante.map({ Forma(rawValue: $0.forma) }) {
                pipelines.prepare(forma) // starts loading it while the Orb holds or morphs
            }
            director.request(controls.variante, at: now)
        }
        director.enter(controls.displayedState, at: now)
        director.reducesMotion = reducesMotion
        director.advance(to: now)
        if requestedVariante != nil, director.destination == nil {
            // The Regia went back to the Blob on its own: the same Variante can be chosen again.
            requestedVariante = nil
            controls.variante = nil
        }
        let frame = director.frame
        // A Forma still loading, or not drawn yet, leaves the Orb Blob.
        let formaPipeline = pipelines.pipeline(for: frame.forma)
        uniforms.morph = formaPipeline == nil || frame.forma == .blob ? 0 : frame.morph
        uniforms.opacity = frame.opacity
        if frame.forma == .orbite {
            uniforms.diagramTime = Orbite.diagramTime(since: orbiteStart, at: now, reducesMotion: reducesMotion)
        }

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
        if let frameLog {
            commands.addCompletedHandler { @Sendable buffer in
                let gpuTime = buffer.gpuEndTime - buffer.gpuStartTime
                Task { @MainActor in frameLog.record(gpuTime: gpuTime) }
            }
        }
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
