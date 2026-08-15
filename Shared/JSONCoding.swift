import Foundation

/// Shared coders. Snake case on the wire matches the Postgres columns exactly,
/// so the same `TaskItem` round-trips through the server, the on-device store,
/// and the widget's own snapshot file untouched.
enum JSONCoding {
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = DateParsing.iso8601(raw) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognised date: \(raw)")
        }
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(DateParsing.iso8601String(date))
        }
        return e
    }()
}

enum DateParsing {
    /// Postgres hands back timestamps with a variable number of fractional
    /// digits and sometimes no zone, so try the tolerant paths in order.
    // Foundation's date formatters are documented as safe for concurrent
    // formatting once configured, but they aren't marked Sendable.
    nonisolated(unsafe) private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let postgresNoZone: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    static func iso8601(_ raw: String) -> Date? {
        if let d = withFraction.date(from: raw) { return d }
        if let d = plain.date(from: raw) { return d }
        // Trim fractional seconds Postgres sometimes emits at odd precisions.
        if let dot = raw.firstIndex(of: "."),
           let plus = raw.range(of: "+", range: dot..<raw.endIndex) ?? raw.range(of: "Z", range: dot..<raw.endIndex) {
            let trimmed = String(raw[raw.startIndex..<dot]) + String(raw[plus.lowerBound...])
            if let d = plain.date(from: trimmed) { return d }
        }
        return postgresNoZone.date(from: String(raw.prefix(19)))
    }

    static func iso8601String(_ date: Date) -> String {
        withFraction.string(from: date)
    }
}
