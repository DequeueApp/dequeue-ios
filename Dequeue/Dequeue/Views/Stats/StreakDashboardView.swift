//
//  StreakDashboardView.swift
//  Dequeue
//
//  Visual dashboard showing streaks, heatmap, and productivity metrics.
//

import SwiftUI

// MARK: - Streak Dashboard View

struct StreakDashboardView: View {
    @StateObject private var tracker = StreakTrackerService()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                streakCard
                weeklyActivity
                monthlyHeatmap
                statsGrid
                milestones
            }
            .padding()
        }
        .navigationTitle("Streaks")
        .overlay {
            if let milestone = tracker.recentMilestone {
                milestoneOverlay(milestone)
            }
        }
    }

    // MARK: - Streak Card

    private var streakCard: some View {
        VStack(spacing: 16) {
            // Current streak
            HStack(spacing: 8) {
                Text("🔥")
                    .font(.system(size: 44))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(tracker.streakInfo.currentStreak)")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                    Text("day streak")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Best: \(tracker.streakInfo.longestStreak)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    todayStatus
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(streakGradient)
            )
        }
    }

    private var streakGradient: some ShapeStyle {
        LinearGradient(
            colors: tracker.streakInfo.isTodayActive
                ? [Color.orange.opacity(0.15), Color.red.opacity(0.15)]
                : [Color.gray.opacity(0.1), Color.gray.opacity(0.05)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @ViewBuilder
    private var todayStatus: some View {
        if tracker.streakInfo.isTodayActive {
            Label("Today ✓", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        } else {
            let remaining = tracker.streakInfo.tasksRemainingForStreak
            Label("\(remaining) to go", systemImage: "flame")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    // MARK: - Weekly Activity

    private var weeklyActivity: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This Week")
                .font(.headline)

            HStack(spacing: 8) {
                ForEach(tracker.streakInfo.weekActivity) { day in
                    VStack(spacing: 6) {
                        // Activity bar
                        RoundedRectangle(cornerRadius: 4)
                            .fill(day.isActive ? Color.green : Color.secondary.opacity(0.2))
                            .frame(width: 36, height: CGFloat(max(8, min(60, day.tasksCompleted * 15))))
                            .animation(.spring(duration: 0.3), value: day.tasksCompleted)

                        // Day label
                        Text(shortDayName(for: day.date))
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        // Count
                        Text("\(day.tasksCompleted)")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(day.isActive ? .primary : .tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "This week's activity: \(tracker.streakInfo.weekActivity.filter(\.isActive).count) active days"
        )
    }

    // MARK: - Monthly Heatmap

    private var monthlyHeatmap: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Last 30 Days")
                .font(.headline)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 3), count: 7), spacing: 3) {
                ForEach(tracker.streakInfo.monthActivity) { day in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(heatmapColor(for: day.intensityLevel))
                        .aspectRatio(1, contentMode: .fit)
                        .accessibilityLabel("\(shortDateLabel(for: day.date)): \(day.tasksCompleted) tasks")
                }
            }

            // Legend
            HStack(spacing: 4) {
                Text("Less")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                ForEach(0..<5) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(heatmapColor(for: level))
                        .frame(width: 12, height: 12)
                }
                Text("More")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statCard(
                title: "Total Tasks",
                value: "\(tracker.streakInfo.totalTasksCompleted)",
                icon: "checkmark.circle",
                color: .green
            )
            statCard(
                title: "Active Days",
                value: "\(tracker.streakInfo.totalActiveDays)",
                icon: "calendar.badge.checkmark",
                color: .blue
            )
            statCard(
                title: "Today",
                value: "\(tracker.streakInfo.todayTasksCompleted)",
                icon: "star",
                color: .yellow
            )
            statCard(
                title: "Best Streak",
                value: "\(tracker.streakInfo.longestStreak) days",
                icon: "trophy",
                color: .orange
            )
        }
    }

    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - Milestones

    private var milestones: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Milestones")
                .font(.headline)

            ForEach(StreakMilestone.allCases, id: \.rawValue) { milestone in
                let achieved = tracker.streakInfo.longestStreak >= milestone.rawValue
                HStack(spacing: 12) {
                    Text(milestone.emoji)
                        .font(.title2)
                        .grayscale(achieved ? 0 : 1)
                        .opacity(achieved ? 1 : 0.4)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(milestone.title)
                            .fontWeight(achieved ? .semibold : .regular)
                            .foregroundStyle(achieved ? .primary : .secondary)
                        Text("\(milestone.rawValue) day streak")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if achieved {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Text("\(milestone.rawValue - tracker.streakInfo.longestStreak) to go")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }

    // MARK: - Milestone Overlay

    private func milestoneOverlay(_ milestone: StreakMilestone) -> some View {
        VStack(spacing: 16) {
            Text(milestone.emoji)
                .font(.system(size: 80))

            Text(milestone.title)
                .font(.title)
                .fontWeight(.bold)

            Text("\(milestone.rawValue) day streak!")
                .font(.headline)
                .foregroundStyle(.secondary)

            Button("Awesome!") {
                withAnimation {
                    tracker.dismissMilestone()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .transition(.opacity)
    }

    // MARK: - Helpers

    private func shortDayName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private func shortDateLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func heatmapColor(for level: Int) -> Color {
        switch level {
        case 0: return Color.secondary.opacity(0.1)
        case 1: return Color.green.opacity(0.3)
        case 2: return Color.green.opacity(0.5)
        case 3: return Color.green.opacity(0.7)
        default: return Color.green.opacity(0.9)
        }
    }
}

// MARK: - Compact Streak Badge (for embedding)

/// A small badge showing the current streak, for use in navigation bars or list rows.
struct StreakBadgeView: View {
    let currentStreak: Int
    let isActive: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text("🔥")
                .font(.caption)
            Text("\(currentStreak)")
                .font(.caption)
                .fontWeight(.bold)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(isActive ? Color.orange.opacity(0.15) : Color.secondary.opacity(0.1))
        )
        .accessibilityLabel("\(currentStreak) day streak\(isActive ? ", active today" : "")")
    }
}

// MARK: - Preview

#Preview("Streak Dashboard") {
    NavigationStack {
        StreakDashboardView()
    }
}

#Preview("Streak Badge") {
    StreakBadgeView(currentStreak: 7, isActive: true)
}
