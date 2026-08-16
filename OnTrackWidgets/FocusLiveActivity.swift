import ActivityKit
import SwiftUI
import WidgetKit

/// The Lock Screen and Dynamic Island glue for a running Focus session — the
/// views themselves live in Shared. See `FocusActivityAttributes` for why
/// this is read-only, tap-to-open.
struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            FocusLiveActivityView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Ink.paper)
                .activitySystemActionForegroundColor(Ink.ink)
                .widgetURL(URL(string: "ontrack://focus"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    FocusIslandExpandedLeading(attributes: context.attributes)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    FocusIslandExpandedTrailing(state: context.state)
                }
            } compactLeading: {
                FocusIslandCompactLeading()
            } compactTrailing: {
                FocusIslandCompactTrailing(state: context.state)
            } minimal: {
                FocusIslandMinimal(state: context.state)
            }
            .widgetURL(URL(string: "ontrack://focus"))
            .keylineTint(Ink.ink)
        }
    }
}
