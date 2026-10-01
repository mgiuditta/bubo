import AppKit
import MetalKit
import os

/// Owns the Panel: the always-on-top window with the Orb, shown unless the HUD is open.
@Observable
final class OrbPanelController {
    /// The `UserDefaults` key of the visibility preference.
    static let defaultsKey = "showsPanel"
    /// The `UserDefaults` key of the position memory.
    static let placementKey = "panelPlacement"
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

    /// The zone of the grid the Panel sits in; in phase 3 it tells which way bubbles and cards open.
    private(set) var zone = PanelPlacement.defaultZone

    /// Creates the Panel, off screen until ``start(openingHUD:)``.
    init() {
        UserDefaults.standard.register(defaults: [Self.defaultsKey: true])
        isShown = UserDefaults.standard.bool(forKey: Self.defaultsKey)
        if let data = UserDefaults.standard.data(forKey: Self.placementKey) {
            do {
                placement = try JSONDecoder().decode(PanelPlacement.self, from: data)
            } catch {
                Logger.panel.error("Panel placement unreadable, back to default: \(error)")
            }
        }
    }

    /// Builds the window and starts following the HUD and the Panel's occlusion.
    ///
    /// - Parameters:
    ///   - openHUD: Called when the Orb is clicked or pressed by VoiceOver.
    ///   - menu: The menu of a right click on the Orb, the same as the menu bar's.
    func start(openingHUD openHUD: @escaping () -> Void, menu: NSMenu) {
        let frame = CGRect(origin: .zero, size: CGSize(width: Self.side, height: Self.side))
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        // Borderless windows have no title, so VoiceOver would announce a nameless dialog.
        panel.setAccessibilityLabel(String(localized: "Panel di Bubo"))
        // Clicks go through until the pointer enters the click circle.
        panel.ignoresMouseEvents = true

        let view = OrbPanelView(frame: frame, device: MTLCreateSystemDefaultDevice())
        view.autoResizeDrawable = false
        view.drawableSize = CGSize(width: Self.side * Self.renderScale, height: Self.side * Self.renderScale)
        view.preferredFramesPerSecond = 60
        view.onPress = openHUD
        view.onDragEnd = { [weak self] in self?.snapAfterDrag() }
        view.onPointerMove = { [weak self] in self?.updateClickThrough() }
        view.menu = menu
        do {
            renderer = try OrbRenderer(view: view)
        } catch {
            Logger.panel.error("Orb renderer unavailable: \(error)")
            return
        }
        panel.contentView = view
        self.panel = panel
        self.view = view
        moveToRememberedSpot()

        // A screen plugged, unplugged or rearranged: back to the remembered spot, or to the main screen.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.moveToRememberedSpot() }
        }

        // Every window's occlusion: the Panel's own pauses rendering, the HUD's hides the Panel.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateVisibility() }
        }
        // The pointer over other apps or over Bubo's windows: the Panel takes clicks only inside the circle.
        NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateClickThrough() }
        }
        NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.updateClickThrough()
            return event
        }
        updateVisibility()
    }

    @ObservationIgnored private var panel: NSPanel?
    @ObservationIgnored private var view: MTKView?
    @ObservationIgnored private var renderer: OrbRenderer?
    @ObservationIgnored private var placement = PanelPlacement()

    /// The connected screens, the main one (with the menu bar) first.
    private var screens: [PanelScreen] {
        NSScreen.screens.map { PanelScreen(id: $0.stableID, visibleFrame: $0.visibleFrame) }
    }

    private func moveToRememberedSpot() {
        guard let spot = placement.spot(among: screens) else { return }
        move(to: spot, animated: false)
    }

    private func snapAfterDrag() {
        guard let panel,
              let spot = placement.drop(center: CGPoint(x: panel.frame.midX, y: panel.frame.midY), among: screens)
        else { return }
        do {
            UserDefaults.standard.set(try JSONEncoder().encode(placement), forKey: Self.placementKey)
        } catch {
            Logger.panel.error("Panel placement not saved: \(error)")
        }
        move(to: spot, animated: !Motion.isReduced)
    }

    private func move(to spot: PanelSpot, animated: Bool) {
        zone = spot.zone
        let origin = spot.panelOrigin(side: Self.side)
        panel?.setFrame(CGRect(origin: origin, size: CGSize(width: Self.side, height: Self.side)),
                        display: true, animate: animated)
        updateClickThrough()
    }

    /// Lets clicks through to the windows below unless the pointer is in the click circle.
    private func updateClickThrough() {
        guard let panel else { return }
        panel.ignoresMouseEvents = !PanelClickCircle.contains(NSEvent.mouseLocation, inPanel: panel.frame)
    }

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

private extension NSScreen {
    /// The display's UUID, stable across relaunches and reconnections; the screen's name when there is none.
    var stableID: String {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue(),
              let id = CFUUIDCreateString(nil, uuid) as String?
        else { return localizedName }
        return id
    }
}

private extension Logger {
    static let panel = Logger(subsystem: "com.mgiuditta.bubo", category: "panel")
}
