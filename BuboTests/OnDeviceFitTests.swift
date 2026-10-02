import Foundation
import FoundationModels
import Synchronization
import Testing
@testable import Bubo

extension OnDeviceModel {
    /// Apple Intelligence off: nothing is measured, nothing answers on the Mac.
    static let off = OnDeviceModel(isAvailable: { false }, tokenCount: { _ in nil })
    /// A model that is on and counts every text as 100 tokens: everything fits.
    static let fitting = OnDeviceModel(isAvailable: { true }, tokenCount: { _ in 100 })

    /// A model that is on and counts `tokens`, or cannot count (macOS before 26.4) when `nil`.
    static func counting(_ tokens: Int?) -> OnDeviceModel {
        OnDeviceModel(isAvailable: { true }, tokenCount: { _ in tokens })
    }
}

struct OnDeviceFitTests {
    @Test func twoThousandTokensFitAndOneMoreDoesNot() async {
        #expect(await OnDeviceModel.counting(2_000).fit(of: "allegato") == .fits(tokens: 2_000))
        #expect(await OnDeviceModel.counting(2_001).fit(of: "allegato") == .tooLong(tokens: 2_001))
    }

    // Before macOS 26.4 there is no count: never an estimate from the characters, however long the text.
    @Test func withoutTokenCountNothingIsEstimated() async {
        let long = String(repeating: "parola ", count: 10_000)
        #expect(await OnDeviceModel.counting(nil).fit(of: long) == .notMeasurable)
        #expect(await OnDeviceModel.counting(nil).fit(of: "breve") == .notMeasurable)
    }

    @Test func aCountThatFailsIsNotMeasurable() async {
        struct Broken: Error {}
        let model = OnDeviceModel(isAvailable: { true }, tokenCount: { _ in throw Broken() })
        #expect(await model.fit(of: "allegato") == .notMeasurable)
    }

    @Test func anUnavailableModelIsNeverMeasured() async {
        let counted = Mutex(false)
        let model = OnDeviceModel(isAvailable: { false }, tokenCount: { _ in
            counted.withLock { $0 = true }
            return 10
        })
        #expect(await model.fit(of: "allegato") == .unavailable)
        #expect(!counted.withLock { $0 })
    }

    @Test(.timeLimit(.minutes(1)))
    func aCountPastItsBudgetIsGivenUp() async {
        let model = OnDeviceModel(countBudget: .milliseconds(50), isAvailable: { true }, tokenCount: { _ in
            try await Task.sleep(for: .seconds(30))
            return 10
        })
        let clock = ContinuousClock()
        let start = clock.now
        #expect(await model.fit(of: "allegato") == .notMeasurable)
        #expect(clock.now - start < .seconds(5))
    }
}

/// Runs only on a Mac with Apple Intelligence on and macOS 26.4: the real model counts and answers.
///
/// Criterion 2 of #89: an Allegato of 2,000 tokens leaves room for a complete answer in Italian. The answers go in
/// the test's attachments for a person to read: one cut short or not in Italian means lowering `attachmentLimit`.
@Suite(.enabled(if: SystemLanguageModel.default.isAvailable, "Apple Intelligence is not available on this Mac"),
       .enabled(if: ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 26, minorVersion: 4,
                                                                                         patchVersion: 0)),
                "Counting tokens needs macOS 26.4"),
       .timeLimit(.minutes(5)))
struct FoundationModelsAnswererLiveTests {
    static let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    /// Italian prose from the specs, cut paragraph by paragraph to just under the limit, as the model counts it.
    static func attachment(from path: String, model: OnDeviceModel) async throws -> Allegato? {
        guard #available(macOS 26.4, *) else { return nil }
        var paragraphs = try String(contentsOf: root.appending(path: path), encoding: .utf8)
            .components(separatedBy: "\n\n")
        while !paragraphs.isEmpty {
            let text = paragraphs.joined(separator: "\n\n")
            if try await model.model.tokenCount(for: text) <= OnDeviceModel.attachmentLimit {
                return Allegato(name: URL(filePath: path).lastPathComponent, text: text)
            }
            paragraphs.removeLast()
        }
        return nil
    }

    @Test(arguments: [
        ("docs/features/10-router.md", "In una frase: di cosa parla questo testo?"),
        ("docs/features/10-router.md", "Riassumi questo testo."),
        ("docs/features/09-sistema.md", "Riassumi questo testo."),
    ])
    func twoThousandTokensLeaveACompleteItalianAnswer(path: String, question: String) async throws {
        let model = OnDeviceModel()
        let attachment = try #require(try await Self.attachment(from: path, model: model))
        var answer = ""
        for try await chunk in FoundationModelsAnswerer(model: model).answer(to: question, attachments: [attachment]) {
            answer += chunk
        }
        Attachment.record(answer, named: "\(question) \(attachment.name).txt")
        let last = try #require(answer.trimmingCharacters(in: .whitespacesAndNewlines).last)
        #expect(".!?»)".contains(last), "\(answer)")
    }
}
