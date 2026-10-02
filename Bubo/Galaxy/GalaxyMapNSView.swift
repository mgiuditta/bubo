import AppKit
import MetalKit
import os

/// The Galassia's map: drag or scroll to move, pinch or the mouse wheel to zoom, click a star to select it or a folder
/// to zoom into it.
///
/// It draws only on a change and stops drawing while its window is covered or minimized; only a camera flight or a
/// comet moving to a file its Sessione just touched draws every frame, until it lands. VoiceOver reaches every action through the list next to it.
final class GalaxyMapNSView: MTKView {
    private let model: GalaxyModel
    private var renderer: GalaxyRenderer?
    /// A change arrived while the window was covered: it is drawn when the window shows again.
    private var needsDrawWhenVisible = false
    private var occlusion: (any NSObjectProtocol)?
    private var dragStart: NSPoint?
    private var didDrag = false

    init(model: GalaxyModel) {
        self.model = model
        super.init(frame: .zero, device: MTLCreateSystemDefaultDevice())
        // Drawn on demand, never on a timer: a still map costs no frames.
        isPaused = true
        enableSetNeedsDisplay = true
        do {
            renderer = try GalaxyRenderer(view: self, model: model)
        } catch {
            Logger.galaxy.error("Galassia: map unavailable: \(error)")
        }
        renderer?.onDraw = { [weak self] in self?.didDraw() }
        model.onRedraw = { [weak self] in self?.requestDraw() }
        model.onAnimation = { [weak self] in self?.startContinuousDrawing() }
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Whether the map is drawing every frame, during a flight or a comet's move.
    var isDrawingContinuously: Bool { !isPaused }

    private var isVisible: Bool {
        window?.occlusionState.contains(.visible) ?? false
    }

    /// Draws once, now if the window shows, else when it shows again.
    func requestDraw() {
        guard isVisible else {
            needsDrawWhenVisible = true
            return
        }
        needsDisplay = true
    }

    private func startContinuousDrawing() {
        guard isVisible else {
            needsDrawWhenVisible = true
            return
        }
        enableSetNeedsDisplay = false
        isPaused = false
    }

    private func stopContinuousDrawing() {
        isPaused = true
        enableSetNeedsDisplay = true
    }

    private func didDraw() {
        if isDrawingContinuously, !model.isAnimating { stopContinuousDrawing() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let occlusion { NotificationCenter.default.removeObserver(occlusion) }
        occlusion = nil
        guard let window else { return }
        occlusion = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                           object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.occlusionChanged() }
        }
    }

    private func occlusionChanged() {
        if isVisible {
            if model.isAnimating {
                startContinuousDrawing()
            } else if needsDrawWhenVisible {
                needsDisplay = true
            }
            needsDrawWhenVisible = false
        } else if isDrawingContinuously {
            // A covered window draws nothing; the flight and the comets land on the next frame shown.
            stopContinuousDrawing()
            needsDrawWhenVisible = true
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        model.resize(to: newSize)
    }

    // MARK: Input

    override var acceptsFirstResponder: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        if event.hasPreciseScrollingDeltas {
            model.pan(by: CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY))
        } else {
            model.zoom(by: pow(1.1, Float(event.scrollingDeltaY)), around: location(of: event))
        }
    }

    override func magnify(with event: NSEvent) {
        model.zoom(by: 1 + Float(event.magnification), around: location(of: event))
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = location(of: event)
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        let point = location(of: event)
        guard let start = dragStart else { return }
        let translation = CGSize(width: point.x - start.x, height: point.y - start.y)
        if !didDrag, hypot(translation.width, translation.height) < 3 { return }
        didDrag = true
        model.pan(by: translation)
        dragStart = point
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil }
        guard !didDrag else { return }
        model.click(at: location(of: event))
    }

    /// Where `event` happened, from the top left corner like the camera's points.
    private func location(of event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: point.x, y: bounds.height - point.y)
    }
}
