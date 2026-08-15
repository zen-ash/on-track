import Foundation

/// The one thing the app and the widget extension both need to agree on: where
/// their shared container lives. Everything else about how they talk to each
/// other builds on this.
enum AppGroup {
    static let identifier = "group.com.aayush.ontrack"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}

/// Widget kind strings, shared so the app's reload call and the widget's own
/// registration can't drift apart into a silent typo-mismatch.
enum WidgetKind {
    static let today = "com.aayush.ontrack.widget.today"
    static let capture = "com.aayush.ontrack.widget.capture"
}
