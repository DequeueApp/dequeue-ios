//
//  TaskActivityLogView.swift
//  Dequeue
//
//  Timeline view showing the history of changes to a task.
//

import SwiftUI

// MARK: - Activity Log View

struct TaskActivityLogView: View {
    let taskId: String
    @State private var groupedActivities: [(date: String, activities: [TaskActivity])] = []
    @State private var isLoading = true
    private let activityService: TaskActivityService

    init(taskId: String, userDefaults: UserDefaults = .standard) {
        self.taskId = taskId
        self.activityService = TaskActivityService(userDefaults: userDefaults)
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if groupedActivities.isEmpty {
                emptyState
            } else {
                activityList
            }
        }
        .navigationTitle("Activity")
        .onAppear {
            loadActivities()
        }
    }

    private var activityList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(groupedActivities, id: \.date) { group in
                    Section {
                        ForEach(group.activities) { activity in
                            ActivityRow(activity: activity)
                        }
                    } header: {
                        Text(group.date)
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No Activity Yet")
                .font(.headline)
            Text("Changes to this task will appear here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    private func loadActivities() {
        groupedActivities = activityService.getGroupedActivities(for: taskId)
        isLoading = false
    }
}

// MARK: - Activity Row

private struct ActivityRow: View {
    let activity: TaskActivity

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Timeline connector
            VStack(spacing: 0) {
                Circle()
                    .fill(activityColor)
                    .frame(width: 8, height: 8)
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 1)
            }
            .frame(width: 8)

            // Icon
            Image(systemName: activity.type.icon)
                .font(.caption)
                .foregroundStyle(activityColor)
                .frame(width: 20, height: 20)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(activity.summary)
                    .font(.subheadline)

                // Show value change if available
                if let prev = activity.previousValue, let new = activity.newValue {
                    HStack(spacing: 4) {
                        Text(prev)
                            .strikethrough()
                            .foregroundStyle(.red.opacity(0.7))
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(new)
                            .foregroundStyle(.green)
                    }
                    .font(.caption)
                }

                Text(activity.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var activityColor: Color {
        switch activity.type.color {
        case "green": return .green
        case "red": return .red
        case "orange": return .orange
        case "blue": return .blue
        case "teal": return .teal
        default: return .secondary
        }
    }
}

// MARK: - Compact Activity Summary

/// Shows last few activities inline (for task detail view)
struct TaskActivitySummary: View {
    let taskId: String
    @State private var recentActivities: [TaskActivity] = []
    private let activityService: TaskActivityService

    init(taskId: String, userDefaults: UserDefaults = .standard) {
        self.taskId = taskId
        self.activityService = TaskActivityService(userDefaults: userDefaults)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if recentActivities.isEmpty {
                Text("No recent activity")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(recentActivities.prefix(3)) { activity in
                    HStack(spacing: 6) {
                        Image(systemName: activity.type.icon)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(activity.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(activity.timestamp, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .onAppear {
            recentActivities = activityService.getActivities(for: taskId)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        TaskActivityLogView(taskId: "preview-task")
    }
}
