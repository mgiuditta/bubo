import Foundation
import Testing
@testable import Bubo

/// The Palette's filters written in the box, its highlights and where its window goes.
struct PaletteTests {
    @Test(arguments: [
        ("@bubo", PaletteFilter.project("bubo")),
        ("7g", .days(7)),
        ("30G", .days(30)),
        ("cli", .source(.cli)),
        ("sessioni", .source(.session)),
    ])
    func aWordNamesAFilter(word: String, filter: PaletteFilter) {
        #expect(PaletteFilter(word) == filter)
    }

    @Test(arguments: ["@", "g", "0g", "settegiorni", "login", "client"])
    func otherWordsAreSearched(word: String) {
        #expect(PaletteFilter(word) == nil)
    }

    @Test func aFilterFollowedByASpaceBecomesAGettone() {
        var query = PaletteQuery()
        query.text = "login @bubo 7g"
        query.absorbFilters()
        // `7g` is still being written: it stays text, but it already filters.
        #expect(query.filters == [.project("bubo")])
        #expect(query.text == "login 7g")
        #expect(query.search.text == "login")
        #expect(query.search.filters == [.project("bubo"), .days(7)])

        query.text += " "
        query.absorbFilters()
        #expect(query.filters == [.project("bubo"), .days(7)])
        #expect(query.text == "login ")
    }

    @Test func aNewFilterReplacesOneOfTheSameKind() {
        var query = PaletteQuery()
        query.text = "7g cli 30g "
        query.absorbFilters()
        #expect(query.filters == [.source(.cli), .days(30)])
        #expect(query.text.isEmpty)

        query.removeLastFilter()
        #expect(query.filters == [.source(.cli)])
        query.remove(.source(.cli))
        #expect(query.isEmpty)
    }

    @Test func searchedWordsAreHighlightedIgnoringCaseAndAccents() {
        let text = "La Città di notarizzazione, non la notte."
        let words = MatchHighlight.ranges(in: text, matching: ["citta", "NOTAR"]).map { String(text[$0]) }
        #expect(words == ["Città", "notarizzazione"])
    }

    @Test func theExcerptStartsNearTheFirstMatch() {
        let text = String(repeating: "parola ", count: 40) + "Briciola è il gatto.\nFine."
        let excerpt = MatchHighlight.excerpt(of: text, matching: ["briciola"], length: 80)
        #expect(excerpt.hasPrefix("…"))
        #expect(excerpt.contains("Briciola è il gatto. Fine."))
        #expect(MatchHighlight.excerpt(of: "breve", matching: ["breve"]) == "breve")
    }

    @Test func thePaletteOpensNearTheTopOfTheHUD() {
        let screen = CGRect(x: 0, y: 0, width: 1_600, height: 1_000)
        let frame = PaletteWindow.frame(of: CGSize(width: 780, height: 480),
                                        over: CGRect(x: 200, y: 100, width: 1_200, height: 800), in: screen)
        #expect(frame.midX == 800)
        #expect(abs(frame.maxY - 780) < 0.001)
    }

    @Test func overThePanelThePaletteStaysOnScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1_600, height: 1_000)
        let frame = PaletteWindow.frame(of: CGSize(width: 780, height: 480),
                                        over: CGRect(x: 1_340, y: 740, width: 240, height: 240), in: screen)
        #expect(screen.contains(frame))
        #expect(frame.maxX == 1_600)
    }
}
