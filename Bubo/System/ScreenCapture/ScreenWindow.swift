import CoreGraphics

/// A window on screen as CoreGraphics lists it: its app and frame, which need no permission; never its title or pixels.
nonisolated struct ScreenWindow: Equatable, Sendable {
    /// The window number, the same as `SCWindow.windowID`.
    let id: CGWindowID
    /// The process that owns it.
    let processID: pid_t
    /// The name of the app that owns it, when CoreGraphics tells it.
    let appName: String?
    /// Where it is, in points, with the origin at the top left of the primary screen.
    let frame: CGRect
    /// Its window level; 0 for the windows of documents and apps.
    let layer: Int

    /// Creates a window with these values.
    init(id: CGWindowID, processID: pid_t, appName: String?, frame: CGRect, layer: Int) {
        self.id = id
        self.processID = processID
        self.appName = appName
        self.frame = frame
        self.layer = layer
    }

    /// Creates the window that `info`, one entry of `CGWindowListCopyWindowInfo`, describes; `nil` when an entry is
    /// missing.
    init?(info: [String: Any]) {
        guard let id = info[kCGWindowNumber as String] as? Int, let processID = info[kCGWindowOwnerPID as String] as? Int,
              let bounds = info[kCGWindowBounds as String] as? [String: Any],
              let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
              let layer = info[kCGWindowLayer as String] as? Int
        else { return nil }
        self.init(id: CGWindowID(id), processID: pid_t(processID), appName: info[kCGWindowOwnerName as String] as? String,
                  frame: frame, layer: layer)
    }

    /// The windows on screen, front to back.
    static func onScreen() -> [ScreenWindow] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        return (list as? [[String: Any]] ?? []).compactMap(ScreenWindow.init(info:))
    }

    /// Returns the frontmost app window of `windows`, listed front to back, that contains `point`, skipping those of
    /// `excludedProcess`; `nil` over the desktop.
    static func frontmost(at point: CGPoint, in windows: [ScreenWindow], excludingProcess excludedProcess: pid_t)
        -> ScreenWindow? {
        windows.first { $0.layer == 0 && $0.processID != excludedProcess && $0.frame.contains(point) }
    }

    /// Returns `location`, with AppKit's origin at the bottom left of the primary screen as in `NSEvent.mouseLocation`,
    /// in CoreGraphics' space, with the origin at its top left.
    static func point(fromScreenLocation location: CGPoint, primaryScreenHeight: CGFloat) -> CGPoint {
        CGPoint(x: location.x, y: primaryScreenHeight - location.y)
    }
}
