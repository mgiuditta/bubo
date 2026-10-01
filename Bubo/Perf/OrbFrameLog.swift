import Foundation
import os

/// The GPU time of every frame the Panel's Orb draws, written to a file for the performance tests.
///
/// One line per frame, the GPU time in seconds, so the line count is the number of frames drawn.
/// Off unless Bubo is launched with `-orbFrameLog <path>`.
final class OrbFrameLog {
    /// The `UserDefaults` key, set from the launch arguments, with the path of the file.
    static let defaultsKey = "orbFrameLog"

    private let file: FileHandle

    /// Creates a log that writes to `url`, emptying the file if it exists.
    ///
    /// - Throws: An error if the file cannot be opened for writing.
    init(url: URL) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        file = try FileHandle(forWritingTo: url)
    }

    /// The log the launch arguments ask for, or `nil` when they ask for none or the file cannot be opened.
    static func fromLaunchArguments() -> OrbFrameLog? {
        guard let path = UserDefaults.standard.string(forKey: defaultsKey) else { return nil }
        do {
            return try OrbFrameLog(url: URL(filePath: path))
        } catch {
            Logger.perf.error("Orb frame log not opened: \(error)")
            return nil
        }
    }

    /// Writes the GPU time of one frame.
    func record(gpuTime: TimeInterval) {
        do {
            try file.write(contentsOf: Data("\(gpuTime)\n".utf8))
        } catch {
            Logger.perf.error("Orb frame not logged: \(error)")
        }
    }

    /// Morphs `controls` from one Variante of the Catalogo to the next until the task is cancelled,
    /// so the frames logged are Morph frames.
    static func keepMorphing(_ controls: OrbControls) async {
        let varianti: [Variante]
        do {
            varianti = try Catalogo(bundle: .main).varianti
        } catch {
            Logger.perf.error("Catalogo unavailable, the Orb stays Blob: \(error)")
            return
        }
        // A Morph, then the least hold on its Variante: the next request starts the next Morph at once.
        let period = Duration.seconds(MorphDirector.morphDuration + MorphDirector.minimumHold)
        for variante in repeatElement(varianti, count: .max).joined() {
            controls.variante = variante
            do {
                try await Task.sleep(for: period)
            } catch {
                return
            }
        }
    }
}

private extension Logger {
    static let perf = Logger(subsystem: "com.mgiuditta.bubo", category: "perf")
}
