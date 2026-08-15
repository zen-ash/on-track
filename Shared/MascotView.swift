import SwiftUI

/// The creature, drawn rather than shipped. Everything is normalised to the
/// view's bounds so one implementation serves the 28pt header version and the
/// 160pt empty-state version.
struct MascotView: View {
    var mood: MascotMood
    /// Set false for the static header instance to avoid a permanent 30fps redraw.
    var animated: Bool = true

    var body: some View {
        Group {
            if animated {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    canvas(time: t)
                }
            } else {
                canvas(time: 0)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel(accessibilityDescription)
    }

    private func canvas(time: TimeInterval) -> some View {
        Canvas { context, size in
            draw(in: &context, size: size, time: time)
        }
    }

    // MARK: - Drawing

    private func draw(in context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let s = min(size.width, size.height)
        // Normalised → view coordinates. Everything below is authored in a 0…1 box.
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: (size.width - s) / 2 + x * s, y: (size.height - s) / 2 + y * s)
        }
        func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(origin: p(x, y), size: CGSize(width: w * s, height: h * s))
        }

        // Idle motion: a slow bob, faster and jitterier when agitated.
        let bobSpeed: Double = mood == .feral ? 5.2 : (mood == .listening ? 3.0 : 1.5)
        let bobAmount: CGFloat = mood == .feral ? 0.016 : 0.010
        let bob = CGFloat(sin(time * bobSpeed)) * bobAmount
        // Feral shivers side to side too.
        let shake: CGFloat = mood == .feral ? CGFloat(sin(time * 27)) * 0.005 : 0

        context.translateBy(x: shake * s, y: bob * s)

        // --- Horns ---
        for horn in horns {
            var path = Path()
            path.move(to: p(horn.baseX - horn.width, horn.baseY))
            path.addQuadCurve(
                to: p(horn.tipX, horn.tipY),
                control: p(horn.baseX - horn.width * 1.5, horn.baseY - (horn.baseY - horn.tipY) * 0.55)
            )
            path.addQuadCurve(
                to: p(horn.baseX + horn.width, horn.baseY),
                control: p(horn.baseX + horn.width * 0.3, horn.baseY - (horn.baseY - horn.tipY) * 0.35)
            )
            path.closeSubpath()
            context.fill(path, with: .color(Ink.ink))
        }

        // --- Head ---
        let headRect = r(0.13, 0.22, 0.74, 0.68)
        let head = RoughBlob(seed: 0x0FACE, lumpiness: 0.055).path(in: headRect)
        context.fill(head, with: .color(Ink.ink))

        // --- Eyes ---
        // Blink: a short, irregular closure so it doesn't read as a metronome.
        let blinkCycle = time.truncatingRemainder(dividingBy: 4.7)
        let isBlinking = animated && blinkCycle < 0.13 && mood != .listening
        let squint = eyeSquint
        let openness: CGFloat = isBlinking ? 0.08 : squint

        let leftEye = r(0.235, 0.40 + (1 - openness) * 0.055, 0.20, 0.175 * openness)
        let rightEye = r(0.545, 0.435 + (1 - openness) * 0.045, 0.145, 0.145 * openness)

        context.fill(Path(ellipseIn: leftEye), with: .color(Ink.paper))
        context.fill(Path(ellipseIn: rightEye), with: .color(Ink.paper))

        if !isBlinking {
            let look = pupilOffset(time: time)
            let lp = CGRect(
                x: leftEye.midX - leftEye.width * 0.20 + look.x * leftEye.width * 0.22,
                y: leftEye.midY - leftEye.width * 0.20 + look.y * leftEye.height * 0.30,
                width: leftEye.width * 0.40, height: leftEye.width * 0.40
            )
            let rp = CGRect(
                x: rightEye.midX - rightEye.width * 0.19 + look.x * rightEye.width * 0.22,
                y: rightEye.midY - rightEye.width * 0.19 + look.y * rightEye.height * 0.30,
                width: rightEye.width * 0.38, height: rightEye.width * 0.38
            )
            context.fill(Path(ellipseIn: lp), with: .color(Ink.ink))
            context.fill(Path(ellipseIn: rp), with: .color(Ink.ink))
        }

        // --- Brows: the single biggest carrier of mood ---
        if let brow = browAngles {
            var left = Path()
            left.move(to: p(0.225, 0.375 - brow.left * 0.05))
            left.addLine(to: p(0.445, 0.375 + brow.left * 0.05))
            context.stroke(left, with: .color(Ink.paper), style: StrokeStyle(lineWidth: s * 0.035, lineCap: .round))

            var right = Path()
            right.move(to: p(0.535, 0.405 + brow.right * 0.05))
            right.addLine(to: p(0.705, 0.405 - brow.right * 0.05))
            context.stroke(right, with: .color(Ink.paper), style: StrokeStyle(lineWidth: s * 0.032, lineCap: .round))
        }

        // --- Mouth ---
        drawMouth(in: &context, p: p, r: r, s: s, time: time)

        // --- Mood extras ---
        drawExtras(in: &context, p: p, r: r, s: s, time: time)
    }

    private func drawMouth(
        in context: inout GraphicsContext,
        p: (CGFloat, CGFloat) -> CGPoint,
        r: (CGFloat, CGFloat, CGFloat, CGFloat) -> CGRect,
        s: CGFloat,
        time: TimeInterval
    ) {
        switch mood {
        case .feral, .triumphant:
            // Jagged grin knocked out of the ink.
            var grin = Path()
            let top: CGFloat = 0.665, bottom: CGFloat = 0.735
            let teethCount = 5
            let startX: CGFloat = 0.275, endX: CGFloat = 0.665
            grin.move(to: p(startX, top))
            for i in 0...(teethCount * 2) {
                let t = CGFloat(i) / CGFloat(teethCount * 2)
                let x = startX + (endX - startX) * t
                grin.addLine(to: p(x, i % 2 == 0 ? top : top + 0.055))
            }
            grin.addLine(to: p(endX, bottom))
            grin.addLine(to: p(startX, bottom))
            grin.closeSubpath()
            context.fill(grin, with: .color(Ink.paper))

        case .listening:
            // Open mouth that pulses with an implied waveform.
            let pulse = 0.5 + 0.5 * CGFloat(sin(time * 7))
            let h = 0.055 + pulse * 0.075
            context.fill(
                Path(ellipseIn: r(0.375, 0.655, 0.22, h)),
                with: .color(Ink.paper)
            )

        case .pleased:
            var smile = Path()
            smile.move(to: p(0.315, 0.675))
            smile.addQuadCurve(to: p(0.625, 0.675), control: p(0.470, 0.775))
            context.stroke(smile, with: .color(Ink.paper), style: StrokeStyle(lineWidth: s * 0.045, lineCap: .round))

        case .impatient, .bored:
            var flat = Path()
            flat.move(to: p(0.325, 0.700))
            flat.addQuadCurve(to: p(0.615, 0.712), control: p(0.470, 0.690))
            context.stroke(flat, with: .color(Ink.paper), style: StrokeStyle(lineWidth: s * 0.038, lineCap: .round))

        case .thinking:
            context.fill(Path(ellipseIn: r(0.415, 0.680, 0.10, 0.055)), with: .color(Ink.paper))

        case .watching:
            var flat = Path()
            flat.move(to: p(0.335, 0.700))
            flat.addLine(to: p(0.605, 0.700))
            context.stroke(flat, with: .color(Ink.paper), style: StrokeStyle(lineWidth: s * 0.036, lineCap: .round))
        }
    }

    private func drawExtras(
        in context: inout GraphicsContext,
        p: (CGFloat, CGFloat) -> CGPoint,
        r: (CGFloat, CGFloat, CGFloat, CGFloat) -> CGRect,
        s: CGFloat,
        time: TimeInterval
    ) {
        switch mood {
        case .feral, .impatient:
            // Anger ticks, top right.
            let intensity: CGFloat = mood == .feral ? 1 : 0.6
            for i in 0..<3 {
                var tick = Path()
                let y = 0.16 + CGFloat(i) * 0.055
                tick.move(to: p(0.80, y))
                tick.addLine(to: p(0.80 + 0.09 * intensity, y - 0.035 * intensity))
                context.stroke(tick, with: .color(Ink.ink), style: StrokeStyle(lineWidth: s * 0.022, lineCap: .round))
            }

        case .listening:
            // Sound arcs radiating from the left, riding the same pulse as the mouth.
            for i in 0..<3 {
                let phase = time * 2.4 - Double(i) * 0.4
                let alpha = 0.55 - CGFloat(i) * 0.15
                let spread = 0.03 + CGFloat(i) * 0.045 + CGFloat(sin(phase)) * 0.012
                var arc = Path()
                arc.move(to: p(0.08 - spread, 0.45))
                arc.addQuadCurve(to: p(0.08 - spread, 0.70), control: p(0.02 - spread * 1.4, 0.575))
                context.stroke(arc, with: .color(Ink.ink.opacity(alpha)), style: StrokeStyle(lineWidth: s * 0.022, lineCap: .round))
            }

        case .thinking:
            // Three dots cycling above the head.
            for i in 0..<3 {
                let phase = sin(time * 3.4 - Double(i) * 0.7)
                let lift = CGFloat(phase) * 0.022
                let alpha = 0.4 + CGFloat(phase) * 0.35
                context.fill(
                    Path(ellipseIn: r(0.78 + CGFloat(i) * 0.065, 0.12 - lift, 0.042, 0.042)),
                    with: .color(Ink.ink.opacity(alpha))
                )
            }

        case .triumphant:
            // Confetti flecks.
            var rng = SeededRNG(0xC0FFEE)
            for _ in 0..<7 {
                let x = rng.value(in: 0.02...0.95)
                let y = rng.value(in: 0.02...0.30)
                let w = rng.value(in: 0.018...0.04)
                context.fill(Path(r(x, y, w, w * 0.6)), with: .color(Ink.ink.opacity(rng.value(in: 0.3...0.85))))
            }

        case .bored:
            // A single drooping "z" — not asleep, just unimpressed.
            var z = Path()
            z.move(to: p(0.80, 0.16))
            z.addLine(to: p(0.90, 0.16))
            z.addLine(to: p(0.80, 0.25))
            z.addLine(to: p(0.90, 0.25))
            context.stroke(z, with: .color(Ink.ink.opacity(0.5)), style: StrokeStyle(lineWidth: s * 0.02, lineCap: .round, lineJoin: .round))

        case .watching, .pleased:
            break
        }
    }

    // MARK: - Mood parameters

    private struct Horn {
        var baseX: CGFloat, baseY: CGFloat, tipX: CGFloat, tipY: CGFloat, width: CGFloat
    }

    /// Asymmetric on purpose — a matched pair looks like a logo, not a creature.
    private var horns: [Horn] {
        [
            Horn(baseX: 0.275, baseY: 0.33, tipX: 0.155, tipY: 0.06, width: 0.075),
            Horn(baseX: 0.690, baseY: 0.335, tipX: 0.815, tipY: 0.115, width: 0.062)
        ]
    }

    /// 1 = wide open, lower = squinting.
    private var eyeSquint: CGFloat {
        switch mood {
        case .feral: return 1.15
        case .listening: return 1.05
        case .impatient: return 0.62
        case .bored: return 0.45
        case .pleased: return 0.8
        case .triumphant: return 1.0
        case .thinking: return 0.7
        case .watching: return 0.9
        }
    }

    /// Positive tilts inward (angry), negative tilts outward (worried/sad).
    private var browAngles: (left: CGFloat, right: CGFloat)? {
        switch mood {
        case .feral: return (1.0, 1.0)
        case .impatient: return (0.65, 0.65)
        case .bored: return (-0.35, -0.35)
        case .thinking: return (0.3, -0.4)
        default: return nil
        }
    }

    /// Where the pupils point. Idle moods drift; focused moods lock on.
    private func pupilOffset(time: TimeInterval) -> CGPoint {
        guard animated else { return .zero }
        switch mood {
        case .bored:
            // Slow, disinterested wander.
            return CGPoint(x: CGFloat(sin(time * 0.6)) * 0.9, y: 0.5)
        case .thinking:
            // Looking up and away.
            return CGPoint(x: CGFloat(sin(time * 0.9)) * 0.7, y: -0.8)
        case .listening:
            return CGPoint(x: 0, y: -0.15)
        case .feral, .impatient:
            return .zero
        default:
            return CGPoint(x: CGFloat(sin(time * 0.4)) * 0.35, y: CGFloat(cos(time * 0.31)) * 0.25)
        }
    }

    private var accessibilityDescription: String {
        switch mood {
        case .bored: return "Mascot looking bored"
        case .watching: return "Mascot watching"
        case .impatient: return "Mascot looking impatient"
        case .feral: return "Mascot looking angry"
        case .pleased: return "Mascot looking pleased"
        case .triumphant: return "Mascot celebrating"
        case .listening: return "Mascot listening"
        case .thinking: return "Mascot thinking"
        }
    }
}

// MARK: - Banner

/// The "reactive but quiet" surface: the creature plus one line, shown only when
/// the mood is worth interrupting for.
struct MascotBanner: View {
    var mood: MascotMood
    var line: String
    var size: CGFloat = 54

    var body: some View {
        HStack(spacing: 12) {
            MascotView(mood: mood)
                .frame(width: size, height: size)

            Text(line)
                .inkHeading(17)
                .foregroundStyle(Ink.ink)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .transition(.asymmetric(
            insertion: .push(from: .leading).combined(with: .opacity),
            removal: .opacity
        ))
        // One stop, not two — the mascot's own mood label and the line next
        // to it are two views of the same information.
        .accessibilityElement(children: .combine)
    }
}

#Preview("Moods") {
    ZStack {
        PaperBackground()
        ScrollView {
            VStack(spacing: 20) {
                ForEach(MascotMood.allCases, id: \.self) { mood in
                    HStack(spacing: 16) {
                        MascotView(mood: mood).frame(width: 76, height: 76)
                        VStack(alignment: .leading) {
                            Text(mood.rawValue).inkTitle(20).posterCase()
                            Text(MascotVoice.line(for: mood, overdue: 3, done: 2, remaining: 4))
                                .inkBodySmall()
                                .foregroundStyle(Ink.inkSoft)
                        }
                        Spacer()
                    }
                }
            }
            .padding(24)
        }
    }
}
