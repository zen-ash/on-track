import SwiftUI

/// Type is doing the heavy lifting for the "edgy" read: SF's compressed width
/// gives us a condensed poster grotesque without shipping a font file, and the
/// monospace cuts are used like rubber stamps.
///
/// Every size below is a *baseline*, not a fixed point size — each modifier
/// scales it with the system's Dynamic Type setting via `@ScaledMetric`,
/// capped at `.inkMaxDynamicTypeSize` (applied once, at the app's root) so a
/// layout this tightly hand-fitted — a 26pt checkbox, stamp badges sized to
/// their padding — doesn't have to survive the five accessibility sizes on
/// top of the standard range.
private struct InkFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    let weight: Font.Weight
    let width: Font.Width
    let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, width: Font.Width = .standard, design: Font.Design = .default, relativeTo textStyle: Font.TextStyle) {
        self._size = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
        self.weight = weight
        self.width = width
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design).width(width))
    }
}

/// The cap referenced above. `xxxLarge` is the top of the *standard* range —
/// everything from `.accessibility1` up is where this UI is most likely to
/// clip or overlap, so text stops growing there rather than at the system
/// maximum. Applied once, high up in the view tree; every `@ScaledMetric` in
/// this file inherits it automatically because it's reading the same
/// (now-clamped) environment value.
extension DynamicTypeSize {
    static let inkMaxDynamicTypeSize: DynamicTypeSize = .xxxLarge

    /// A widget's canvas is fixed with no scroll to fall back on, so it gets
    /// a tighter cap than the rest of the app — enough to still shrink for
    /// someone who prefers smaller text, not enough to overflow a 155pt tile.
    static let inkWidgetMaxDynamicTypeSize: DynamicTypeSize = .large
}

extension View {
    func inkDisplay(_ size: CGFloat = 42) -> some View {
        modifier(InkFont(size: size, weight: .black, width: .compressed, relativeTo: .largeTitle))
    }

    func inkTitle(_ size: CGFloat = 26) -> some View {
        modifier(InkFont(size: size, weight: .heavy, width: .compressed, relativeTo: .title))
    }

    func inkHeading(_ size: CGFloat = 19) -> some View {
        modifier(InkFont(size: size, weight: .bold, width: .condensed, relativeTo: .headline))
    }

    func inkBody() -> some View {
        modifier(InkFont(size: 17, weight: .medium, relativeTo: .body))
    }

    func inkBodySmall() -> some View {
        modifier(InkFont(size: 15, weight: .regular, relativeTo: .subheadline))
    }

    /// Stamped meta labels — dates, tags, counts.
    func inkStamp(_ size: CGFloat = 11) -> some View {
        modifier(InkFont(size: size, weight: .bold, design: .monospaced, relativeTo: .caption2))
    }

    /// Poster type: uppercase, tight, unapologetic.
    func posterCase(tracking: CGFloat = -1.0) -> some View {
        self.textCase(.uppercase).tracking(tracking)
    }

    /// Stamp type: uppercase, airy tracking, small.
    func stampCase() -> some View {
        self.textCase(.uppercase).tracking(1.4)
    }
}
