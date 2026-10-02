import Foundation

/// What the agent asks of a Sessione's Anteprima through the bridge's tools (spec 15).
///
/// Reading the page is Lettura; everything that changes it is Modifica reversibile.
nonisolated enum PreviewAction: Equatable, Sendable {
    /// A picture of the page, at most 1568 px on its long side.
    case screenshot
    /// The HTML of the page, or of the element `selector` matches.
    case dom(selector: String?)
    /// The last console lines, only those containing `filter` when given.
    case console(filter: String?)
    /// The last requests of the page, only those containing `filter` when given.
    case network(filter: String?)
    /// Opens `address`, absolute or relative to the page.
    case navigate(to: String)
    /// Clicks the element `selector` matches.
    case click(selector: String)
    /// Replaces the value of the field `selector` matches with `text`.
    case fill(selector: String, text: String)
    /// Scrolls to the element `selector` matches, else by `offset` points down.
    case scroll(selector: String?, offset: Double?)
    /// Runs `code`, the body of a function, in a world apart from the page's scripts.
    case runJavaScript(code: String)

    /// The action of the bridge's tool `tool`, with its arguments; `nil` for a tool Bubo does not know.
    init?(tool: String, selector: String?, text: String?, url: String?, filter: String?, code: String?, y: Double?) {
        switch tool {
        case "screenshot": self = .screenshot
        case "dom": self = .dom(selector: selector)
        case "console": self = .console(filter: filter)
        case "rete": self = .network(filter: filter)
        case "naviga":
            guard let url else { return nil }
            self = .navigate(to: url)
        case "clicca":
            guard let selector else { return nil }
            self = .click(selector: selector)
        case "compila":
            guard let selector, let text else { return nil }
            self = .fill(selector: selector, text: text)
        case "scorri": self = .scroll(selector: selector, offset: y)
        case "esegui_js":
            guard let code else { return nil }
            self = .runJavaScript(code: code)
        default: return nil
        }
    }
}

/// What a ``PreviewAction`` gives back to the agent.
nonisolated enum PreviewReply: Equatable, Sendable {
    case text(String)
    /// A JPEG picture of the page.
    case image(Data)
    /// Why the action failed, written for the agent.
    case failure(String)
}
