import SwiftUI

// MARK: - Checkbox

/// Hand-drawn box; completing it draws the stroke on rather than fading it in.
struct InkCheckbox: View {
    var isDone: Bool
    var seed: UInt64
    var size: CGFloat = 26

    var body: some View {
        ZStack {
            // Fewer samples and a tighter wobble keep the corners legible — at
            // 26pt a looser line smooths into a blob rather than a square.
            RoughRect(seed: seed, wobble: 0.9, corner: 1.5, samplesPerEdge: 3)
                .stroke(Ink.ink.opacity(isDone ? 1 : 0.75), style: StrokeStyle(lineWidth: 2, lineCap: .round))

            RoughRect(seed: seed &+ 1, wobble: 0.7, corner: 1.5, samplesPerEdge: 3)
                .fill(Ink.ink)
                .scaleEffect(isDone ? 1 : 0.2)
                .opacity(isDone ? 1 : 0)

            BrushCheck()
                .trim(from: 0, to: isDone ? 1 : 0)
                .stroke(Ink.paper, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .padding(size * 0.2)
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.34, dampingFraction: 0.62), value: isDone)
    }
}

// MARK: - Stamps

/// Rubber-stamp meta label. `filled` inverts it for the one thing on screen
/// that actually needs to shout.
struct StampLabel: View {
    let text: String
    var filled: Bool = false
    var tint: Color = Ink.ink
    var seed: UInt64 = 5

    var body: some View {
        Text(text)
            .inkStamp(10)
            .stampCase()
            .foregroundStyle(filled ? Ink.paper : tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background {
                if filled {
                    RoughRect(seed: seed, wobble: 1.3, corner: 2).fill(tint)
                } else {
                    RoughRect(seed: seed, wobble: 1.3, corner: 2)
                        .stroke(tint.opacity(0.5), lineWidth: 1.2)
                }
            }
    }
}

// MARK: - Buttons

/// Solid ink block. Pressing collapses it into its own drop shadow.
struct InkBlockButtonStyle: ButtonStyle {
    var seed: UInt64 = 21
    var tint: Color = Ink.ink

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .inkHeading(17)
            .posterCase(tracking: 0.4)
            .foregroundStyle(Ink.paper)
            .padding(.horizontal, 22)
            .padding(.vertical, 15)
            .background {
                ZStack {
                    RoughRect(seed: seed &+ 9, wobble: 1.4, corner: 5)
                        .fill(Ink.ink.opacity(0.28))
                        .offset(x: pressed ? 0 : 4, y: pressed ? 0 : 4)
                    RoughRect(seed: seed, wobble: 1.8, corner: 5).fill(tint)
                }
            }
            .offset(x: pressed ? 3 : 0, y: pressed ? 3 : 0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: pressed)
    }
}

/// Outlined counterpart for secondary actions.
struct InkOutlineButtonStyle: ButtonStyle {
    var seed: UInt64 = 33

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .inkHeading(16)
            .posterCase(tracking: 0.4)
            .foregroundStyle(Ink.ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background {
                RoughRect(seed: seed, wobble: 1.6, corner: 4)
                    .stroke(Ink.ink.opacity(pressed ? 1 : 0.7), lineWidth: 2)
                    .background(RoughRect(seed: seed, wobble: 1.6, corner: 4).fill(pressed ? Ink.inkGhost : .clear))
            }
            .animation(.easeOut(duration: 0.12), value: pressed)
    }
}

/// Small square icon button — used for the back chevron, close, and overflow.
///
/// `accessibilityLabel` is required rather than defaulted: the button is a
/// bare SF Symbol with no text, so without an explicit label VoiceOver has
/// nothing reliable to read — the symbol name itself, if anything.
struct InkIconButton: View {
    let systemName: String
    var seed: UInt64 = 44
    let accessibilityLabel: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(Ink.ink)
                .frame(width: 38, height: 38)
                .background(RoughRect(seed: seed, wobble: 1.4, corner: 4).stroke(Ink.ink.opacity(0.45), lineWidth: 1.6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - Containers

/// Card with a hand-inked border and a hard offset shadow.
struct InkCard<Content: View>: View {
    var seed: UInt64
    var emphasised: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .background {
                ZStack {
                    RoughRect(seed: seed &+ 5, wobble: 1.4, corner: 6)
                        .fill(Ink.ink.opacity(emphasised ? 0.22 : 0.10))
                        .offset(x: 3.5, y: 3.5)
                    RoughRect(seed: seed, wobble: 1.9, corner: 6).fill(Ink.paper)
                    RoughRect(seed: seed, wobble: 1.9, corner: 6)
                        .stroke(Ink.ink.opacity(emphasised ? 1 : 0.65), lineWidth: emphasised ? 2.2 : 1.5)
                }
            }
    }
}

/// Section header: heavy compressed caps with a rule that runs to the edge.
struct SectionRule: View {
    let title: String
    var trailing: String?
    var seed: UInt64 = 8

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .inkStamp(11)
                .stampCase()
                .foregroundStyle(Ink.ink)

            RoughDivider(seed: seed, opacity: 0.28)

            if let trailing {
                Text(trailing)
                    .inkStamp(11)
                    .stampCase()
                    .foregroundStyle(Ink.inkSoft)
            }
        }
        // The divider has nothing to say, and title+trailing read better as
        // one phrase ("Late, 3") than two separate stops. The header trait
        // is what lets VoiceOver's rotor jump section to section instead of
        // swiping through every row to get there.
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel(trailing.map { "\(title), \($0)" } ?? title)
    }
}

// MARK: - Feedback

/// Haptics, wrapped so call sites read as intent rather than plumbing.
@MainActor
enum InkHaptics {
    static func tick() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.7)
    }

    static func thud() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    static func done() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func nope() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
