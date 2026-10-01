import Foundation

// The report of scripts/perf.sh, built against BuboPerfTests/PerfBudgets.swift.
//
//   perf-report metal-hud <messages>          A reading of the Orb's GPU time from the metal-HUD lines in <messages>.
//   perf-report launch-time <start> <events>  A cold-launch reading: from <start>, seconds since 1970, to the first
//                                             "HUD interattivo" signpost in <events>, `log show --style ndjson`.
//   perf-report report <readings> <output>    report.md and report.json in <output> from the JSON readings in
//                                             <readings>; exits with 1 when a budget is not kept.

let usage = "uso: perf-report metal-hud <messaggi> | launch-time <inizio> <eventi> | report <letture> <uscita>"

func write(_ measurement: PerfMeasurement) throws {
    FileHandle.standardOutput.write(try JSONEncoder().encode(measurement))
    print()
}

func firstInteractiveHUD(in events: String) throws -> Date? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSZ"
    return try events.split(separator: "\n").lazy.compactMap { line -> Date? in
        let event = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        guard event?["signpostName"] as? String == "HUD interattivo",
              let timestamp = event?["timestamp"] as? String else { return nil }
        return formatter.date(from: timestamp)
    }.min()
}

func readings(in folder: URL) throws -> [PerfMeasurement] {
    let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
    return try files.filter { $0.pathExtension == "json" }.map { file in
        try JSONDecoder().decode(PerfMeasurement.self, from: Data(contentsOf: file))
    }
}

do {
    let arguments = CommandLine.arguments.dropFirst()
    switch (arguments.first, arguments.count) {
    case ("metal-hud", 2):
        let messages = try String(contentsOf: URL(filePath: arguments.last!), encoding: .utf8)
        let log = MetalHUDLog(lines: messages.split(separator: "\n"))
        if let p95 = log.gpuTimePercentile95, let rate = log.framesPerSecond {
            let fps = rate.formatted(.number.precision(.fractionLength(0)))
            try write(PerfMeasurement(.orbGPUTime, value: p95,
                                      from: "Metal HUD: \(log.frames.count) fotogrammi, \(fps) fps medi"))
        } else {
            try write(PerfMeasurement(skipping: .orbGPUTime, because: "Nessuna riga metal-HUD nel log di sistema"))
        }
    case ("launch-time", 3):
        let start = Date(timeIntervalSince1970: Double(arguments.dropFirst().first!) ?? .nan)
        let events = try String(contentsOf: URL(filePath: arguments.last!), encoding: .utf8)
        if let end = try firstInteractiveHUD(in: events), end > start {
            try write(PerfMeasurement(.coldLaunch, value: end.timeIntervalSince(start) * 1000,
                                      from: "perf.sh --freddo, da open al segnale HUD interattivo"))
        } else {
            try write(PerfMeasurement(skipping: .coldLaunch, because: "Nessun segnale HUD interattivo dopo l'avvio"))
        }
    case ("report", 3):
        let output = URL(filePath: arguments.last!)
        let report = BudgetReport(measurements: try readings(in: URL(filePath: arguments.dropFirst().first!)))
        try report.markdown.write(to: output.appending(path: "report.md"), atomically: true, encoding: .utf8)
        try report.json().write(to: output.appending(path: "report.json"))
        print(report.markdown, terminator: "")
        exit(report.isWithinBudgets ? 0 : 1)
    default:
        FileHandle.standardError.write(Data("\(usage)\n".utf8))
        exit(64)
    }
} catch {
    FileHandle.standardError.write(Data("perf-report: \(error)\n".utf8))
    exit(70)
}
