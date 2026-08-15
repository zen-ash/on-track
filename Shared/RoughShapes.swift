import SwiftUI

/// A rectangle drawn by a slightly unsteady hand. Points are sampled along the
/// perimeter, nudged off true, then joined with curves so the result reads as a
/// pen stroke rather than a polygon.
struct RoughRect: Shape {
    var seed: UInt64 = 7
    var wobble: CGFloat = 2.2
    var corner: CGFloat = 4
    /// Samples per edge. More samples = looser, sketchier line.
    var samplesPerEdge: Int = 5

    func path(in rect: CGRect) -> Path {
        var rng = SeededRNG(seed)
        let inset = rect.insetBy(dx: wobble, dy: wobble)
        guard inset.width > 0, inset.height > 0 else { return Path(rect) }

        var points: [CGPoint] = []

        func sample(from a: CGPoint, to b: CGPoint) {
            for i in 0..<samplesPerEdge {
                let t = CGFloat(i) / CGFloat(samplesPerEdge)
                points.append(CGPoint(
                    x: a.x + (b.x - a.x) * t + rng.jitter(wobble),
                    y: a.y + (b.y - a.y) * t + rng.jitter(wobble)
                ))
            }
        }

        // Corners pulled in by `corner` so the joins look softened, not mitred.
        let tl = CGPoint(x: inset.minX + corner, y: inset.minY)
        let tr = CGPoint(x: inset.maxX - corner, y: inset.minY)
        let rt = CGPoint(x: inset.maxX, y: inset.minY + corner)
        let rb = CGPoint(x: inset.maxX, y: inset.maxY - corner)
        let br = CGPoint(x: inset.maxX - corner, y: inset.maxY)
        let bl = CGPoint(x: inset.minX + corner, y: inset.maxY)
        let lb = CGPoint(x: inset.minX, y: inset.maxY - corner)
        let lt = CGPoint(x: inset.minX, y: inset.minY + corner)

        sample(from: tl, to: tr)
        sample(from: rt, to: rb)
        sample(from: br, to: bl)
        sample(from: lb, to: lt)

        return Path.throughSmoothed(points, closed: true)
    }
}

/// A hand-drawn horizontal rule. Give each one a different seed or every
/// divider on screen will have an identical, obviously-fake wobble.
struct RoughRule: Shape {
    var seed: UInt64 = 3
    var wobble: CGFloat = 1.1

    func path(in rect: CGRect) -> Path {
        var rng = SeededRNG(seed)
        let steps = max(4, Int(rect.width / 26))
        let midY = rect.midY
        var points: [CGPoint] = []
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            points.append(CGPoint(x: rect.minX + rect.width * t, y: midY + rng.jitter(wobble)))
        }
        return Path.throughSmoothed(points, closed: false)
    }
}

/// A blob — the base silhouette for the mascot and for "ink splat" accents.
struct RoughBlob: Shape {
    var seed: UInt64 = 11
    var lumpiness: CGFloat = 0.07

    func path(in rect: CGRect) -> Path {
        var rng = SeededRNG(seed)
        let steps = 22
        let cx = rect.midX, cy = rect.midY
        let rx = rect.width / 2, ry = rect.height / 2
        // Fixed harmonics keep the blob organic but never spiky.
        let phase1 = rng.value(in: 0...6.28)
        let phase2 = rng.value(in: 0...6.28)

        var points: [CGPoint] = []
        for i in 0..<steps {
            let t = CGFloat(i) / CGFloat(steps) * .pi * 2
            let wob = 1
                + lumpiness * sin(t * 3 + phase1)
                + lumpiness * 0.6 * sin(t * 5 + phase2)
            points.append(CGPoint(x: cx + cos(t) * rx * wob, y: cy + sin(t) * ry * wob))
        }
        return Path.throughSmoothed(points, closed: true)
    }
}

/// The completion mark. Built to be revealed with `.trim` so it draws on like a
/// real stroke instead of fading in.
struct BrushCheck: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: rect.minX + w * 0.12, y: rect.minY + h * 0.52))
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + w * 0.40, y: rect.minY + h * 0.82),
            control: CGPoint(x: rect.minX + w * 0.22, y: rect.minY + h * 0.74)
        )
        p.addQuadCurve(
            to: CGPoint(x: rect.minX + w * 0.92, y: rect.minY + h * 0.14),
            control: CGPoint(x: rect.minX + w * 0.68, y: rect.minY + h * 0.40)
        )
        return p
    }
}

extension Path {
    /// Joins points with quadratic curves through their midpoints — the standard
    /// trick for turning a jittered point list into something that looks drawn.
    static func throughSmoothed(_ points: [CGPoint], closed: Bool) -> Path {
        var path = Path()
        guard points.count > 2 else {
            guard let first = points.first else { return path }
            path.move(to: first)
            points.dropFirst().forEach { path.addLine(to: $0) }
            return path
        }

        if closed {
            let start = CGPoint(
                x: (points[points.count - 1].x + points[0].x) / 2,
                y: (points[points.count - 1].y + points[0].y) / 2
            )
            path.move(to: start)
            for i in 0..<points.count {
                let current = points[i]
                let next = points[(i + 1) % points.count]
                let mid = CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2)
                path.addQuadCurve(to: mid, control: current)
            }
            path.closeSubpath()
        } else {
            path.move(to: points[0])
            for i in 1..<(points.count - 1) {
                let current = points[i]
                let next = points[i + 1]
                let mid = CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2)
                path.addQuadCurve(to: mid, control: current)
            }
            path.addLine(to: points[points.count - 1])
        }
        return path
    }
}
