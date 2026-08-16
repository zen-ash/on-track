import Foundation

/// Everything the UI needs to persist Focus tracks and sessions, mirroring
/// `TaskStore`'s shape so the local and Supabase paths stay interchangeable
/// the same way.
protocol FocusStore: Sendable {
    /// Every track, archived included — small dataset, no pagination, and
    /// resolving a past session's track name needs archived ones too.
    func loadTracks() async throws -> [FocusTrack]
    func upsertTracks(_ tracks: [FocusTrack]) async throws

    /// Completed sessions started on or after `since`.
    func loadSessions(since: Date) async throws -> [FocusSession]
    func upsertSessions(_ sessions: [FocusSession]) async throws
}
