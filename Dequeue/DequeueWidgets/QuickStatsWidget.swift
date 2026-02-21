//
//  QuickStatsWidget.swift
//  DequeueWidgets
//
//  Shows quick task statistics: completed today, pending, and completion rate.
//  Available in small size for Home Screen and Lock Screen accessories.
//
//  DEQ-120, DEQ-121
//

import SwiftUI
import WidgetKit

// MARK: - Timeline Provider

struct QuickStatsProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickStatsEntry {
        QuickStatsEntry(
            date: Date(),
            data: WidgetStatsData(
                completedToday: 5,
                pendingTotal: 12,
                activeStackCount: 3,
                overdueCount: 1,
                completionRate: 0.42
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickStatsEntry) -> Void) {
        let data = WidgetDataReader.readStats()
        completion(QuickStatsEntry(date: Date(), data: data))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickStatsEntry>) -> Void) {
        let data = WidgetDataReader.readStats()
        let entry = QuickStatsEntry(date: Date(), data: data)

        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Timeline Entry

struct QuickStatsEntry: TimelineEntry {
    let date: Date
    let data: WidgetStatsData?
}

// MARK: - Widget Definition

struct QuickStatsWidget: Widget {
    let kind = "QuickStatsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickStatsProvider()) { entry in
            QuickStatsWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Quick Stats")
        .description("Today's task completion stats at a glance.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Widget Views

struct QuickStatsWidgetView: View {
    let entry: QuickStatsEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .accessoryRectangular:
            lockScreenRectangularView
        case .accessoryInline:
            lockScreenInlineView
        default:
            smallView
        }
    }

    // MARK: - Small Widget

    private var smallView: some View {
        VStack(spacing: 8) {
            if let data = entry.data {
                // Completion ring
                ZStack {
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                        .frame(width: 64, height: 64)

                    Circle()
                        .trim(from: 0, to: data.completionRate)
                        .stroke(
                            completionColor(for: data.completionRate),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .frame(width: 64, height: 64)
                        .rotationEffect(.degrees(-90))

                    Text("\(Int(data.completionRate * 100))%")
                        .font(.caption)
                        .fontWeight(.bold)
                }

                // Stats grid
                HStack(spacing: 12) {
                    StatItem(
                        value: "\(data.completedToday)",
                        label: "Done",
                        color: .green
                    )

                    StatItem(
                        value: "\(data.pendingTotal)",
                        label: "Left",
                        color: .blue
                    )

                    if data.overdueCount > 0 {
                        StatItem(
                            value: "\(data.overdueCount)",
                            label: "Late",
                            color: .red
                        )
                    }
                }
            } else {
                emptyState
            }
        }
        .widgetURL(URL(string: "dequeue://stats"))
    }

    // MARK: - Lock Screen Rectangular

    private var lockScreenRectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let data = entry.data {
                HStack(spacing: 4) {
                    Image(systemName: "chart.bar.fill")
                        .font(.caption2)
                    Text("Today")
                        .font(.caption)
                        .fontWeight(.semibold)
                }

                HStack(spacing: 8) {
                    Label("\(data.completedToday) done", systemImage: "checkmark.circle")
                        .font(.caption2)

                    Label("\(data.pendingTotal) left", systemImage: "circle")
                        .font(.caption2)
                }

                if data.overdueCount > 0 {
                    Label("\(data.overdueCount) overdue", systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No task data")
                    .font(.caption)
                Text("Open Dequeue to sync")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Lock Screen Inline

    @ViewBuilder
    private var lockScreenInlineView: some View {
        if let data = entry.data {
            if data.overdueCount > 0 {
                Text("✅ \(data.completedToday) done · \(data.pendingTotal) left · ⚠️ \(data.overdueCount) overdue")
            } else {
                Text("✅ \(data.completedToday) done · \(data.pendingTotal) left")
            }
        } else {
            Text("Dequeue — Open to sync")
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No Stats Yet")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func completionColor(for rate: Double) -> Color {
        switch rate {
        case 0.75...: return .green
        case 0.5..<0.75: return .blue
        case 0.25..<0.5: return .orange
        default: return .red
        }
    }
}

// MARK: - Stat Item

struct StatItem: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    QuickStatsWidget()
} timeline: {
    QuickStatsEntry(
        date: .now,
        data: WidgetStatsData(
            completedToday: 7,
            pendingTotal: 5,
            activeStackCount: 3,
            overdueCount: 2,
            completionRate: 0.58
        )
    )
    QuickStatsEntry(date: .now, data: nil)
}
