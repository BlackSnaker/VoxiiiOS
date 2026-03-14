import SwiftUI
import WidgetKit

@main
struct VixiiLiveActivitiesBundle: WidgetBundle {
    var body: some Widget {
        VoxiiInboxSummaryWidget()
        VoxiiInboxContactsWidget()
        VoxiiInboxDashboardWidget()
        VoxiiCallLiveActivityWidget()
        VoxiiMessageLiveActivityWidget()
    }
}
