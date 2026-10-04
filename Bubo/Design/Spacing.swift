import CoreGraphics

/// The spacing scale of Bubo, in points (design system, Spaziatura).
///
/// New views use the steps from `xxs` to `xxl` and never hand-written numbers; panels have `m` or `l` margins.
enum Spacing {
    /// 4 pt.
    static let xxs: CGFloat = 4
    /// 8 pt.
    static let xs: CGFloat = 8
    /// 12 pt.
    static let s: CGFloat = 12
    /// 16 pt, the inner margin of panels.
    static let m: CGFloat = 16
    /// 24 pt, the outer margin of panels.
    static let l: CGFloat = 24
    /// 32 pt.
    static let xl: CGFloat = 32
    /// 48 pt.
    static let xxl: CGFloat = 48
    /// The minimum height of a row in the sidebar.
    static let sidebarRowMinHeight: CGFloat = 36
    /// The maximum width of a conversation's text, for comfortable reading.
    static let readingWidth: CGFloat = 720

    // The scale before the brand kit, still used by existing views.

    /// 4 pt.
    static let xxSmall: CGFloat = 4
    /// 8 pt.
    static let xSmall: CGFloat = 8
    /// 12 pt.
    static let small: CGFloat = 12
    /// 18 pt, the padding of glass panels.
    static let medium: CGFloat = 18
    /// 24 pt.
    static let large: CGFloat = 24
    /// 40 pt.
    static let xLarge: CGFloat = 40
}
