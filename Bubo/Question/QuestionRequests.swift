import SwiftUI

/// What the agent of a Domanda waits for before going on: its questions, then a Richiesta di permesso, such as a
/// Server MCP to call, a command to run or a file to write. The same in the chat and in the Panel's bubble.
struct QuestionRequests: View {
    let model: QuestionModel

    var body: some View {
        if let question = model.agentQuestions.first {
            AgentQuestionView(question: question, hasKeyboard: model.pendingPermission == nil) { replies in
                model.answerAgentQuestion(question.id, with: replies)
            }
            .id(question.id)
        }
        if let (pending, queued) = model.pendingPermission, let folder = model.requestsFolder {
            PermissionRequestView(pending: pending, project: folder, queued: queued, hasKeyboard: true) { answer in
                model.answerPermission(pending.id, with: answer)
            } allowInProject: {
                try model.allowInProject(pending.id)
            }
            .id(pending.id)
        }
    }
}
