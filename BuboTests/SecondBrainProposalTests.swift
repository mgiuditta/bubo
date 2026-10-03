import Foundation
import Testing
@testable import Bubo

/// The proposal the model writes at the end of the setup conversation of the Secondo cervello.
struct SecondBrainProposalTests {
    @Test func theLastBlockIsReadAndLeftOutOfTheProse() throws {
        let answer = """
        Questo vault è tuo, controlla:
        ```secondo-cervello
        {"azione": "crea", "cartella": "/vecchia"}
        ```
        Meglio così:
        ```secondo-cervello
        {"azione": "usa", "cartella": "~/Note", "escluse": ["Archivio"], "prioritarie": ["Lavoro"],
         "persone": ["Giulia"], "progetti": ["Bubo"]}
        ```
        """

        let proposal = try #require(SecondBrainProposal(in: answer))

        #expect(proposal == SecondBrainProposal(action: .use, path: "~/Note", excludedFolders: ["Archivio"],
                                                priorityFolders: ["Lavoro"], people: ["Giulia"], projects: ["Bubo"]))
        #expect(proposal.folder.path == FileManager.default.homeDirectoryForCurrentUser.appending(path: "Note").path)
        #expect(!SecondBrainProposal.prose(of: answer).contains("~/Note"))
        #expect(SecondBrainProposal.prose(of: answer).hasSuffix("Meglio così:"))
    }

    @Test func onlyActionAndFolderAreRequired() throws {
        let proposal = try #require(SecondBrainProposal(in: "```secondo-cervello\n{\"azione\":\"crea\",\"cartella\":\"/x\"}\n```"))

        #expect(proposal == SecondBrainProposal(action: .create, path: "/x"))
    }

    @Test(arguments: [
        "Nessuna proposta, solo una domanda?",
        "```secondo-cervello\n{\"azione\":\"sposta\",\"cartella\":\"/x\"}\n```",
        "```secondo-cervello\n{\"azione\":\"usa\",\"cartella\":\" \"}\n```",
        "```secondo-cervello\n{\"azione\":\"usa\"\n```",
    ])
    func anAnswerWithoutAValidBlockProposesNothing(answer: String) {
        #expect(SecondBrainProposal(in: answer) == nil)
    }
}
