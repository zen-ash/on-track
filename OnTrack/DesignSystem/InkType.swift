import SwiftUI

/// Type is doing the heavy lifting for the "edgy" read: SF's compressed width
/// gives us a condensed poster grotesque without shipping a font file, and the
/// monospace cuts are used like rubber stamps.
enum InkType {
    static func display(_ size: CGFloat = 42) -> Font {
        .system(size: size, weight: .black).width(.compressed)
    }

    static func title(_ size: CGFloat = 26) -> Font {
        .system(size: size, weight: .heavy).width(.compressed)
    }

    static func heading(_ size: CGFloat = 19) -> Font {
        .system(size: size, weight: .bold).width(.condensed)
    }

    static let body = Font.system(size: 17, weight: .medium)
    static let bodySmall = Font.system(size: 15, weight: .regular)

    /// Stamped meta labels — dates, tags, counts.
    static func stamp(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .bold, design: .monospaced)
    }
}

extension View {
    /// Poster type: uppercase, tight, unapologetic.
    func posterCase(tracking: CGFloat = -1.0) -> some View {
        self.textCase(.uppercase).tracking(tracking)
    }

    /// Stamp type: uppercase, airy tracking, small.
    func stampCase() -> some View {
        self.textCase(.uppercase).tracking(1.4)
    }
}
