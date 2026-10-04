import AppKit
import os
import SwiftUI
import UniformTypeIdentifiers

/// The Costi window, outside the HUD like the Cronologia: opened from the Finestra menu, the Palette and the Quota in
/// the HUD, with no shortcut (spec 18).
final class CostsWindow {
    private let ledger: CostLedger
    private let cliHistory: CLIHistoryCosts
    private let sessionTitle: (UUID) -> String?
    private lazy var window = makeWindow()

    /// Creates the window, built at its first opening.
    ///
    /// - Parameters:
    ///   - ledger: The turns of Bubo shown.
    ///   - cliHistory: The turns of the Cronologia CLI shown, apart from the ledger.
    ///   - sessionTitle: The title of a Sessione still in Bubo.
    init(ledger: CostLedger, cliHistory: CLIHistoryCosts = CLIHistoryCosts(makeReader: CLIHistoryCosts.userReader),
         sessionTitle: @escaping (UUID) -> String?) {
        self.ledger = ledger
        self.cliHistory = cliHistory
        self.sessionTitle = sessionTitle
    }

    /// Brings the window forward, as it was left, and reads the Cronologia CLI again.
    func show() {
        cliHistory.reload()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1_000, height: 720),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: true)
        window.title = String(localized: "Costi")
        window.contentViewController = NSHostingController(rootView: CostsView(
            ledger: ledger, cliHistory: cliHistory, sessionTitle: sessionTitle) { [weak self] csv in self?.save(csv) })
        // Dark like the rest of Bubo, whatever the system's appearance.
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        // The Finestra menu already has its own Costi item, which also opens it when closed.
        window.isExcludedFromWindowsMenu = true
        if !window.setFrameUsingName("Costi") { window.center() }
        window.setFrameAutosaveName("Costi")
        return window
    }

    /// Asks where to save `csv`, as a sheet of the window.
    private func save(_ csv: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = String(localized: "Costi di Bubo") + ".csv"
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try Data(csv.utf8).write(to: url, options: .atomic)
            } catch {
                Logger.costs.error("CSV not saved: \(error)")
                NSAlert(error: error).runModal()
            }
        }
    }
}
