//
//  UpNextWidget.swift
//  DequeueWidgets
//
//  Shows upcoming tasks with due dates across all stacks.
//  Available in medium and large sizes.
//
//  DEQ-120
//

import SwiftUI
import WidgetKit

// MARK: - Timeline Provider

struct UpNextProvider: TimelineProvider {
    func placeholder(in context: Context) -> UpNextEntry {
        UpNextEntry(
            date: Date(),
            data: WidgetUpNextData(
                upcomingTasks: [
                    WidgetTaskItem(
                        id: "1", title: "Review pull request",
                        stackTitle: "Sprint", stackId: "s1",
                        dueDate: Calendar.current.date(byAdding: .hour, value: 1, to: Date()),
                        priority: 3, isOverdue: false
                    ),
                    WidgetTaskItem(
                        id: "2", title: "Update documentation",
                        stackTitle: "Docs", stackId: "s2",
                        dueDate: Calendar.current.date(byAdding: .hour, value: 3, to: Date()),
                        priority: 2, isOverdue: false
                    ),
                    WidgetTaskItem(
                        id: "3", title: "Team standup prep",
                        stackTitle: "Daily", stackId: "s3",
                        dueDate: Calendar.current.date(byAdding: .day, value: 1, to: Date()),
                        priority: nil, isOverdue: false
                    )
                ],
                overdueCount: 0
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (UpNextEntry) -> Void) {
        let data = WidgetDataReader.readUpNext()
        completion(UpNextEntry(date: Date(), data: data))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UpNextEntry>) -> Void) {
        let data = WidgetDataReader.readUpNext()
        let entry = UpNextEntry(date: Date(), data: data)

        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Timeline Entry

struct UpNextEntry: TimelineEntry {
    let date: Date
    let data: WidgetUpNextData?
}

// MARK: - Widget Definition

struct UpNextWidget: Widget {
    let kind = "UpNextWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UpNextProvider()) { entry in
            UpNextWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Up Next")
        .description("Your upcoming tasks with due dates.")
        .supportedFamilies([.systemMedium, .systemLarge, .accessoryRectangular])
    }
}

// MARK: - Widget Views

struct UpNextWidgetView: View {
    let entry: UpNextEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemMedium:
            mediumView
        case .systemLarge:
            largeView
        case .accessoryRectangular:
            lockScreenView
        default:
            mediumView
        }
    }

    // MARK: - Medium Widget

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let data = entry.data, !data.upcomingTasks.isEmpty {
                // Header
                HStack {
                    Label("Up Next", systemImage: "clock.arrow.circlepath")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if data.overdueCount > 0 {
                        Text("\(data.overdueCount) overdue")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.red)
                    }
                }

                // Task list (up to 3 in medium)
                ForEach(Array(data.upcomingTasks.prefix(3).enumerated()), id: \.element.id) { index, task in
                    if index > 0 {
                        Divider()
                    }
                    TaskRowView(task: task, compact: true)
                }

                Spacer(minLength: 0)
            } else {
                emptyState
            }
        }
        .widgetURL(URL(string: "dequeue://home"))
    }

    // MARK: - Large Widget

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let data = entry.data, !data.upcomingTasks.isEmpty {
                // Header
                HStack {
                    Label("Up Next", systemImage: "clock.arrow.circlepath")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if data.overdueCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2)
                            Text("\(data.overdueCount) overdue")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(.red)
                    }
                }
                .padding(.bottom, 2)

                // Task list (up to 7 in large)
                ForEach(Array(data.upcomingTasks.prefix(7).enumerated()), id: \.element.id) { index, task in
                    if index > 0 {
                        Divider()
                    }
                    TaskRowView(task: task, compact: false)
                }

                Spacer(minLength: 0)

                if data.upcomingTasks.count > 7 {
                    Text("+\(data.upcomingTasks.count - 7) more")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            } else {
                emptyState
            }
        }
        .widgetURL(URL(string: "dequeue://home"))
    }

    // MARK: - Lock Screen

    private var lockScreenView: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let data = entry.data, let first = data.upcomingTasks.first {
                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption2)
                    Text("Up Next")
                        .font(.caption2)
                        .fontWeight(.semibold)
                }

                Text(first.title)
                    .font(.caption2)
                    .lineLimit(1)

                if let dueDate = first.dueDate {
                    Text(dueDate.widgetRelativeString)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No upcoming tasks")
                    .font(.caption)
                Text("You're all clear!")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.title2)
                .foregroundStyle(.green)
            Text("All Clear!")
                .font(.subheadline)
                .fontWeight(.medium)
            Text("No tasks with upcoming due dates")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Task Row

struct TaskRowView: View {
    let task: WidgetTaskItem
    let compact: Bool

    var body: some View {
        HStack(spacing: 8) {
            // Priority indicator
            if let priority = task.priority {
                PriorityDot(priority: priority)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(task.title)
                    .font(compact ? .caption : .subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if !compact {
                    Text(task.stackTitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let dueDate = task.dueDate {
                Text(dueDate.widgetRelativeString)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(task.isOverdue ? .red : .secondary)
            }
        }
        .widgetURL(URL(string: "dequeue://task/\(task.id)"))
    }
}

// MARK: - Priority Dot

struct PriorityDot: View {
    let priority: Int

    private var color: Color {
        switch priority {
        case 3: return .red
        case 2: return .orange
        case 1: return .blue
        default: return .gray
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
    }
}

// MARK: - Previews

#Preview("Medium", as: .systemMedium) {
    UpNextWidget()
} timeline: {
    UpNextEntry(
        date: .now,
        data: WidgetUpNextData(
            upcomingTasks: [
                WidgetTaskItem(
                    id: "1", title: "Review PR #314",
                    stackTitle: "Sprint Tasks", stackId: "s1",
                    dueDate: Calendar.current.date(byAdding: .hour, value: -1, to: Date()),
                    priority: 3, isOverdue: true
                ),
                WidgetTaskItem(
                    id: "2", title: "Deploy API changes",
                    stackTitle: "DevOps", stackId: "s2",
                    dueDate: Calendar.current.date(byAdding: .hour, value: 2, to: Date()),
                    priority: 2, isOverdue: false
                ),
                WidgetTaskItem(
                    id: "3", title: "Write documentation",
                    stackTitle: "Docs", stackId: "s3",
                    dueDate: Calendar.current.date(byAdding: .day, value: 1, to: Date()),
                    priority: nil, isOverdue: false
                )
            ],
            overdueCount: 1
        )
    )
}

#Preview("Large", as: .systemLarge) {
    UpNextWidget()
} timeline: {
    UpNextEntry(
        date: .now,
        data: WidgetUpNextData(
            upcomingTasks: [
                WidgetTaskItem(
                    id: "1", title: "Morning standup",
                    stackTitle: "Daily", stackId: "s1",
                    dueDate: Calendar.current.date(byAdding: .hour, value: 1, to: Date()),
                    priority: nil, isOverdue: false
                ),
                WidgetTaskItem(
                    id: "2", title: "Review database migration",
                    stackTitle: "Backend", stackId: "s2",
                    dueDate: Calendar.current.date(byAdding: .hour, value: 3, to: Date()),
                    priority: 3, isOverdue: false
                ),
                WidgetTaskItem(
                    id: "3", title: "Update API docs",
                    stackTitle: "Documentation", stackId: "s3",
                    dueDate: Calendar.current.date(byAdding: .day, value: 1, to: Date()),
                    priority: 2, isOverdue: false
                ),
                WidgetTaskItem(
                    id: "4", title: "Fix lint warnings",
                    stackTitle: "Code Quality", stackId: "s4",
                    dueDate: Calendar.current.date(byAdding: .day, value: 2, to: Date()),
                    priority: 1, isOverdue: false
                )
            ],
            overdueCount: 0
        )
    )
}
