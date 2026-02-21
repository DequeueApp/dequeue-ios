//
//  DequeueWidgetBundle.swift
//  DequeueWidgets
//
//  Widget bundle containing all Dequeue widgets: Active Stack, Up Next, and Quick Stats.
//
//  DEQ-120, DEQ-121
//

import SwiftUI
import WidgetKit

@main
struct DequeueWidgetBundle: WidgetBundle {
    var body: some Widget {
        ActiveStackWidget()
        UpNextWidget()
        QuickStatsWidget()
    }
}
