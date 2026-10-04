import AppKit
import MetalKit
import os
import SwiftUI

/// The Neuroni's map in SwiftUI.
struct NeuronMap: NSViewRepresentable {
    let model: NeuronModel
    /// Opens the note at an index, on a double click.
    let open: (Int) -> Void

    func makeNSView(context: Context) -> NeuronMapNSView {
        NeuronMapNSView(model: model, open: open)
    }

    func updateNSView(_ view: NeuronMapNSView, context: Context) {}
}

/// The Neuroni's map: drag or scroll to move, pinch or the mouse wheel to zoom, click a note to select it and light its
/// links, double click it to open it.
///
/// Like the Galassia's map, it draws only on a change and only while its window shows; a camera flight draws every
/// frame until it lands. VoiceOver reaches every note through the list next to it.
final class NeuronMapNSView: MTKView {
    private let model: NeuronModel
    private let open: (Int) -> Void
    private var renderer: NeuronRenderer?
    private var needsDrawWhenVisible = false
    private var occlusion: (any NSObjectProtocol)?
    private var dragStart: NSPoint?
    private var didDrag = false

    init(model: NeuronModel, open: @escaping (Int) -> Void) {
        self.model = model
        self.open = open
        super.init(frame: .zero, device: MTLCreateSystemDefaultDevice())
        isPaused = true
        enableSetNeedsDisplay = true
        do {
            renderer = try NeuronRenderer(view: self, model: model)
        } catch {
            Logger.neurons.error("Neuroni: map unavailable: \(error)")
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

    /// Whether the window was reported covered or minimized. Only a change reported by AppKit counts: right after
    /// the window shows, `occlusionState` can still miss `.visible` with no change notified later, and a map that
    /// waited for it never drew the notes (#658).
    private var isOccluded = false

    private var isVisible: Bool {
        window != nil && !isOccluded
    }

    private func requestDraw() {
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

    private func didDraw() {
        guard !isPaused, !model.isAnimating else { return }
        isPaused = true
        enableSetNeedsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let occlusion { NotificationCenter.default.removeObserver(occlusion) }
        occlusion = nil
        isOccluded = false
        guard let window else { return }
        if needsDrawWhenVisible {
            needsDrawWhenVisible = false
            needsDisplay = true
        }
        occlusion = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                           object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.occlusionChanged() }
        }
    }

    private func occlusionChanged() {
        isOccluded = window.map { !$0.occlusionState.contains(.visible) } ?? false
        if isVisible {
            if model.isAnimating {
                startContinuousDrawing()
            } else if needsDrawWhenVisible {
                needsDisplay = true
            }
            needsDrawWhenVisible = false
        } else if !isPaused {
            isPaused = true
            enableSetNeedsDisplay = true
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
        if event.clickCount == 2, let index = model.hit(at: location(of: event)) { open(index) }
    }

    /// Where `event` happened, from the top left corner like the camera's points.
    private func location(of event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: point.x, y: bounds.height - point.y)
    }
}
