import SwiftUI

/// The whole app is ink on paper. Two colours, everything else is opacity.
enum Ink {
    static let paper = Color(red: 0.988, green: 0.984, blue: 0.976)
    static let paperShade = Color(red: 0.945, green: 0.939, blue: 0.926)
    static let ink = Color(red: 0.043, green: 0.047, blue: 0.055)

    /// Ink that has soaked in a little — secondary text.
    static let inkSoft = Color(red: 0.043, green: 0.047, blue: 0.055).opacity(0.58)
    /// Barely there — hairlines, disabled states.
    static let inkFaint = Color(red: 0.043, green: 0.047, blue: 0.055).opacity(0.16)
    static let inkGhost = Color(red: 0.043, green: 0.047, blue: 0.055).opacity(0.07)

    /// The single accent. Used for one thing only: things that are late.
    static let alarm = Color(red: 0.86, green: 0.18, blue: 0.12)
}

/// Deterministic randomness. Rough edges must be *stable* — a shape that
/// re-wobbles on every redraw looks like a rendering bug, not a drawing.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64

    init(_ seed: UInt64) {
        // Avoid the zero state, and spread small seeds across the range.
        state = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        if state == 0 { state = 0x9E3779B97F4A7C15 }
    }

    mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 2_685_821_657_736_338_717
    }

    /// Signed jitter in ±`amount`.
    mutating func jitter(_ amount: CGFloat) -> CGFloat {
        CGFloat.random(in: -amount...amount, using: &self)
    }

    mutating func value(in range: ClosedRange<CGFloat>) -> CGFloat {
        CGFloat.random(in: range, using: &self)
    }
}

extension String {
    /// A stable seed derived from a string, so the same task always gets the
    /// same hand-drawn imperfections.
    var inkSeed: UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}
