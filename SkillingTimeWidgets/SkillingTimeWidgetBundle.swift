import SwiftUI
import WidgetKit

@main
struct SkillingTimeWidgetBundle: WidgetBundle {
    var body: some Widget {
        SkillingTimeLiveActivityWidget()
        SkillingTimeTodayWidget()
        SkillingTimeQuickStartWidget()
        if #available(iOS 18.0, *) {
            StartSkillControl()
        }
    }
}
