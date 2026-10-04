# Finestra Casa = Cervello Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** La finestra grande di Bubo diventa due colonne: a sinistra Cervello, Neuroni, Riunioni, un elenco unico di Domande e Sessioni e i Progetti; a destra la conversazione aperta, che si continua lì.

**Architecture:** Prima i modelli, ognuno testabile da solo: le Domande finite si salvano (`QuestionArchive`), una Sessione aperta accetta un nuovo turno (`SessionStore.send`), un elenco unico le mette insieme per giorno (`ConversationList`), il Destinatario dice a chi va il testo, e la proposta di Sessione nasce anche dal nome di un Progetto nel testo. Poi il guscio `NavigationSplitView` sostituisce il corpo di `HUDView` tenendone fogli, onboarding e drop; infine le viste di destra, la Bolla che apre la conversazione giusta e la rimozione di Orbita, Striscia e anelli.

**Tech Stack:** Swift 6.2 (isolamento predefinito MainActor), SwiftUI macOS 26 (`NavigationSplitView`, Liquid Glass), Swift Testing, XCTest per l'UI test, XcodeGen.

**Spec:** `docs/superpowers/specs/2026-10-04-casa-cervello-design.md`, sezione 1. ADR 0013. Dipende dal brand kit (PR #694): `Spacing`, `Font.bubo*`, `GlassCapsuleButton`.

## Global Constraints

- Solo scuro (`.preferredColorScheme(.dark)`), `tint(Palette.accent)`, colore solo dell'Orb (ADR 0004).
- Token: `Spacing.xxs…xxl`, `Spacing.sidebarRowMinHeight` (36), `Spacing.readingWidth` (720); caratteri `Font.buboDisplay/buboTitle/buboBody/buboInterface/buboData`. Niente numeri a mano nelle viste nuove.
- Clic su un elemento delle Conversazioni = apre quella conversazione a destra, con il composer.
- Il chip del Destinatario dice sempre a chi si scrive: `Cervello` o il nome del Progetto.
- La Domanda trasformata in Sessione resta nell'elenco con il link alla Sessione nata da lei.
- Orbita, Striscia, la scelta della Vista e `HUDRings` spariscono; la Board resta come «Lavoro».
- Bolla e Panel restano; «Apri la chat completa» apre la finestra su quella conversazione.
- Testi in italiano nel String Catalog, inglese tradotto; `scripts/polish-check.sh` passa.
- Comando di test di una suite: `xcodegen generate --quiet && xcodebuild -project Bubo.xcodeproj -scheme Bubo -destination "platform=macOS,arch=arm64" -derivedDataPath .build/DerivedData -skipPackagePluginValidation -allowProvisioningUpdates -quiet test -only-testing:BuboTests/<Suite>`
- Commit in italiano, chiusi da `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## File

| File | Responsabilità |
|---|---|
| `Bubo/Question/QuestionArchive.swift` (nuovo) | Domande finite su disco (JSON in Application Support), lette e scritte |
| `Bubo/Question/QuestionModel.swift` (modifica) | archivia la Domanda in `startNewQuestion()`; carica una Domanda passata per continuarla |
| `Bubo/Sessions/SessionStore.swift` (modifica) | `send(_:to:)` pubblico; `Session.originQuestion` |
| `Bubo/Sessions/Session.swift` (modifica) | `originQuestion: UUID?` |
| `Bubo/Window/ConversationList.swift` (nuovo) | elenco unico, raggruppato per giorno |
| `Bubo/Window/Recipient.swift` (nuovo) | Destinatario: Cervello o Progetto |
| `Bubo/Intake/SessionProposal.swift` (modifica) | proposta anche dal nome di un Progetto nel testo |
| `Bubo/Window/SidebarSelection.swift` (nuovo) | cosa è scelto nella barra laterale |
| `Bubo/Window/MainSidebar.swift` (nuovo) | barra laterale |
| `Bubo/Window/ConversationRow.swift` (nuovo) | riga di Domanda o Sessione |
| `Bubo/Window/HomeView.swift` (nuovo) | casa vuota: Orb grande, «Chiedi al tuo cervello», suggerimenti |
| `Bubo/Window/QuestionDetail.swift` (nuovo) | Domanda aperta, con composer |
| `Bubo/Window/SessionDetail.swift` (nuovo) | Sessione aperta, trascrizione e composer |
| `Bubo/Window/RecipientChip.swift` (nuovo) | chip del Destinatario |
| `Bubo/HUD/HUDView.swift` (modifica) | il corpo diventa `NavigationSplitView`; fogli, drop e onboarding restano |
| `Bubo/HUD/HUDPresenter` (modifica, file dove vive) | `selection: SidebarSelection`, `show(session:)` e `show(question:)` la impostano |
| `Bubo/HUD/SessionOrbit.swift`, `SessionStrip.swift`, `HUDRings.swift`, `VistaDelleSessioni.swift` (eliminati) | via con ADR 0013 |
| `BuboUITests/MainWindowUITests.swift` (nuovo) | clic su una Sessione → conversazione e chip del Progetto |
| `CONTEXT.md`, `docs/design-system.md` | HUD, Vista delle Sessioni, Destinatario |

## Parallelismo

- Gruppo A (file disgiunti, insieme): Task 1, Task 2, Task 4, Task 5.
- Task 3 dopo il Task 1. Task 6 dopo A e 3.
- Gruppo B (dopo il Task 6, insieme): Task 7, Task 8, Task 9.
- Task 10 e 11 per ultimi, in serie.

---

### Task 1: Le Domande finite si salvano

**Files:**
- Create: `Bubo/Question/QuestionArchive.swift`
- Modify: `Bubo/Question/QuestionModel.swift` (`startNewQuestion()`, init)
- Test: `BuboTests/QuestionArchiveTests.swift`

**Interfaces:**
- Produces: `struct ArchivedQuestion: Codable, Identifiable, Equatable, Sendable { let id: UUID; var title: String; var date: Date; var turns: [QuestionTurn]; var sessionID: UUID? }`, `final class QuestionArchive` con `init(file: URL)`, `var questions: [ArchivedQuestion]` (più recenti prima), `func save(_:)`, `func linkSession(_ session: UUID, toQuestion: UUID)`, `static func live() throws -> QuestionArchive`. `QuestionTurn` diventa `Codable`.

- [ ] **Step 1: Test che fallisce**

```swift
import Foundation
import Testing
@testable import Bubo

struct QuestionArchiveTests {
    private func file() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "domande-\(UUID().uuidString).json")
    }

    @Test func aSavedQuestionIsReadBackNewestFirst() throws {
        let file = file()
        let archive = QuestionArchive(file: file)
        let old = ArchivedQuestion(id: UUID(), title: "Meteo", date: .distantPast,
                                   turns: [QuestionTurn(prompt: "Meteo", answer: "Sole")], sessionID: nil)
        let new = ArchivedQuestion(id: UUID(), title: "Treni", date: .now,
                                   turns: [QuestionTurn(prompt: "Treni", answer: "18:02")], sessionID: nil)
        archive.save(old)
        archive.save(new)
        #expect(QuestionArchive(file: file).questions.map(\.title) == ["Treni", "Meteo"])
    }

    @Test func savingTheSameQuestionAgainReplacesIt() {
        let archive = QuestionArchive(file: file())
        var question = ArchivedQuestion(id: UUID(), title: "Meteo", date: .now,
                                        turns: [QuestionTurn(prompt: "Meteo", answer: "Sole")], sessionID: nil)
        archive.save(question)
        question.turns.append(QuestionTurn(prompt: "E domani?", answer: "Pioggia"))
        archive.save(question)
        #expect(archive.questions.count == 1)
        #expect(archive.questions.first?.turns.count == 2)
    }

    @Test func aSessionBornFromAQuestionIsLinked() {
        let archive = QuestionArchive(file: file())
        let id = UUID()
        archive.save(ArchivedQuestion(id: id, title: "Login", date: .now, turns: [], sessionID: nil))
        let session = UUID()
        archive.linkSession(session, toQuestion: id)
        #expect(archive.questions.first?.sessionID == session)
    }

    @Test func aMissingOrBrokenFileIsAnEmptyArchive() throws {
        let file = file()
        #expect(QuestionArchive(file: file).questions.isEmpty)
        try Data("nope".utf8).write(to: file)
        #expect(QuestionArchive(file: file).questions.isEmpty)
    }
}
```

- [ ] **Step 2: Eseguire** — `-only-testing:BuboTests/QuestionArchiveTests`; atteso: «cannot find 'QuestionArchive' in scope».

- [ ] **Step 3: Implementazione**

`QuestionTurn`: `nonisolated struct QuestionTurn: Codable, Equatable, Sendable`.

```swift
import Foundation
import Observation
import os

/// A Domanda that ended, kept so it shows among the Conversazioni and can be continued.
nonisolated struct ArchivedQuestion: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    /// The first prompt, shortened.
    var title: String
    /// When the last turn ended.
    var date: Date
    var turns: [QuestionTurn]
    /// The Sessione this Domanda became, if it did.
    var sessionID: UUID?
}

/// The Domande that ended, in a JSON file in Bubo's Application Support folder (ADR 0006: Bubo keeps the
/// conversations).
@Observable
final class QuestionArchive {
    /// The Domande, newest first.
    private(set) var questions: [ArchivedQuestion]
    @ObservationIgnored private let file: URL

    /// Reads the archive at `file`; a missing or unreadable file is an empty archive.
    init(file: URL) {
        self.file = file
        let saved = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([ArchivedQuestion].self, from: $0) }
        questions = (saved ?? []).sorted { $0.date > $1.date }
    }

    /// The archive in Bubo's Application Support folder.
    static func live() throws -> QuestionArchive {
        let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true)
            .appending(path: "Bubo", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return QuestionArchive(file: folder.appending(path: "Domande.json"))
    }

    /// Keeps `question`, replacing the one with its id.
    func save(_ question: ArchivedQuestion) {
        questions.removeAll { $0.id == question.id }
        questions.append(question)
        questions.sort { $0.date > $1.date }
        write()
    }

    /// Records that the Domanda `question` became the Sessione `session`.
    func linkSession(_ session: UUID, toQuestion question: UUID) {
        guard let index = questions.firstIndex(where: { $0.id == question }) else { return }
        questions[index].sessionID = session
        write()
    }

    private func write() {
        do {
            try JSONEncoder().encode(questions).write(to: file, options: .atomic)
        } catch {
            Logger(subsystem: "com.mgiuditta.bubo", category: "questions").error("Domande not saved: \(error)")
        }
    }
}
```

In `QuestionModel`: proprietà `var archive: QuestionArchive?` (impostata all'avvio in `AppDelegate` con `try? QuestionArchive.live()`); in `startNewQuestion()`, prima di `turns = []`:

```swift
        archiveCurrentQuestion()
```

```swift
    /// Keeps the Domanda that is ending among the Conversazioni, with its last turn; nothing for an empty one.
    private func archiveCurrentQuestion() {
        var all = turns
        if !lastPrompt.isEmpty, !answer.isEmpty {
            all.append(QuestionTurn(prompt: lastPrompt, answer: answer, isOnMac: routedAnswer?.isOnMac ?? true))
        }
        guard let first = all.first, let question else { return }
        archive?.save(ArchivedQuestion(id: question, title: String(first.prompt.prefix(80)), date: now(),
                                       turns: all, sessionID: nil))
    }
```

(`question` è l'UUID della Domanda in corso, già esistente in `QuestionModel`.)

- [ ] **Step 4: Eseguire** — PASS (4 test).
- [ ] **Step 5: Commit** — `Finestra: le Domande finite si salvano tra le Conversazioni (#690)`.

### Task 2: Una Sessione aperta accetta un nuovo turno

**Files:**
- Modify: `Bubo/Sessions/SessionStore.swift:453` (`restart(_:prompt:)` diventa la base di `send`)
- Test: `BuboTests/SessionStoreSendTests.swift`

**Interfaces:**
- Produces: `SessionStore.send(_ prompt: String, to id: UUID) -> Bool` (`false` se la Sessione non è viva o è in un turno), `SessionStore.canSend(to id: UUID) -> Bool`.

- [ ] **Step 1: Test che fallisce** — con lo `SessionStore` dei test esistenti (vedi `BuboTests/SessionStoreTests.swift` per il costruttore con bridge finto):

```swift
@Test func aLiveSessionAtRestTakesANewTurn() async throws {
    let (store, bridge) = try SessionStoreFixture.make()
    let id = try await store.startAndWait("Correggi il login", in: SessionStoreFixture.project)
    #expect(store.canSend(to: id))
    #expect(store.send("Aggiungi un test", to: id))
    try await bridge.waitForPrompt(containing: "Aggiungi un test")
}

@Test func aSessionInATurnDoesNotTakeAnother() async throws {
    let (store, _) = try SessionStoreFixture.make(answering: .never)
    let id = try await store.start("Correggi il login", in: SessionStoreFixture.project)
    #expect(!store.canSend(to: id))
    #expect(!store.send("Altro", to: id))
}
```

Se `SessionStoreFixture` non esiste con questi nomi, il primo passo è estrarlo dal setup già ripetuto in `SessionStoreTests` (stesso bridge finto), senza cambiarne il comportamento.

- [ ] **Step 2: Eseguire** — fallisce: «no member 'send'».
- [ ] **Step 3: Implementazione**

```swift
    /// Whether the Sessione `id` can take a new turn now: open, live and not in a turn.
    func canSend(to id: UUID) -> Bool {
        guard let session = sessions.first(where: { $0.id == id }) else { return false }
        return session.isLive && turnTasks[id] == nil
    }

    /// Asks `prompt` as the next turn of the open Sessione `id`, in its copy and its conversation; `false`, and
    /// nothing asked, when ``canSend(to:)`` is false.
    @discardableResult
    func send(_ prompt: String, to id: UUID) -> Bool {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, canSend(to: id) else { return false }
        restart(id, prompt: trimmed)
        return true
    }
```

Verificare che `turnTasks[id]` torni `nil` a fine turno (altrimenti usare `session.activity != .lavora`).

- [ ] **Step 4: Eseguire** — PASS.
- [ ] **Step 5: Commit** — `Finestra: una Sessione aperta accetta un nuovo turno (#690)`.

### Task 3: Elenco unico delle Conversazioni, per giorno

**Files:**
- Create: `Bubo/Window/ConversationList.swift`
- Test: `BuboTests/ConversationListTests.swift`

**Interfaces:**
- Consumes: `ArchivedQuestion` (Task 1), `Session`, `CLIConversation`.
- Produces: `enum ConversationItem: Identifiable, Equatable { case question(ArchivedQuestion), session(id: UUID, title: String, project: URL, date: Date, activity: Session.Activity?), cli(id: String, title: String, project: URL?, date: Date) }` con `date`, `title`; `enum DayGroup: Comparable { case today, yesterday, thisWeek, earlier }` con `title: LocalizedStringResource`; `ConversationList.groups(of: [ConversationItem], now: Date, calendar: Calendar) -> [(DayGroup, [ConversationItem])]`; `ConversationList.items(questions:sessions:cli:includingCLI:) -> [ConversationItem]`.

- [ ] **Step 1: Test che fallisce**

```swift
import Foundation
import Testing
@testable import Bubo

struct ConversationListTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()
    private let now = Date(timeIntervalSince1970: 1_791_100_800) // sabato 4 ottobre 2026, 08:00 GMT

    private func question(_ title: String, hoursAgo: Double) -> ConversationItem {
        .question(ArchivedQuestion(id: UUID(), title: title, date: now.addingTimeInterval(-hoursAgo * 3600),
                                   turns: [], sessionID: nil))
    }

    @Test func itemsGoInDayGroupsNewestFirst() {
        let items = [question("Vecchia", hoursAgo: 24 * 30), question("Ieri", hoursAgo: 20),
                     question("Oggi", hoursAgo: 1), question("Martedì", hoursAgo: 24 * 4)]
        let groups = ConversationList.groups(of: items, now: now, calendar: calendar)
        #expect(groups.map(\.0) == [.today, .yesterday, .thisWeek, .earlier])
        #expect(groups.map { $0.1.map(\.title) } == [["Oggi"], ["Ieri"], ["Martedì"], ["Vecchia"]])
    }

    @Test func emptyGroupsAreLeftOut() {
        let groups = ConversationList.groups(of: [question("Oggi", hoursAgo: 1)], now: now, calendar: calendar)
        #expect(groups.map(\.0) == [.today])
    }

    @Test func theCommandLineShowsOnlyWhenAsked() {
        let cli = CLIConversation.fixture(title: "Da terminale", date: now)
        #expect(ConversationList.items(questions: [], sessions: [], cli: [cli], includingCLI: false).isEmpty)
        #expect(ConversationList.items(questions: [], sessions: [], cli: [cli], includingCLI: true).count == 1)
    }

    @Test func aQuestionThatBecameASessionStaysListed() {
        var archived = ArchivedQuestion(id: UUID(), title: "Login", date: now, turns: [], sessionID: UUID())
        archived.sessionID = UUID()
        let items = ConversationList.items(questions: [archived], sessions: [], cli: [], includingCLI: false)
        #expect(items.map(\.title) == ["Login"])
    }
}
```

`CLIConversation.fixture(title:date:)`: helper di test in `BuboTests/Fixtures/CLIConversation+Fixture.swift`, costruito con l'init memberwise di `CLIConversation`.

- [ ] **Step 2: Eseguire** — fallisce: «cannot find 'ConversationList'».
- [ ] **Step 3: Implementazione**

```swift
import Foundation

/// One entry of the Conversazioni in the sidebar: a Domanda, a Sessione or a conversation of the command line.
enum ConversationItem: Identifiable, Equatable {
    case question(ArchivedQuestion)
    case session(id: UUID, title: String, project: URL, date: Date, activity: Session.Activity?)
    case cli(id: String, title: String, project: URL?, date: Date)

    var id: String {
        switch self {
        case .question(let question): "q-\(question.id)"
        case .session(let id, _, _, _, _): "s-\(id)"
        case .cli(let id, _, _, _): "c-\(id)"
        }
    }

    var title: String {
        switch self {
        case .question(let question): question.title
        case .session(_, let title, _, _, _), .cli(_, let title, _, _): title
        }
    }

    var date: Date {
        switch self {
        case .question(let question): question.date
        case .session(_, _, _, let date, _), .cli(_, _, _, let date): date
        }
    }
}

/// The day groups of the Conversazioni, in the order they show.
enum DayGroup: Int, Comparable {
    case today, yesterday, thisWeek, earlier

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .today: "Oggi"
        case .yesterday: "Ieri"
        case .thisWeek: "Questa settimana"
        case .earlier: "Prima"
        }
    }
}

/// The Domande and the Sessioni in one list, by day (ADR 0013).
enum ConversationList {
    /// The items of the sidebar, newest first; the command line's conversations only when `includingCLI`.
    static func items(questions: [ArchivedQuestion], sessions: [Session], cli: [CLIConversation],
                      includingCLI: Bool) -> [ConversationItem] {
        var items = questions.map(ConversationItem.question)
        items += sessions.map { session in
            .session(id: session.id, title: session.title, project: session.project, date: session.lastActivity,
                     activity: session.isLive ? session.activity : nil)
        }
        if includingCLI {
            items += cli.map { .cli(id: $0.id, title: $0.title, project: $0.project, date: $0.date) }
        }
        return items.sorted { $0.date > $1.date }
    }

    /// `items` in day groups as seen at `now`, newest first in each; empty groups are left out.
    static func groups(of items: [ConversationItem], now: Date, calendar: Calendar) -> [(DayGroup, [ConversationItem])] {
        let grouped = Dictionary(grouping: items) { group(of: $0.date, now: now, calendar: calendar) }
        return grouped.keys.sorted().map { ($0, grouped[$0]!.sorted { $0.date > $1.date }) }
    }

    private static func group(of date: Date, now: Date, calendar: Calendar) -> DayGroup {
        if calendar.isDate(date, inSameDayAs: now) { return .today }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return .yesterday
        }
        if let week = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: now)), date >= week {
            return .thisWeek
        }
        return .earlier
    }
}
```

I nomi `session.lastActivity`, `CLIConversation.id/title/project/date` vanno allineati alle proprietà reali (leggere `Session.swift` e `CLIConversation.swift` prima di scrivere).

- [ ] **Step 4: Eseguire** — PASS.
- [ ] **Step 5: Commit** — `Finestra: elenco unico di Domande e Sessioni, per giorno (#690)`.

### Task 4: Destinatario

**Files:**
- Create: `Bubo/Window/Recipient.swift`
- Test: `BuboTests/RecipientTests.swift`

**Interfaces:**
- Produces: `enum Recipient: Hashable { case brain, project(URL) }`, `var name: String` (`"Cervello"` o il nome della cartella), `var accessibilityLabel: String` («Destinatario: …»).

- [ ] **Step 1: Test che fallisce**

```swift
import Foundation
import Testing
@testable import Bubo

struct RecipientTests {
    @Test func theBrainIsCalledCervello() {
        #expect(Recipient.brain.name == "Cervello")
        #expect(Recipient.brain.accessibilityLabel == "Destinatario: Cervello")
    }

    @Test func aProjectIsCalledAsItsFolder() {
        let project = Recipient.project(URL(filePath: "/Users/matteo/dev/bubo", directoryHint: .isDirectory))
        #expect(project.name == "bubo")
        #expect(project.accessibilityLabel == "Destinatario: bubo")
    }
}
```

- [ ] **Step 2: Eseguire** — fallisce.
- [ ] **Step 3: Implementazione**

```swift
import Foundation

/// Who the composer writes to: the Cervello (a Domanda) or a Progetto (a Sessione).
enum Recipient: Hashable {
    case brain
    case project(URL)

    /// The name on the chip.
    var name: String {
        switch self {
        case .brain: String(localized: "Cervello")
        case .project(let folder): folder.lastPathComponent
        }
    }

    /// What VoiceOver reads for the chip.
    var accessibilityLabel: String {
        String(localized: "Destinatario: \(name)")
    }
}
```

- [ ] **Step 4: Eseguire** — PASS.
- [ ] **Step 5: Commit** — `Finestra: Destinatario Cervello o Progetto (#690)`.

### Task 5: Proposta di Sessione dal nome di un Progetto

**Files:**
- Modify: `Bubo/Intake/SessionProposal.swift`, `Bubo/Question/QuestionModel.swift` (dove si calcola la proposta), `Bubo/Sessions/Session.swift` (`originQuestion`), `Bubo/Question/QuestionModel.swift:707` (`turnIntoSession`)
- Test: `BuboTests/SessionProposalTests.swift` (esistente: aggiungere)

**Interfaces:**
- Produces: `SessionProposal.forText(_ text: String, among projects: [URL]) -> SessionProposal?`; `Session.originQuestion: UUID?`; `SessionDraft.originQuestion: UUID?` passato a `SessionStore.start`.

- [ ] **Step 1: Test che fallisce**

```swift
    @Test(arguments: ["entra in bubo e sistema il login", "Bubo: aggiungi un test", "nel progetto BUBO fai il build"])
    func aKnownProjectNamedInTheTextIsProposed(text: String) {
        let bubo = URL(filePath: "/Users/matteo/dev/bubo", directoryHint: .isDirectory)
        #expect(SessionProposal.forText(text, among: [bubo]) == .session(bubo))
    }

    @Test(arguments: ["che tempo fa a Torino", "bubolo è una parola", "dimmi del gufo bubo bubo"])
    func noProjectNoProposal(text: String) {
        let bubo = URL(filePath: "/Users/matteo/dev/bubo", directoryHint: .isDirectory)
        let other = URL(filePath: "/Users/matteo/dev/ssg", directoryHint: .isDirectory)
        #expect(SessionProposal.forText(text, among: [other]) == nil)
        if text.hasPrefix("bubolo") { #expect(SessionProposal.forText(text, among: [bubo]) == nil) }
    }
```

- [ ] **Step 2: Eseguire** — fallisce.
- [ ] **Step 3: Implementazione** — parola intera, senza maiuscole, solo se esattamente un Progetto è nominato:

```swift
    /// The Sessione proposed when `text` names exactly one of `projects` as a whole word, ignoring case.
    static func forText(_ text: String, among projects: [URL]) -> SessionProposal? {
        let words = Set(text.lowercased().split { !$0.isLetter && !$0.isNumber && $0 != "-" && $0 != "_" }.map(String.init))
        let named = projects.filter { words.contains($0.lastPathComponent.lowercased()) }
        guard named.count == 1, let project = named.first else { return nil }
        return .session(project)
    }
```

Nel punto in cui `QuestionModel` calcola la proposta dagli Allegati, se quella è `nil` usa `forText(lastPrompt, among: projects)`. `turnIntoSession(accepting:)` mette `draft.originQuestion = question`; `SessionStore.start` lo copia in `Session.originQuestion`; chi conferma chiama `archive.linkSession(newID, toQuestion: origin)`.

- [ ] **Step 4: Eseguire** — PASS, più `SessionProposalTests` esistenti verdi.
- [ ] **Step 5: Commit** — `Finestra: la proposta di Sessione nasce anche dal nome del Progetto (#690)`.

### Task 6: Il guscio a due colonne

**Files:**
- Create: `Bubo/Window/SidebarSelection.swift`, `Bubo/Window/MainSidebar.swift`, `Bubo/Window/ConversationRow.swift`
- Modify: `Bubo/HUD/HUDView.swift` (corpo), il file di `HUDPresenter` (`selection`)
- Test: `BuboTests/SidebarSelectionTests.swift`

**Interfaces:**
- Produces: `enum SidebarSelection: Hashable { case brain, neurons, meetings, conversation(String), project(URL), work }`; `HUDPresenter.selection: SidebarSelection`; `HUDPresenter.show(session:)` imposta `.conversation("s-\(id)")`; `HUDPresenter.show(question:)` imposta `.conversation("q-\(id)")`.

- [ ] **Step 1: Test che fallisce**

```swift
@MainActor
struct SidebarSelectionTests {
    @Test func showingASessionSelectsItsConversation() {
        let hud = HUDPresenter()
        let id = UUID()
        hud.show(session: id)
        #expect(hud.selection == .conversation("s-\(id)"))
    }

    @Test func theWindowOpensOnTheBrain() {
        #expect(HUDPresenter().selection == .brain)
    }
}
```

- [ ] **Step 2: Eseguire** — fallisce.
- [ ] **Step 3: Implementazione** — `HUDView.body`:

```swift
    var body: some View {
        @Bindable var hud = hud
        NavigationSplitView {
            MainSidebar(selection: $hud.selection, questions: questions, sessions: sessions)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            detail(for: hud.selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 900, minHeight: 560)
        // … gli stessi modificatori di oggi: background con i fogli di Consegna, dropDestination, sheet,
        // onAppear, task di avvio e onboarding, tint, preferredColorScheme (spostati invariati).
    }

    @ViewBuilder
    private func detail(for selection: SidebarSelection) -> some View {
        switch selection {
        case .brain: HomeView(questions: questions, onboarding: onboarding)
        case .neurons: NeuronsView()          // la vista che esiste già
        case .meetings: MeetingView(recorder: meetings) // idem
        case .work: if let sessions { SessionBoard(store: sessions) }
        case .project(let folder): if let sessions { ProjectSessionsList(project: folder, store: sessions) }
        case .conversation(let id): ConversationDetail(id: id, questions: questions, sessions: sessions)
        }
    }
```

Nel Task 6 `HomeView` è il blocco `main` di oggi senza Viste (Orb + `QuestionView`); `ConversationDetail` mostra per ora `ConversationReaderView` in sola lettura. `MainSidebar`:

```swift
struct MainSidebar: View {
    @Binding var selection: SidebarSelection
    let questions: QuestionModel
    let sessions: SessionStore?
    @AppStorage("mostraRigaDiComando") private var includesCLI = false
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        List(selection: $selection) {
            Label("Cervello", systemImage: "brain").tag(SidebarSelection.brain)
            Label("Neuroni", systemImage: "point.3.connected.trianglepath.dotted").tag(SidebarSelection.neurons)
            Label("Riunioni", systemImage: "waveform").tag(SidebarSelection.meetings)
            ForEach(groups, id: \.0) { group, items in
                Section(String(localized: group.title)) {
                    ForEach(items) { ConversationRow(item: $0).tag(SidebarSelection.conversation($0.id)) }
                }
            }
            if let sessions, !sessions.projects.isEmpty {
                Section("Progetti") {
                    ForEach(sessions.projects, id: \.self) { project in
                        Label(project.lastPathComponent, systemImage: "folder").tag(SidebarSelection.project(project))
                    }
                    Label("Lavoro", systemImage: "rectangle.split.3x1").tag(SidebarSelection.work)
                }
            }
        }
        .environment(\.defaultMinListRowHeight, Spacing.sidebarRowMinHeight)
        .safeAreaInset(edge: .bottom, alignment: .leading) {
            GlassCapsuleButton("Impostazioni", systemImage: "gearshape") { openSettings() }
                .padding(Spacing.m)
        }
        .toolbar { Toggle("Mostra anche la riga di comando", isOn: $includesCLI) }
    }

    private var groups: [(DayGroup, [ConversationItem])] {
        let items = ConversationList.items(questions: questions.archive?.questions ?? [],
                                           sessions: sessions?.sessions ?? [],
                                           cli: sessions?.cliHistory ?? [], includingCLI: includesCLI)
        return ConversationList.groups(of: items, now: .now, calendar: .current)
    }
}
```

`ConversationRow`: titolo in `.buboInterface`; per una Sessione il chip del Progetto (capsula con filo `Palette.line`) e, se `activity == .attende`, il pallino `Palette.attention` con etichetta VoiceOver «Attende te»; ora in `.buboData` e `Palette.textSecondary`.

- [ ] **Step 4: Eseguire** — `SidebarSelectionTests` PASS, build Debug verde, `BuboTests` completo verde.
- [ ] **Step 5: Commit** — `Finestra: due colonne, Cervello, Conversazioni e Progetti (#690)`.

### Task 7: Conversazione aperta con il composer

**Files:**
- Create: `Bubo/Window/QuestionDetail.swift`, `Bubo/Window/SessionDetail.swift`, `Bubo/Window/ConversationDetail.swift`
- Modify: `Bubo/Question/QuestionModel.swift` (`continueQuestion(_ archived: ArchivedQuestion)`)
- Test: `BuboTests/QuestionModelContinueTests.swift`

**Interfaces:**
- Consumes: `QuestionArchive`, `SessionStore.send`, `Recipient`.
- Produces: `QuestionModel.continueQuestion(_:)`: avvia una nuova Domanda con `turns = archived.turns` e `question = archived.id`, così il prossimo prompt la continua e il salvataggio la sostituisce.

- [ ] **Step 1: Test che fallisce**

```swift
@MainActor
struct QuestionModelContinueTests {
    @Test func aPastQuestionContinuesWithItsTurns() {
        let model = QuestionModel()
        let archived = ArchivedQuestion(id: UUID(), title: "Meteo", date: .now,
                                        turns: [QuestionTurn(prompt: "Meteo", answer: "Sole")], sessionID: nil)
        model.continueQuestion(archived)
        #expect(model.turns == archived.turns)
        #expect(model.question == archived.id)
    }
}
```

- [ ] **Step 2: Eseguire** — fallisce.
- [ ] **Step 3: Implementazione** — `continueQuestion`: `startNewQuestion(); turns = archived.turns; question = archived.id`. `QuestionDetail`: le domande e risposte (`AnswerProse` per le risposte) in una `ScrollView` larga al massimo `Spacing.readingWidth`, poi il composer di `QuestionView` con `RecipientChip(.brain)`; all'apparire chiama `continueQuestion` se la Domanda corrente è un'altra. `SessionDetail`: `ConversationReaderView` della Sessione sopra, sotto un campo con `RecipientChip(.project(session.project))` che chiama `store.send(text, to: id)`, disabilitato con «Sta lavorando…» quando `!store.canSend(to: id)`; le Richieste di permesso e `AgentQuestionView` della Sessione restano visibili sopra il campo come oggi in `SessionColumn`.
- [ ] **Step 4: Eseguire** — PASS; prova a mano: clic su una Domanda di ieri, nuova domanda, la risposta tiene conto dei turni.
- [ ] **Step 5: Commit** — `Finestra: la conversazione si apre e si continua (#690)`.

### Task 8: Casa vuota e chip del Destinatario

**Files:**
- Create: `Bubo/Window/HomeView.swift`, `Bubo/Window/RecipientChip.swift`
- Test: `BuboTests/HomeSuggestionsTests.swift`

**Interfaces:**
- Produces: `HomeSuggestions.make(profile: String, recentNotes: [String]) -> [String]` (al più 3).

- [ ] **Step 1: Test che fallisce**

```swift
struct HomeSuggestionsTests {
    @Test func atMostThreeSuggestionsFromTheNotes() {
        let suggestions = HomeSuggestions.make(profile: "", recentNotes: ["Lancio", "Riunione 3 ottobre", "Idee", "Budget"])
        #expect(suggestions.count == 3)
        #expect(suggestions.first == "Cosa c'è di nuovo in Lancio?")
    }

    @Test func withoutNotesThereAreGeneralOnes() {
        #expect(HomeSuggestions.make(profile: "", recentNotes: []).count == 3)
    }
}
```

- [ ] **Step 2: Eseguire** — fallisce.
- [ ] **Step 3: Implementazione** — `HomeSuggestions.make`: per le prime 3 note recenti «Cosa c'è di nuovo in \(nota)?»; senza note «Cosa ho deciso questa settimana?», «Riassumi l'ultima Riunione», «Cosa ricordi di me?». `HomeView`: `HUDOrb` 320 pt, `Text("Chiedi al tuo cervello").font(.buboDisplay)`, tre `Button` capsula con il suggerimento (riempiono il prompt), il composer di `QuestionView` con `RecipientChip`. `RecipientChip`: `Menu` con `Recipient.brain` e i Progetti, etichetta `name` + `chevron.down`, `.accessibilityLabel(recipient.accessibilityLabel)`; scegliere un Progetto apre `NewSessionSheet` con quel Progetto e il testo del campo.
- [ ] **Step 4: Eseguire** — PASS.
- [ ] **Step 5: Commit** — `Finestra: casa vuota con suggerimenti e chip del Destinatario (#690)`.

### Task 9: «Apri la chat completa» apre quella conversazione

**Files:**
- Modify: dove la Bolla chiama l'HUD (cercare `Apri la chat completa` in `Bubo/Panel/`), il file di `HUDPresenter`
- Test: `BuboTests/SidebarSelectionTests.swift`

- [ ] **Step 1: Test che fallisce**

```swift
    @Test func openingTheFullChatSelectsTheQuestion() {
        let hud = HUDPresenter()
        let id = UUID()
        hud.show(question: id)
        #expect(hud.selection == .conversation("q-\(id)"))
    }
```

- [ ] **Step 2–4:** `show(question:)` imposta la selezione e mostra la finestra; la Bolla, prima di aprire, salva la Domanda nell'archivio (`archive.save`) senza chiuderla, poi chiama `hud.show(question: questions.question)`. PASS.
- [ ] **Step 5: Commit** — `Finestra: la Bolla apre la chat completa sulla sua Domanda (#690)`.

### Task 10: Via Orbita, Striscia, anelli e scelta della Vista

**Files:**
- Delete: `Bubo/HUD/SessionOrbit.swift`, `Bubo/HUD/SessionStrip.swift`, `Bubo/HUD/HUDRings.swift`, `Bubo/HUD/VistaDelleSessioni.swift`, la scelta della Vista in `Bubo/Settings/AppearanceSettingsView.swift`, i comandi ⌘1–⌘4 delle Viste
- Modify: `HUDPresenter` (`vista`, `switchVista`, `endVistaSwitch` via), test che li usano

- [ ] **Step 1:** `grep -rn "VistaDelleSessioni\|SessionOrbit\|SessionStrip\|HUDRings\|switchVista" Bubo BuboTests` ed eliminare ogni uso; i test delle Viste si cancellano con il codice.
- [ ] **Step 2:** build Debug e `BuboTests` completo verdi; `scripts/polish-check.sh` verde (stringhe stale rimosse dal catalogo con `xcstringstool sync`).
- [ ] **Step 3: Commit** — `Finestra: via Orbita, Striscia, anelli e scelta della Vista (ADR 0013)`.

### Task 11: UI test, dominio e design system

**Files:**
- Create: `BuboUITests/MainWindowUITests.swift`
- Modify: `CONTEXT.md` (HUD, Vista delle Sessioni, nuovo Destinatario), `docs/design-system.md` (Finestra), chiudere #690 con un commento che rimanda all'ADR 0013

- [ ] **Step 1: UI test**

```swift
import XCTest

final class MainWindowUITests: XCTestCase {
    @MainActor
    func testClickingASessionOpensItWithItsProject() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestingSessions", "fixture"]
        app.launch()
        let row = app.outlines.staticTexts["Login che scade"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()
        XCTAssertTrue(app.buttons["Destinatario: bubo"].waitForExistence(timeout: 2))
    }
}
```

`-uiTestingSessions fixture` carica uno `SessionStore` con una Sessione «Login che scade» sul Progetto `bubo` (stesso schema degli argomenti di avvio già usati da `QuestionLiveTests`).

- [ ] **Step 2:** `CONTEXT.md`: **HUD** «La finestra di lavoro: barra laterale con Cervello, Conversazioni e Progetti; a destra la conversazione aperta.» **Vista delle Sessioni** ridotta a Elenco (barra laterale) e Board (Lavoro). **Destinatario** nuovo termine.
- [ ] **Step 3:** test completi, polish-check, commit `Finestra: UI test, CONTEXT e design system (#690)`, push `feat/finestra-casa`, PR verso `main`. Nessun merge.

## Self-review

- Spec §1 Struttura → Task 6 (barra laterale, Impostazioni di vetro), 8 (casa vuota). Composer e destinatario → Task 4, 5, 7, 8. Comportamento: clic apre → 6–7; Domanda trasformata resta → 1, 3, 5; Bolla → 9; Orb grande solo nella casa → 8, 10. Eliminazioni → 10. Dominio → 11. Test → ogni task, UI test → 11.
- Lacune trovate nel codice e coperte: Domande non salvate (Task 1), nessun nuovo turno per una Sessione aperta (Task 2), proposta solo dagli Allegati (Task 5).
- Nomi coerenti: `ArchivedQuestion`, `QuestionArchive`, `ConversationItem.id` con prefissi `q-`/`s-`/`c-` usati da `SidebarSelection.conversation` nei Task 6 e 9.
