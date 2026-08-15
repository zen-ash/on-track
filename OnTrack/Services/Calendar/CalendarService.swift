import EventKit
import Foundation

/// Read-only calendar access for the daily planner. Nothing in this file ever
/// calls a write API — no save, no remove — even though the permission
/// EventKit actually grants (`requestFullAccessToEvents`) is technically
/// capable of both; there is no OS-level "read-only" calendar grant to ask
/// for instead, so the read-only promise is enforced by this file's contents
/// rather than by the permission itself. Only start/end times ever leave this
/// type — see `BusyBlock`.
actor CalendarService {
    private let store = EKEventStore()

    enum AccessState: Sendable {
        case notDetermined
        case denied
        case authorized
    }

    var accessState: AccessState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            return .notDetermined
        case .fullAccess:
            return .authorized
        default:
            // .writeOnly can't happen — this app never requests it — and
            // .restricted/.denied both mean the same thing to the caller:
            // nothing to read.
            return .denied
        }
    }

    /// Shows the system prompt if authorization has never been decided.
    /// Returns whether the app can read events afterwards.
    @discardableResult
    func requestAccess() async -> Bool {
        guard accessState != .authorized else { return true }
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        return granted && accessState == .authorized
    }

    /// Every non-all-day event on `date`, across every calendar the user has
    /// added to Calendar.app. All-day events are excluded on purpose — a
    /// subscribed Birthdays or Holidays calendar would otherwise read as
    /// "busy all day" and swamp the plan with a block that isn't real.
    func busyBlocks(on date: Date, calendar: Calendar = .current) -> [BusyBlock] {
        guard accessState == .authorized else { return [] }
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let blocks = store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .map { BusyBlock(start: $0.startDate, end: $0.endDate) }
            .sorted { $0.start < $1.start }

        // A stuffed calendar shouldn't blow out the prompt any more than a
        // stuffed task list does — capture and plan both cap what they send
        // the same way.
        return Array(blocks.prefix(40))
    }
}
