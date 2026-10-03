import AppKit
import MetalKit
import QuartzCore
import os

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
        view.preferredFramesPerSecond = pace.framesPerSecond
        view.delegate = self
        self.view = view
    }

    /// Whether the view is on screen and not covered; its owner keeps it current. Hidden, the Orb draws no frames.
    var isVisible = true {
        didSet {
            guard isVisible != oldValue else { return }
            // Shown again: one frame tells whether something changed while it was hidden.
            if isVisible, pace == .still { pace = .full }
            updateLoop()
        }
    }

    /// Where the pointer is over the view, -1…1 on each axis from the centre with y up; `nil` when it is outside.
    ///
    /// The Orb eases toward it at the frames it draws anyway: the pointer alone never wakes a still Orb.
    var pointer: SIMD2<Float>?

    private let queue: MTLCommandQueue
    private let pipelines: OrbPipelines
    private let controls: OrbControls
    private let frameLog: OrbFrameLog?
    private weak var view: MTKView?
    /// How often the Orb draws now; decided again at every frame.
    private var pace = OrbPace.full
    /// While the Orb is still: the tasks that wait for what makes it draw again.
    private var wakers: [Task<Void, Never>] = []
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

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // A still Orb draws again at its new size.
        if pace == .still { resume() }
    }

    func draw(in view: MTKView) {
        guard isVisible else { return }
        let now = CACurrentMediaTime()
        let reducesMotion = Motion.isReduced
        animation.state = controls.displayedState
        animation.targetTinta = Tinta(for: controls.provider)
        animation.reducesMotion = reducesMotion
        animation.voiceLevel = controls.voiceLevel
        animation.advance(by: now - lastFrameTime)
        uniforms.apply(animation)
        followPointer(over: now - lastFrameTime, reducesMotion: reducesMotion)
        lastFrameTime = now
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
        follow(OrbPace(state: controls.displayedState, isMorphing: director.isMorphing,
                       isSettled: animation.isSettled && director.isAtRest,
                       isLowPowerModeEnabled: ProcessInfo.processInfo.isLowPowerModeEnabled,
                       reducesMotion: reducesMotion))
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

    /// Eases the Orb's lean toward the pointer, or back to rest once it leaves; with Reduce Motion the Orb never leans.
    private func followPointer(over elapsed: CFTimeInterval, reducesMotion: Bool) {
        guard !reducesMotion else {
            uniforms.pointer = .zero
            return
        }
        let target = pointer ?? .zero
        // About a quarter of a second to get there, whatever the frame rate.
        let step = Float(1 - exp(-min(elapsed, 0.1) * 8))
        uniforms.pointer += (target - uniforms.pointer) * step
    }

    /// Switches the view's frame rate to `newPace`; this frame is drawn either way.
    private func follow(_ newPace: OrbPace) {
        guard newPace != pace else { return }
        Logger.orb.debug("Orb pace \(self.pace.framesPerSecond) → \(newPace.framesPerSecond) fps")
        pace = newPace
        updateLoop()
    }

    /// Runs the view's loop at the pace, or stops it while the Orb is hidden or still.
    private func updateLoop() {
        guard let view else { return }
        if pace != .still, view.preferredFramesPerSecond != pace.framesPerSecond {
            view.preferredFramesPerSecond = pace.framesPerSecond
        }
        let isPaused = !isVisible || pace == .still
        if view.isPaused != isPaused { view.isPaused = isPaused }
        if isVisible, pace == .still {
            waitForChange()
        } else {
            stopWaiting()
        }
    }

    /// Draws again, at least one frame that decides the pace anew.
    private func resume() {
        pace = .full
        updateLoop()
    }

    /// Resumes drawing at the first change of Stato, Tinta or Variante, or of the settings that can stop the Orb.
    private func waitForChange() {
        guard wakers.isEmpty else { return }
        let controls = controls
        wakers = [
            Task { [weak self] in
                // The first value is the current one, not a change.
                for await _ in Observations({ (controls.displayedState, controls.provider, controls.variante) })
                    .dropFirst() {
                    self?.wakeUp()
                    return
                }
            },
            // Riduci movimento, in Aspetto or in the system's settings.
            Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: UserDefaults.didChangeNotification) {
                    self?.wakeUp()
                    return
                }
            },
            Task { [weak self] in
                let name = NSWorkspace.accessibilityDisplayOptionsDidChangeNotification
                for await _ in NSWorkspace.shared.notificationCenter.notifications(named: name) {
                    self?.wakeUp()
                    return
                }
            },
        ]
    }

    private func stopWaiting() {
        wakers.forEach { $0.cancel() }
        wakers = []
    }

    private func wakeUp() {
        stopWaiting()
        resume()
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

private extension Logger {
    static let orb = Logger(subsystem: "com.mgiuditta.bubo", category: "orb")
}
