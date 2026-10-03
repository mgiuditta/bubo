import AppKit
import ImageIO
import os
import ScreenCaptureKit
import UniformTypeIdentifiers

/// «Allega finestra» (#485, #103): the system's window picker, one click on the window under the cursor, one shot of it
/// as an Allegato.
///
/// The picker is the user's choice, so Bubo needs no Screen Recording, which `claude` would inherit (ADR 0005); and no
/// Accessibility either, so no text of the element under the cursor: the selected text comes with «Chiedi a Bubo».
final class WindowCapture: NSObject, SCContentSharingPickerObserver {
    /// Why no window was attached.
    enum Failure: Error {
        /// The system did not show the picker.
        case pickerUnavailable(any Error)
        /// The picked window could not be shot.
        case captureFailed(any Error)
        /// The shot could not be saved.
        case notSaved
    }

    /// Shows the picker and returns the Allegato of the window the user clicks, saved as a PNG in a new folder inside
    /// `directory`; `nil` when the user cancels, or when the picker is already on screen.
    func attachment(savingIn directory: URL) async throws(Failure) -> Allegato? {
        guard pending == nil else { return nil }
        // Before the picker: the window that should take the click, for the log only.
        let expected = NSScreen.screens.first.flatMap { primary in
            ScreenWindow.frontmost(
                at: ScreenWindow.point(fromScreenLocation: NSEvent.mouseLocation, primaryScreenHeight: primary.frame.height),
                in: ScreenWindow.onScreen(), excludingProcess: ProcessInfo.processInfo.processIdentifier)
        }
        let picker = SCContentSharingPicker.shared
        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = .singleWindow
        configuration.excludedBundleIDs = [Bundle.main.bundleIdentifier].compactMap(\.self)
        configuration.allowsChangingSelectedContent = false
        picker.defaultConfiguration = configuration
        picker.add(self)
        picker.isActive = true
        // Off as soon as it is done, picked or not, so the capture indicator goes away.
        defer {
            picker.isActive = false
            picker.remove(self)
        }
        let picked: Picked?
        do {
            picked = try await withCheckedThrowingContinuation { continuation in
                pending = continuation
                picker.present(using: .window)
            }
        } catch {
            throw .pickerUnavailable(error)
        }
        guard let picked else { return nil }
        Logger.capture.info("Picked the window under the cursor: \(picked.windowID == expected?.id, privacy: .public)")
        let image: CGImage
        do {
            image = try await SCScreenshotManager.captureImage(contentFilter: picked.filter,
                                                               configuration: picked.configuration)
        } catch {
            throw .captureFailed(error)
        }
        guard let url = Self.save(image, named: Self.fileName(forApp: picked.appName ?? expected?.appName),
                                  in: directory)
        else { throw .notSaved }
        return Allegato(fileAt: url)
    }

    /// Returns the name of the shot of a window of `appName`, without extension, such as «Finestra di Safari».
    nonisolated static func fileName(forApp appName: String?) -> String {
        // A slash or a colon would end the name early in the path.
        let app = appName?.replacing(/[\/:]/, with: "-").trimmingCharacters(in: .whitespaces)
        guard let app, !app.isEmpty else {
            return String(localized: "Finestra", comment: "File name of a window shot, before .png")
        }
        return String(localized: "Finestra di \(app)", comment: "File name of a window shot of an app, before .png")
    }

    // MARK: - Picker

    /// The window the user picked, with what its shot needs.
    private struct Picked {
        let filter: SCContentFilter
        /// The size of the shot in pixels: the window at full resolution.
        let pixelSize: CGSize
        let windowID: CGWindowID?
        let appName: String?

        /// The shot at full resolution, without the cursor.
        var configuration: SCStreamConfiguration {
            let configuration = SCStreamConfiguration()
            configuration.width = Int(pixelSize.width)
            configuration.height = Int(pixelSize.height)
            configuration.showsCursor = false
            return configuration
        }
    }

    private var pending: CheckedContinuation<Picked?, any Error>?

    private func finish(_ result: sending Result<Picked?, any Error>) {
        pending?.resume(with: result)
        pending = nil
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor in finish(.success(nil)) }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter,
                                          for stream: SCStream?) {
        let scale = CGFloat(filter.pointPixelScale)
        let pixelSize = CGSize(width: filter.contentRect.width * scale, height: filter.contentRect.height * scale)
        let window = filter.includedWindows.first
        let windowID = window?.windowID
        let appName = window?.owningApplication?.applicationName
        // SCContentFilter is not Sendable, but the picker hands over a filter it no longer changes, and only the main
        // actor reads it from here on.
        nonisolated(unsafe) let filter = filter
        Task { @MainActor in
            finish(.success(Picked(filter: filter, pixelSize: pixelSize, windowID: windowID, appName: appName)))
        }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: any Error) {
        Task { @MainActor in finish(.failure(error)) }
    }

    // MARK: - Saving

    /// Saves `image` as `name`.png in a new folder inside `directory`, so the chip shows a plain name and no shot
    /// overwrites another; `nil` when it cannot be written.
    private static func save(_ image: CGImage, named name: String, in directory: URL) -> URL? {
        let folder = directory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let url = folder.appending(path: name).appendingPathExtension("png")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            Logger.capture.error("No folder for the window shot: \(error)")
            return nil
        }
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? url : nil
    }
}

private extension Logger {
    static let capture = Logger(subsystem: "com.mgiuditta.bubo", category: "capture")
}
