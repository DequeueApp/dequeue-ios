//
//  ActiveStackWidget.swift
//  DequeueWidgets
//
//  Shows the currently active stack with its top task.
//  Available in small and medium sizes for Home Screen and Lock Screen.
//
//  DEQ-120, DEQ-121
//

import SwiftUI
import WidgetKit

// MARK: - Timeline Provider

struct ActiveStackProvider: TimelineProvider {
    func placeholder(in context: Context) -> ActiveStackEntry {
        ActiveStackEntry(
            date: Date(),
            data: WidgetActiveStackData(
                stackTitle: "Morning Routine",
                stackId: "placeholder",
                activeTaskTitle: "Review daily goals",
                activeTaskId: "placeholder-task",
                pendingTaskCount: 3,
                totalTaskCount: 5,
                dueDate: nil,
                priority: nil,
                tags: []
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ActiveStackEntry) -> Void) {
        let data = WidgetDataReader.readActiveStack()
        completion(ActiveStackEntry(date: Date(), data: data))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ActiveStackEntry>) -> Void) {
        let data = WidgetDataReader.readActiveStack()
        let entry = ActiveStackEntry(date: Date(), data: data)

        // Refresh every 15 minutes (in addition to app-triggered refreshes)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Timeline Entry

struct ActiveStackEntry: TimelineEntry {
    let date: Date
    let data: WidgetActiveStackData?
}

// MARK: - Widget Definition

struct ActiveStackWidget: Widget {
    let kind = "ActiveStackWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ActiveStackProvider()) { entry in
            ActiveStackWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Active Stack")
        .description("Shows your currently focused stack and top task.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}

// MARK: - Widget Views

struct ActiveStackWidgetView: View {
    let entry: ActiveStackEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumView
        case .accessoryRectangular:
            lockScreenRectangularView
        case .accessoryCircular:
            lockScreenCircularView
        default:
            smallView
        }
    }

    // MARK: - Small Widget

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let data = entry.data {
                // Stack title
                HStack(spacing: 4) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(data.stackTitle)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Active task
                if let taskTitle = data.activeTaskTitle {
                    Text(taskTitle)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                } else {
                    Text("All done! 🎉")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                Spacer()

                // Progress
                HStack {
                    let completed = data.totalTaskCount - data.pendingTaskCount
                    Text("\(completed)/\(data.totalTaskCount)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if let dueDate = data.dueDate {
                        Label(dueDate.widgetRelativeString, systemImage: "clock")
                            .font(.caption2)
                            .foregroundStyle(dueDate < Date() ? .red : .secondary)
                    }
                }
            } else {
                emptyStateSmall
            }
        }
        .widgetURL(widgetURL)
    }

    // MARK: - Medium Widget

    private var mediumView: some View {
        HStack(spacing: 12) {
            if let data = entry.data {
                // Left: Stack info
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                        Text(data.stackTitle)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                    }

                    Spacer()

                    // Active task
                    if let taskTitle = data.activeTaskTitle {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Up Next")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            Text(taskTitle)
                                .font(.callout)
                                .fontWeight(.medium)
                                .lineLimit(2)
                        }
                    } else {
                        Text("All tasks completed! 🎉")
                            .font(.callout)
                    }

                    Spacer()

                    // Tags
                    if !data.tags.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(data.tags.prefix(3), id: \.self) { tag in
                                Text(tag)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.quaternary)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                Spacer()

                // Right: Progress ring
                VStack {
                    Spacer()
                    ProgressRingView(
                        completed: data.totalTaskCount - data.pendingTaskCount,
                        total: data.totalTaskCount
                    )
                    Spacer()

                    if let dueDate = data.dueDate {
                        Label(dueDate.widgetRelativeString, systemImage: "clock")
                            .font(.caption2)
                            .foregroundStyle(dueDate < Date() ? .red : .secondary)
                    }
                }
                .frame(width: 60)
            } else {
                emptyStateMedium
            }
        }
        .widgetURL(widgetURL)
    }

    // MARK: - Lock Screen Rectangular

    private var lockScreenRectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let data = entry.data {
                HStack(spacing: 4) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.caption2)
                    Text(data.stackTitle)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }

                if let taskTitle = data.activeTaskTitle {
                    Text(taskTitle)
                        .font(.caption2)
                        .lineLimit(1)
                }

                let completed = data.totalTaskCount - data.pendingTaskCount
                Text("\(completed)/\(data.totalTaskCount) tasks")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("No active stack")
                    .font(.caption)
                Text("Open Dequeue to start")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Lock Screen Circular

    private var lockScreenCircularView: some View {
        if let data = entry.data {
            let completed = data.totalTaskCount - data.pendingTaskCount
            Gauge(value: Double(completed), in: 0...max(Double(data.totalTaskCount), 1)) {
                Image(systemName: "square.stack.3d.up.fill")
            } currentValueLabel: {
                Text("\(data.pendingTaskCount)")
                    .font(.caption)
            }
            .gaugeStyle(.accessoryCircular)
        } else {
            Gauge(value: 0, in: 0...1) {
                Image(systemName: "square.stack.3d.up.fill")
            } currentValueLabel: {
                Text("–")
                    .font(.caption)
            }
            .gaugeStyle(.accessoryCircular)
        }
    }

    // MARK: - Empty States

    private var emptyStateSmall: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No Active Stack")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateMedium: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("No Active Stack")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Activate a stack in Dequeue to see it here")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var widgetURL: URL? {
        if let data = entry.data {
            return URL(string: "dequeue://stack/\(data.stackId)")
        }
        return URL(string: "dequeue://home")
    }
}

// MARK: - Progress Ring

struct ProgressRingView: View {
    let completed: Int
    let total: Int

    private var progress: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 5)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    progress >= 1.0 ? Color.green : Color.blue,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Text("\(completed)")
                    .font(.title3)
                    .fontWeight(.bold)
                Text("of \(total)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Date Helper

extension Date {
    /// Short relative string for widget display (e.g., "2h", "3d", "Tomorrow")
    var widgetRelativeString: String {
        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.minute, .hour, .day], from: now, to: self)

        if self < now {
            // Overdue
            if let days = components.day, abs(days) > 0 {
                return "\(abs(days))d overdue"
            } else if let hours = components.hour, abs(hours) > 0 {
                return "\(abs(hours))h overdue"
            } else {
                return "Overdue"
            }
        } else {
            // Upcoming
            if let days = components.day, days > 1 {
                return "in \(days)d"
            } else if let days = components.day, days == 1 {
                return "Tomorrow"
            } else if let hours = components.hour, hours > 0 {
                return "in \(hours)h"
            } else if let minutes = components.minute, minutes > 0 {
                return "in \(minutes)m"
            } else {
                return "Now"
            }
        }
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    ActiveStackWidget()
} timeline: {
    ActiveStackEntry(
        date: .now,
        data: WidgetActiveStackData(
            stackTitle: "Morning Routine",
            stackId: "preview-1",
            activeTaskTitle: "Review daily goals and priorities",
            activeTaskId: "task-1",
            pendingTaskCount: 3,
            totalTaskCount: 5,
            dueDate: Calendar.current.date(byAdding: .hour, value: 2, to: Date()),
            priority: 2,
            tags: ["daily", "focus"]
        )
    )
    ActiveStackEntry(date: .now, data: nil)
}

#Preview("Medium", as: .systemMedium) {
    ActiveStackWidget()
} timeline: {
    ActiveStackEntry(
        date: .now,
        data: WidgetActiveStackData(
            stackTitle: "Sprint Planning",
            stackId: "preview-2",
            activeTaskTitle: "Draft sprint goals for Q1 2026",
            activeTaskId: "task-2",
            pendingTaskCount: 2,
            totalTaskCount: 8,
            dueDate: Calendar.current.date(byAdding: .day, value: 1, to: Date()),
            priority: 3,
            tags: ["work", "sprint", "Q1"]
        )
    )
}
