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
    /// The drawable's pixels per point of the normal Panel, below Retina to save GPU; the HUD's Orb uses it too.
    static let renderScale = PanelSize.normal.renderScale

    /// Whether the user wants the Panel on screen; remembered across launches.
    var isShown: Bool {
        didSet {
            UserDefaults.standard.set(isShown, forKey: Self.defaultsKey)
            updateVisibility()
        }
    }

    /// The zone of the grid the Panel sits in; it tells which way the bubble opens.
    private(set) var zone = PanelPlacement.defaultZone

    /// The Panel's size on the screen it is on.
    private(set) var size = PanelPlacement.defaultSize

    /// Whether the Panel is reduced on the screen it is on; setting it switches size there, as "Panel ridotto" does.
    var isReduced: Bool {
        get { size == .reduced }
        set { resize(to: newValue ? .reduced : .normal) }
    }

    /// Imports the recordings and trascrizioni dropped on the Orb as Riunioni; set by the app.
    var importMeetings: ([URL]) -> Void = { _ in }
    /// Imports the web video of a link dropped on the Orb as a Riunione, calling the closure instead when the link
    /// has no video; set by the app.
    var importVideo: (URL, @escaping () -> Void) -> Void = { _, fallback in fallback() }

    /// The bubble beside the Orb, with the prompt and the answer of the Domanda.
    let bubble = PanelBubble()

    /// What the pill beside the reduced Orb says; `nil` while it is not on screen.
    private(set) var status: PanelStatus?
    /// How the pill appears, read from Riduci movimento each time it comes back.
    private(set) var statusAppearance = PanelBubbleAppearance.grow

    /// Creates the Panel, off screen until ``start(openingHUD:menu:questions:hud:sessions:meetings:)``.
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

    /// Builds the window and starts following the HUD, the Panel's occlusion and the Riunioni.
    ///
    /// - Parameters:
    ///   - openHUD: Called when the Orb is clicked or pressed by VoiceOver.
    ///   - menu: The menu of a right click on the Orb, the same as the menu bar's.
    ///   - questions: The Domanda of the HUD, which the bubble shows too.
    ///   - hud: Where the bubble's "Rifai con…" and Sessione go.
    ///   - sessions: The Sessioni whose Attende te and Errore the status pill and VoiceOver tell; `nil` when they
    ///     cannot be kept.
    ///   - meetings: The Riunioni, whose recording puts a red dot on the Orb.
    ///   - brainSetup: The interview that sets up the Secondo cervello, held in the bubble.
    func start(openingHUD openHUD: @escaping () -> Void, menu: NSMenu, questions: QuestionModel, hud: HUDPresenter,
               sessions: SessionStore?, meetings: MeetingRecorder, brainSetup: SecondBrainConversation) {
        self.openHUD = openHUD
        self.questions = questions
        let frame = CGRect(origin: .zero, size: CGSize(width: size.side, height: size.side))
        let panel = OrbPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .floating
        // Out of the window cycle: the Panel is not a window to switch to.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
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
        // The bubble is the default way to ask; the HUD stays a hot key or a menu item away.
        view.onPress = { [weak self] in self?.askInPanel() }
        view.onAsk = { [weak self] in self?.askInPanel() }
        view.onToggleSize = { [weak self] in self?.isReduced.toggle() }
        view.onDragEnd = { [weak self] in self?.snapAfterDrag() }
        view.onPointerMove = { [weak self] in self?.updateClickThrough() }
        view.registerForDraggedTypes(OrbDropTarget.types)
        view.onDropEnter = { [weak self, questions] pasteboard in
            questions.awaitAttachments()
            self?.isOfferingTranscription = OrbDropTarget.drop(in: pasteboard).isTranscription
        }
        view.onDropExit = { [weak self, questions] in
            if questions.attachments.isEmpty { questions.stopAwaitingAttachments() }
            self?.isOfferingTranscription = false
        }
        view.onDrop = { [weak self, questions] pasteboard in
            self?.drop(pasteboard, into: questions) ?? false
        }
        view.menu = menu
        let frameLog = OrbFrameLog.fromLaunchArguments()
        do {
            renderer = try OrbRenderer(view: view, frameLog: frameLog)
        } catch {
            Logger.panel.error("Orb renderer unavailable: \(error)")
            return
        }
        if frameLog != nil {
            Task { await OrbFrameLog.keepMorphing(.shared) }
        }
        panel.contentView = view
        self.panel = panel
        self.view = view
        startBubble(questions: questions, hud: hud, brainSetup: brainSetup)
        startStatus(questions: questions, hud: hud, sessions: sessions)
        Task { [weak self] in
            for await isRecording in Observations({ meetings.isRecording }) {
                self?.view?.isRecordingMeeting = isRecording
            }
        }
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
        // The pointer over other apps or over Bubo's windows: the Panel takes clicks only inside the circle. A drag
        // from another app moves the pointer too, so that a drop on the Orb reaches it.
        // The pointer moving is also when the Dock has just changed side or size, which changes `visibleFrame` with no
        // notification: the Panel follows it there.
        NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.followVisibleFrames()
                self?.updateClickThrough()
            }
        }
        NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.followVisibleFrames()
            self?.updateClickThrough()
            return event
        }
        updateVisibility()
    }

    /// Opens the bubble with the keyboard in its prompt, or the HUD when the HUD is open and the Panel hidden.
    ///
    /// With a browser in front, its page comes in the prompt as an Allegato as soon as the browser tells it.
    func askInPanel() {
        guard !isHUDOpen else {
            openHUD()
            return
        }
        // Read before the bubble opens: the Panel never activates Bubo, so the app in front is the user's.
        let front = NSWorkspace.shared.frontmostApplication
        bubble.open(focus: .prompt)
        guard let front, let id = front.bundleIdentifier, BrowserPage.script(forBrowser: id) != nil else { return }
        let browserName = front.localizedName ?? id
        Task { [weak self] in
            guard let page = await BrowserPage.current(inBrowser: id, named: browserName),
                  let self, bubble.isOpen, let questions, !questions.isAnswering
            else { return }
            questions.attach([page])
        }
    }

    /// «Allega finestra» (#485): the system's picker, then the window the user clicks goes in the prompt as an
    /// Allegato, in the bubble, or in the HUD when the Panel is hidden or the HUD open.
    func attachWindow() {
        guard let questions else { return }
        Task {
            let allegato: Allegato?
            do {
                let directory = try QuestionModel.directory().appending(path: "Allegati", directoryHint: .isDirectory)
                allegato = try await windowCapture.attachment(savingIn: directory)
            } catch {
                Logger.panel.error("Window not attached: \(error)")
                Self.explainCaptureFailure()
                return
            }
            guard let allegato else { return }
            questions.attach([allegato])
            if isShown, !isHUDOpen { bubble.open(focus: .prompt) } else { openHUD() }
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                 userInfo: [.announcement: String(localized: "Allegato: \(allegato.name)"),
                                            .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
    }

    /// Says that the window could not be attached, and the way that always works: no setting to change, because Bubo
    /// asks for no Screen Recording (ADR 0005).
    private static func explainCaptureFailure() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Finestra non allegata")
        alert.informativeText = String(localized: """
            macOS non ha mostrato la scelta della finestra o non ha dato lo scatto. Premi ⌃⌘⇧4, poi Spazio, fai clic \
            sulla finestra e incollala nel prompt con ⌘V.
            """)
        NSApp.activate()
        alert.runModal()
    }

    /// Puts what is dropped on the Orb in the prompt of the bubble, with the Orb in Ascolto; returns whether anything
    /// could be attached.
    private func drop(_ pasteboard: NSPasteboard, into questions: QuestionModel) -> Bool {
        let interval = Signposts.beginInterval(.dropToListening)
        defer { Signposts.endInterval(.dropToListening, interval) }
        isOfferingTranscription = false
        let attachments: [Allegato]
        switch OrbDropTarget.drop(in: pasteboard) {
        case .meetingFiles(let files):
            if questions.attachments.isEmpty { questions.stopAwaitingAttachments() }
            importMeetings(files)
            return true
        case .videoLink(let link):
            // Read now: the pasteboard of a drag does not outlive it, and the link may still become an Allegato.
            let fallback = self.attachments(of: pasteboard)
            if questions.attachments.isEmpty { questions.stopAwaitingAttachments() }
            importVideo(link) { [weak self, questions] in
                questions.awaitAttachments()
                self?.attach(fallback, into: questions)
            }
            return true
        case .attachments:
            attachments = self.attachments(of: pasteboard)
        }
        return attach(attachments, into: questions)
    }

    /// The Allegati of a drop, with a dragged image saved in the Domande's folder.
    private func attachments(of pasteboard: NSPasteboard) -> [Allegato] {
        do {
            let images = try QuestionModel.directory().appending(path: "Allegati", directoryHint: .isDirectory)
            return OrbDropTarget.attachments(from: pasteboard, imageDirectory: images)
        } catch {
            Logger.panel.error("No folder for dropped images: \(error)")
            return []
        }
    }

    /// Puts `attachments` in the prompt of the bubble; returns whether there was anything to attach.
    @discardableResult
    private func attach(_ attachments: [Allegato], into questions: QuestionModel) -> Bool {
        guard !attachments.isEmpty else {
            if questions.attachments.isEmpty { questions.stopAwaitingAttachments() }
            return false
        }
        questions.attach(attachments)
        bubble.open(focus: .prompt)
        // The chips are seen at once; VoiceOver hears what came with the drop.
        let names = attachments.map(\.name).formatted(.list(type: .and))
        let announcement = attachments.count == 1 ? String(localized: "Allegato: \(names)")
            : String(localized: "Allegati: \(names)")
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: announcement,
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
        // For the manual check of focus theft, as for the bubble: kinds and count, never names or paths.
        Logger.panel.info("""
            Dropped \(attachments.map { String(describing: $0.kind) }.joined(separator: ","), privacy: .public); \
            Bubo active \(NSApp.isActive), \
            front \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none", privacy: .public)
            """)
        return true
    }

    @ObservationIgnored private var openHUD: () -> Void = {}
    @ObservationIgnored private weak var questions: QuestionModel?
    @ObservationIgnored private let windowCapture = WindowCapture()
    @ObservationIgnored private var bubbleWindow: PanelBubbleWindow?
    @ObservationIgnored private var statusWindow: PanelStatusWindow?
    /// What the pill would say were it on screen, as last computed from the Sessioni and the Domanda.
    @ObservationIgnored private var pendingStatus: PanelStatus?
    /// Whether media files or a web link are dragged over the Orb: the pill then says what a drop does.
    @ObservationIgnored private var isOfferingTranscription = false {
        didSet { if isOfferingTranscription != oldValue { updateStatus() } }
    }
    @ObservationIgnored private var panel: NSPanel?
    @ObservationIgnored private var view: OrbPanelView?
    @ObservationIgnored private var renderer: OrbRenderer?
    @ObservationIgnored private var placement = PanelPlacement()
    /// The screens' visible frames when the Panel was last placed; they change with the Dock.
    @ObservationIgnored private var visibleFrames: [CGRect] = []

    /// The connected screens, the main one (with the menu bar) first.
    private var screens: [PanelScreen] {
        NSScreen.screens.map { PanelScreen(id: $0.stableID, visibleFrame: $0.visibleFrame) }
    }

    private func startBubble(questions: QuestionModel, hud: HUDPresenter, brainSetup: SecondBrainConversation) {
        let bubble = bubble
        let view = PanelBubbleView(bubble: bubble, model: questions, hud: hud, brainSetup: brainSetup) { [weak self] size in
            self?.placeBubble(size: size)
        }
        let window = PanelBubbleWindow.make(content: view)
        window.onCancel = bubble.close
        bubbleWindow = window

        // The keyboard gone to another window or app: an empty bubble closes, one with a Domanda stays.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: window, queue: .main
        ) { [questions] _ in
            MainActor.assumeIsolated {
                bubble.loseKeyboard(closes: PanelBubble.closesOnLosingKeyboard(
                    prompt: questions.prompt, answer: questions.answer, isAnswering: questions.isAnswering,
                    hasAttachments: !questions.attachments.isEmpty))
            }
        }
        // The window follows the bubble: on screen when it is open, with the keyboard when the prompt asks for it.
        // Put away, the bubble ends the Ascolto of its Allegati, which stay in the prompt.
        Task { [weak self] in
            for await (isOpen, _) in Observations({ (bubble.isOpen, bubble.takesKeyboard) }) {
                if !isOpen { questions.stopAwaitingAttachments() }
                self?.updateBubbleWindow()
            }
        }
        // An answer or a Sintesi parlata that starts with the HUD closed shows in the bubble ("Chiedi a Bubo", voce).
        Task { [weak self] in
            for await (isAnswering, isSpeaking) in Observations({ (questions.isAnswering, questions.subtitle != nil) }) {
                bubble.follow(isAnswering: isAnswering, isSpeaking: isSpeaking,
                              panelIsVisible: self?.panel?.isVisible == true)
            }
        }
    }

    private func updateBubbleWindow() {
        guard let panel, let bubbleWindow else { return }
        guard bubble.isOpen, panel.isVisible else {
            if bubbleWindow.isVisible, isBubbleWindowShown {
                isBubbleWindowShown = false
                // After the fade, so the bubble's own transition is seen; it keeps following the Panel meanwhile.
                bubbleWindow.orderOutFading { [weak panel] in panel?.removeChildWindow(bubbleWindow) }
            }
            return
        }
        if !isBubbleWindowShown {
            isBubbleWindowShown = true
            if !bubbleWindow.isVisible { placeBubble(size: bubbleWindow.frame.size) }
            bubbleWindow.orderFrontFading()
            // A child moves with the Panel while it is dragged.
            panel.addChildWindow(bubbleWindow, ordered: .above)
        }
        if bubble.takesKeyboard, !bubbleWindow.isKeyWindow {
            // Never `NSApp.activate`: the app in front keeps being in front.
            bubbleWindow.makeKey()
            // For the manual check of focus theft: Bubo stays inactive, the app in front does not change.
            Logger.panel.debug("""
                Bubble has the keyboard; Bubo active \(NSApp.isActive), \
                front \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none", privacy: .public)
                """)
        }
    }

    private func startStatus(questions: QuestionModel, hud: HUDPresenter, sessions: SessionStore?) {
        let bubble = bubble
        let view = PanelStatusView(panel: self) { [weak self] status in
            self?.press(status, hud: hud)
        } onResize: { [weak self] size in
            self?.placeStatus(size: size)
        }
        statusWindow = PanelStatusWindow.make(content: view)
        // The Sessioni and the Domanda decide what the pill says; the Orb's VoiceOver value tells the Sessioni too.
        Task { [weak self] in
            for await (status, description) in Observations({
                let all = sessions?.sessions ?? []
                let hasOutcome = !questions.answer.isEmpty || questions.failure != nil
                let status = PanelStatus.status(sessions: all, hasUnseenOutcome: bubble.hasUnseenOutcome && hasOutcome,
                                                questionFailed: questions.failure != nil)
                return (status, PanelStatus.sessionsDescription(of: all))
            }) {
                self?.view?.sessionsDescription = description
                self?.pendingStatus = status
                self?.updateStatus()
            }
        }
        // The bubble says it all while it is open: the pill steps aside.
        Task { [weak self] in
            for await _ in Observations({ bubble.isOpen }) {
                self?.updateStatus()
            }
        }
    }

    /// Follows the pill: the Sessione in the HUD, or the bubble back with its Domanda.
    private func press(_ status: PanelStatus, hud: HUDPresenter) {
        switch status {
        case .waiting(_, let session), .failing(_, let session): hud.show(session: session)
        case .answerReady, .questionFailed: bubble.open(focus: .prompt)
        case .dropHint: break
        }
    }

    /// Shows the pill when there is something to say beside a visible reduced Panel with the bubble closed, and hides
    /// it otherwise; VoiceOver hears it once as it comes.
    private func updateStatus() {
        let isShowable = size == .reduced && !bubble.isOpen && panel?.isVisible == true
        let newStatus = isOfferingTranscription && panel?.isVisible == true ? .dropHint
            : isShowable ? pendingStatus : nil
        guard newStatus != status else { return }
        if status == nil, let newStatus {
            statusAppearance = .appearance(reducesMotion: Motion.isReduced)
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                 userInfo: [.announcement: newStatus.accessibilityLabel,
                                            .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        }
        status = newStatus
        updateStatusWindow()
    }

    private func updateStatusWindow() {
        guard let panel, let statusWindow else { return }
        guard status != nil else {
            if statusWindow.isVisible, isStatusWindowShown {
                isStatusWindowShown = false
                statusWindow.orderOutFading { [weak panel] in panel?.removeChildWindow(statusWindow) }
            }
            return
        }
        guard !isStatusWindowShown else { return }
        isStatusWindowShown = true
        if !statusWindow.isVisible { placeStatus(size: statusWindow.frame.size) }
        statusWindow.orderFrontFading()
        // A child moves with the Panel while it is dragged.
        panel.addChildWindow(statusWindow, ordered: .above)
    }

    /// Puts a pill of `size` beside the Orb, toward the screen's center.
    private func placeStatus(size: CGSize) {
        guard let panel, let statusWindow, let screen = panel.screen ?? NSScreen.main else { return }
        let frame = PanelStatusLayout.frame(ofSize: size, besidePanel: panel.frame, in: zone,
                                            visibleFrame: screen.visibleFrame)
        if frame != statusWindow.frame { statusWindow.setFrame(frame, display: true) }
    }

    /// Puts a bubble of `size` beside the Panel, toward the screen's center.
    private func placeBubble(size: CGSize) {
        guard let panel, let bubbleWindow, let screen = panel.screen ?? NSScreen.main else { return }
        let frame = PanelBubbleLayout.frame(ofSize: size, besidePanel: panel.frame, in: zone,
                                            visibleFrame: screen.visibleFrame)
        if frame != bubbleWindow.frame { bubbleWindow.setFrame(frame, display: true) }
    }

    /// Switches the Panel to `newSize` on the screen it is on, in place in its zone, and remembers it.
    private func resize(to newSize: PanelSize) {
        guard newSize != size, panel != nil, let spot = placement.resize(to: newSize, among: screens) else { return }
        savePlacement()
        // With Riduci movimento the change is immediate.
        move(to: spot, animated: !Motion.isReduced)
    }

    private func moveToRememberedSpot() {
        visibleFrames = NSScreen.screens.map(\.visibleFrame)
        guard let spot = placement.spot(among: screens) else { return }
        move(to: spot, animated: false)
    }

    /// Puts the Panel back in its zone when a screen's visible frame has changed, as when the Dock moves.
    private func followVisibleFrames() {
        guard NSScreen.screens.map(\.visibleFrame) != visibleFrames else { return }
        moveToRememberedSpot()
    }

    private func snapAfterDrag() {
        guard let panel,
              let spot = placement.drop(center: CGPoint(x: panel.frame.midX, y: panel.frame.midY), among: screens)
        else { return }
        savePlacement()
        move(to: spot, animated: !Motion.isReduced)
    }

    private func savePlacement() {
        do {
            UserDefaults.standard.set(try JSONEncoder().encode(placement), forKey: Self.placementKey)
        } catch {
            Logger.panel.error("Panel placement not saved: \(error)")
        }
    }

    private func move(to spot: PanelSpot, animated: Bool) {
        zone = spot.zone
        size = spot.size
        bubble.side = spot.zone.bubbleSide
        bubble.maxHeight = PanelBubbleLayout.maxHeight(in: spot.screen.visibleFrame)
        if let view {
            view.size = spot.size
            let pixels = spot.size.side * spot.size.renderScale
            view.drawableSize = CGSize(width: pixels, height: pixels)
        }
        panel?.setFrame(spot.panelFrame, display: true, animate: animated)
        if let bubbleWindow, bubbleWindow.isVisible { placeBubble(size: bubbleWindow.frame.size) }
        if let statusWindow, statusWindow.isVisible { placeStatus(size: statusWindow.frame.size) }
        updateStatus()
        updateClickThrough()
    }

    /// Lets clicks through to the windows below unless the pointer is in the click circle.
    private func updateClickThrough() {
        guard let panel else { return }
        let isPointerOnOrb = panel.isVisible
            && PanelClickCircle.contains(NSEvent.mouseLocation, inPanel: panel.frame, of: size)
        panel.ignoresMouseEvents = !isPointerOnOrb
        // Only on the way in or out: a pointer elsewhere must not cut the launch greeting short.
        if isPointerOnOrb != wasPointerOnOrb {
            wasPointerOnOrb = isPointerOnOrb
            OrbControls.shared.hover(isPointerInside: isPointerOnOrb)
        }
    }

    /// Whether the Panel, the bubble and the pill were last asked on screen: while one fades out it is still visible.
    @ObservationIgnored private var isPanelShown = false
    @ObservationIgnored private var isBubbleWindowShown = false
    @ObservationIgnored private var isStatusWindowShown = false

    /// Whether the pointer was on the Orb at the last move, so the owl follows only entering and leaving.
    @ObservationIgnored private var wasPointerOnOrb = false

    private var isHUDOpen: Bool {
        NSApp.windows.contains {
            $0.identifier?.rawValue.hasPrefix(HUDPresenter.windowID) == true && $0.isVisible && !$0.isMiniaturized
        }
    }

    private func updateVisibility() {
        guard let panel else { return }
        let isHUDOpen = isHUDOpen
        // The Domanda goes on in the HUD, where the user sees how it ended: the bubble grows into it.
        if isHUDOpen {
            bubble.closeIntoHUD()
            bubble.markOutcomeSeen()
        }
        let wantsPanel = isShown && !isHUDOpen
        if wantsPanel != isPanelShown {
            isPanelShown = wantsPanel
            if wantsPanel {
                panel.orderFrontFading()
            } else {
                // Once out, the Orb stops rendering.
                panel.orderOutFading { [weak self] in self?.updateVisibility() }
            }
        }
        renderer?.isVisible = panel.isVisible && panel.occlusionState.contains(.visible)
        updateBubbleWindow()
        updateStatus()
    }
}

/// The Panel's window, which snaps and changes size at the container's pace.
private final class OrbPanel: NSPanel {
    override func animationResizeTime(_ newFrame: NSRect) -> TimeInterval {
        Motion.panelFrameChange
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
