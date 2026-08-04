import Foundation

/// The creature only shows up when it has something to say. Each mood is a
/// distinct face *and* a distinct reason for being on screen.
enum MascotMood: String, CaseIterable, Sendable {
    /// Nothing on the list. Slouched, unimpressed.
    case bored
    /// Normal working state — watching you, saying nothing.
    case watching
    /// Something is late.
    case impatient
    /// A lot of things are late.
    case feral
    /// You've knocked a few out.
    case pleased
    /// Everything due today is done.
    case triumphant
    /// Mic is hot.
    case listening
    /// Waiting on the model.
    case thinking

    /// Whether this mood is worth interrupting the list for. `watching` is the
    /// quiet default and deliberately renders nothing in banners.
    var isWorthShowing: Bool {
        self != .watching
    }
}

/// Lines are short, dry, and never cute. The creature is a flatmate who thinks
/// you could be doing better, not a mascot selling you something.
enum MascotVoice {
    static func line(for mood: MascotMood, overdue: Int = 0, done: Int = 0, remaining: Int = 0) -> String {
        switch mood {
        case .bored:
            return ["Nothing here.", "Empty. Suspicious.", "So we're just vibing.", "Say something. I'll write it down."]
                .randomElement()!
        case .watching:
            return remaining == 1 ? "One left." : "\(remaining) left."
        case .impatient:
            return overdue == 1 ? "One thing is late." : "\(overdue) things are late."
        case .feral:
            return ["\(overdue) overdue. Bold.", "\(overdue) late. I'm counting.", "This is a lot of late."]
                .randomElement()!
        case .pleased:
            return done == 1 ? "One down." : "\(done) down. Keep moving."
        case .triumphant:
            return ["Today is clear.", "Done. Go outside.", "Nothing left. Rare."].randomElement()!
        case .listening:
            return "Talking. I'm listening."
        case .thinking:
            return "Thinking…"
        }
    }

    /// Picks the mood from real state, in priority order — lateness beats
    /// progress, progress beats idle.
    static func mood(overdue: Int, dueToday: Int, doneToday: Int) -> MascotMood {
        if overdue >= 5 { return .feral }
        if overdue > 0 { return .impatient }
        if dueToday == 0 && doneToday == 0 { return .bored }
        if dueToday == 0 && doneToday > 0 { return .triumphant }
        if doneToday > 0 { return .pleased }
        return .watching
    }
}
