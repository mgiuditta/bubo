import Foundation
import Testing
@testable import Bubo

struct QuotaTests {
    static let fiveHour = Quota.Window(used: 0.2, resetsAt: Date(timeIntervalSince1970: 1_790_852_400))
    static let sevenDay = Quota.Window(used: 0.02, resetsAt: Date(timeIntervalSince1970: 1_791_428_400))

    @Test func aReportReplacesOnlyTheWindowsItCarries() {
        let known = Quota(fiveHour: Self.fiveHour, sevenDay: Self.sevenDay)
        let newer = Quota.Window(used: 0.25, resetsAt: Self.fiveHour.resetsAt)
        #expect(known.merging(Quota(fiveHour: newer)) == Quota(fiveHour: newer, sevenDay: Self.sevenDay))
    }

    @Test func anEmptyReportKeepsWhatIsKnown() {
        #expect(Quota().merging(Quota()) == Quota())
        #expect(Quota(sevenDay: Self.sevenDay).merging(Quota()) == Quota(sevenDay: Self.sevenDay))
    }
}

struct QuotaSavingTests {
    private let defaults = UserDefaults(suiteName: "QuotaSavingTests-\(UUID())")!

    @Test func theSavedQuotaComesBackWhole() {
        let quota = Quota(fiveHour: QuotaTests.fiveHour, sevenDay: QuotaTests.sevenDay)
        quota.save(to: defaults)
        #expect(Quota.saved(in: defaults) == quota)
    }

    @Test func withNothingSavedTheQuotaIsEmpty() {
        #expect(Quota.saved(in: defaults) == Quota())
    }

    @Test func anUnreadableSaveGivesAnEmptyQuota() {
        defaults.set(Data("non è JSON".utf8), forKey: Quota.defaultsKey)
        #expect(Quota.saved(in: defaults) == Quota())
    }

    // Shown at launch until `claude` reports a newer one: no `claude` starts for it.
    @Test func aDomandaStartsFromTheQuotaSavedAtTheLastLaunch() {
        let quota = Quota(sevenDay: QuotaTests.sevenDay)
        quota.save(to: defaults)
        #expect(QuestionModel(defaults: defaults).quota == quota)
    }
}
