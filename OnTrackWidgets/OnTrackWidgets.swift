import AppIntents
import SwiftUI
import WidgetKit

private let captureURL = URL(string: "ontrack://capture")!

@main
struct OnTrackWidgetsBundle: WidgetBundle {
    var body: some Widget {
        QuickCaptureControl()
        QuickCaptureLockScreenWidget()
        TodayWidget()
    }
}

// MARK: - Control Centre

/// Appears in Control Centre, and can also be bound to the Action Button.
/// It opens the app's capture deep link rather than owning any logic, so there's
/// exactly one capture implementation in the project.
struct QuickCaptureControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.aayush.ontrack.control.capture") {
            ControlWidgetButton(action: OpenURLIntent(captureURL)) {
                Label("Capture", systemImage: "waveform")
            }
        }
        .displayName("Capture")
        .description("Speak a task straight into On Track.")
    }
}

// MARK: - Lock Screen

struct QuickCaptureLockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.capture, provider: CaptureProvider()) { _ in
            CaptureWidgetView()
                .widgetURL(captureURL)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Capture")
        .description("One tap from the Lock Screen to speak a task.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}

struct CaptureEntry: TimelineEntry {
    let date: Date
}

struct CaptureProvider: TimelineProvider {
    func placeholder(in context: Context) -> CaptureEntry {
        CaptureEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (CaptureEntry) -> Void) {
        completion(CaptureEntry(date: Date()))
    }

    /// Nothing here changes over time — it's a button, not a readout.
    func getTimeline(in context: Context, completion: @escaping (Timeline<CaptureEntry>) -> Void) {
        completion(Timeline(entries: [CaptureEntry(date: Date())], policy: .never))
    }
}

struct CaptureWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular:
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.system(size: 17, weight: .black))
                    VStack(alignment: .leading, spacing: 0) {
                        Text("ON TRACK")
                            .font(.system(size: 11, weight: .black).width(.compressed))
                        Text("Say it")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    Spacer(minLength: 0)
                }

            default:
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "waveform")
                        .font(.system(size: 20, weight: .black))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Capture with On Track")
    }
}
