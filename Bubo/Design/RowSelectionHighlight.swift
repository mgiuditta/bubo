import AppKit
import SwiftUI

/// The selection of a row in a list, drawn by Bubo with lightness and a border in place of the system blue
/// (design system: `tint` does not reach the selection of a List on macOS).
///
/// Used as the row's `listRowBackground`: it also turns off the table's own highlight, so the same row looks the same
/// whether the list has the keyboard focus or not.
struct RowSelectionHighlight: View {
    /// Whether the row is the selected one.
    let isSelected: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        RoundedRectangle(cornerRadius: CornerRadius.small)
            .fill(isSelected ? Palette.rowSelection : .clear)
            .strokeBorder(isSelected ? border : .clear)
            .padding(.horizontal, Spacing.xs)
            .background { SystemHighlightRemover() }
    }

    /// The border of the selected row: stronger with Aumenta contrasto.
    private var border: Color {
        contrast == .increased ? Palette.textPrimary : Palette.lineStrong
    }
}

extension View {
    /// Tags the row with `value` and draws its selection like the rest of Bubo when `value` is `selection`.
    func selectableRow<Value: Hashable>(_ value: Value, selection: Value?) -> some View {
        tag(value).listRowBackground(RowSelectionHighlight(isSelected: value == selection))
    }
}

/// Turns off the selection highlight of the table hosting the row; keyboard and selection keep working.
private struct SystemHighlightRemover: NSViewRepresentable {
    func makeNSView(context: Context) -> RemoverView { RemoverView() }

    func updateNSView(_ view: RemoverView, context: Context) { view.removeHighlight() }

    final class RemoverView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            removeHighlight()
        }

        func removeHighlight() {
            guard let table = enclosingScrollView?.documentView as? NSTableView,
                  table.selectionHighlightStyle != .none else { return }
            table.selectionHighlightStyle = .none
        }
    }
}
