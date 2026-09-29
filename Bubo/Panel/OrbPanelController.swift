import AppKit
import MetalKit
import os

/// Owns the Panel: the always-on-top window with the Orb, shown unless the HUD is open.
@Observable
final class OrbPanelController {
    /// The `UserDefaults` key of the visibility preference.
    static let defaultsKey = "showsPanel"
    /// The Panel's fixed side, in points.
    static let side: CGFloat = 240
    /// The drawable's pixels per point, below Retina to save GPU.
    static let renderScale: CGFloat = 1.5

    /// Whether the user wants the Panel on screen; remembered across launches.
    var isShown: Bool {
        didSet {
            UserDefaults.standard.set(isShown, forKey: Self.defaultsKey)
            updateVisibility()
        }
    }

    /// Creates the Panel, off screen until ``start(openingHUD:)``.
    init() {
        UserDefaults.standard.register(defaults: [Self.defaultsKey: true])
        isShown = UserDefaults.standard.bool(forKey: Self.defaultsKey)
    }

    /// Builds the window and starts following the HUD and the Panel's occlusion.
    ///
    /// - Parameter openHUD: Called when VoiceOver presses the Orb.
    func start(openingHUD openHUD: @escaping () -> Void) {
        let frame = CGRect(origin: .zero, size: CGSize(width: Self.side, height: Self.side))
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true

        let view = OrbPanelView(frame: frame, device: MTLCreateSystemDefaultDevice())
        view.autoResizeDrawable = false
        view.drawableSize = CGSize(width: Self.side * Self.renderScale, height: Self.side * Self.renderScale)
        view.preferredFramesPerSecond = 60
        view.onPress = openHUD
        do {
            renderer = try OrbRenderer(view: view)
        } catch {
            Logger.panel.error("Orb renderer unavailable: \(error)")
            return
        }
        panel.contentView = view
        // ponytail: fixed bottom-right corner; the 3×3 grid and per-screen memory come with the next ticket.
        if let visible = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(CGPoint(x: visible.maxX - Self.side, y: visible.minY))
        }
        self.panel = panel
        self.view = view

        // Every window's occlusion: the Panel's own pauses rendering, the HUD's hides the Panel.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateVisibility() }
        }
        updateVisibility()
    }

    @ObservationIgnored private var panel: NSPanel?
    @ObservationIgnored private var view: MTKView?
    @ObservationIgnored private var renderer: OrbRenderer?

    private var isHUDOpen: Bool {
        NSApp.windows.contains {
            $0.identifier?.rawValue.hasPrefix(HUDPresenter.windowID) == true && $0.isVisible && !$0.isMiniaturized
        }
    }

    private func updateVisibility() {
        guard let panel, let view else { return }
        let wantsPanel = isShown && !isHUDOpen
        if wantsPanel != panel.isVisible {
            if wantsPanel { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
        }
        view.isPaused = !(panel.isVisible && panel.occlusionState.contains(.visible))
    }
}

private extension Logger {
    static let panel = Logger(subsystem: "com.mgiuditta.bubo", category: "panel")
}
