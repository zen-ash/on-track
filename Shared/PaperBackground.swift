import SwiftUI

/// Off-white stock with visible tooth. The grain is deterministic, so it never
/// crawls or shimmers between redraws.
struct PaperBackground: View {
    var speckles: Int = 900

    var body: some View {
        Ink.paper
            .overlay {
                Canvas { context, size in
                    var rng = SeededRNG(0x9A17_3E5B)
                    for _ in 0..<speckles {
                        let x = rng.value(in: 0...size.width)
                        let y = rng.value(in: 0...size.height)
                        let s = rng.value(in: 0.7...1.9)
                        let a = rng.value(in: 0.02...0.09)
                        context.fill(
                            Path(ellipseIn: CGRect(x: x, y: y, width: s, height: s)),
                            with: .color(Ink.ink.opacity(a))
                        )
                    }
                }
                .allowsHitTesting(false)
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }
}

/// A hand-drawn divider. Pass a distinct seed per instance so no two rules on
/// screen share the same wobble.
struct RoughDivider: View {
    var seed: UInt64 = 3
    var opacity: CGFloat = 0.22

    var body: some View {
        RoughRule(seed: seed)
            .stroke(Ink.ink.opacity(opacity), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            .frame(height: 3)
    }
}

/// Ink splatter used sparingly behind empty states and celebration moments.
struct InkSplatter: View {
    var seed: UInt64
    var count: Int = 6

    var body: some View {
        Canvas { context, size in
            var rng = SeededRNG(seed)
            for _ in 0..<count {
                let r = rng.value(in: 2...9)
                let x = rng.value(in: 0...max(1, size.width - r))
                let y = rng.value(in: 0...max(1, size.height - r))
                let blob = RoughBlob(seed: UInt64(rng.value(in: 1...9999)), lumpiness: 0.3)
                context.fill(
                    blob.path(in: CGRect(x: x, y: y, width: r, height: r)),
                    with: .color(Ink.ink.opacity(rng.value(in: 0.25...0.8)))
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
