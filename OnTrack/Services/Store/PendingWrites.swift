import Foundation

/// Writes that haven't reached the server yet.
///
/// Without this, anything captured offline exists only in memory: the failed
/// upsert is never retried, and the next refresh replaces the in-memory list
/// with server state — silently destroying it. Queuing to disk means a task
/// spoken in aeroplane mode survives a relaunch and lands when the network
/// comes back.
actor PendingWrites {
    private struct Payload: Codable {
        var upserts: [TaskItem] = []
        var deletes: [UUID] = []
    }

    private let fileURL: URL
    private var cache: Payload?

    init(filename: String = "pending-writes.json") {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent(filename)
    }

    // MARK: - Queueing

    func enqueueUpserts(_ items: [TaskItem]) {
        guard !items.isEmpty else { return }
        var payload = load()
        for item in items {
            payload.upserts.removeAll { $0.id == item.id }
            payload.upserts.append(item)
            // A re-created task is no longer pending deletion.
            payload.deletes.removeAll { $0 == item.id }
        }
        save(payload)
    }

    func enqueueDeletes(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        var payload = load()
        for id in ids {
            // Never uploaded, now deleted — the queued upsert is moot. But a row
            // that reached the server still needs the delete to be sent.
            payload.upserts.removeAll { $0.id == id }
            if !payload.deletes.contains(id) { payload.deletes.append(id) }
        }
        save(payload)
    }

    // MARK: - Draining

    func snapshot() -> (upserts: [TaskItem], deletes: [UUID]) {
        let payload = load()
        return (payload.upserts, payload.deletes)
    }

    var isEmpty: Bool {
        let payload = load()
        return payload.upserts.isEmpty && payload.deletes.isEmpty
    }

    /// Clears only what was successfully sent, so anything queued mid-flush survives.
    func clearUpserts(_ ids: [UUID]) {
        var payload = load()
        payload.upserts.removeAll { ids.contains($0.id) }
        save(payload)
    }

    func clearDeletes(_ ids: [UUID]) {
        var payload = load()
        payload.deletes.removeAll { ids.contains($0) }
        save(payload)
    }

    func clearAll() {
        save(Payload())
    }

    // MARK: - Storage

    private func load() -> Payload {
        if let cache { return cache }
        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONCoding.decoder.decode(Payload.self, from: data) else {
            cache = Payload()
            return cache!
        }
        cache = payload
        return payload
    }

    private func save(_ payload: Payload) {
        cache = payload
        guard let data = try? JSONCoding.encoder.encode(payload) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
