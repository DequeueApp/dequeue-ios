//
//  AnalyticsDashboardView.swift
//  Dequeue
//
//  Productivity dashboard with charts and metrics.
//

import SwiftUI
import SwiftData

// MARK: - Dashboard View

struct AnalyticsDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var summary: ProductivitySummary?
    @State private var dailyData: [DailyCompletionData] = []
    @State private var tagData: [TagAnalytics] = []
    @State private var stackData: [StackAnalytics] = []
    @State private var hourlyData: [HourlyProductivity] = []
    @State private var avgTimeToComplete: Double?
    @State private var currentStreak: Int = 0
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if isLoading {
                    ProgressView()
                        .padding(.top, 40)
                } else {
                    // Summary Cards
                    if let summary {
                        summaryCards(summary)
                    }

                    // Quick Stats Row
                    quickStatsRow

                    // Daily Chart
                    dailyCompletionChart

                    // Tag Breakdown
                    if !tagData.isEmpty {
                        tagBreakdown
                    }

                    // Stack Breakdown
                    if !stackData.isEmpty {
                        stackBreakdown
                    }

                    // Hourly Distribution
                    hourlyDistribution
                }
            }
            .padding()
        }
        .navigationTitle("Analytics")
        .onAppear { loadData() }
        .refreshable { loadData() }
    }

    // MARK: - Summary Cards

    @ViewBuilder
    private func summaryCards(_ summary: ProductivitySummary) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            MetricCard(
                title: "Completion Rate",
                value: "\(summary.completionPercentage)%",
                icon: "chart.pie.fill",
                color: summary.completionRate > 0.7 ? .green : summary.completionRate > 0.4 ? .orange : .red
            )
            MetricCard(
                title: "Total Tasks",
                value: "\(summary.totalTasks)",
                icon: "list.bullet",
                color: .blue
            )
            MetricCard(
                title: "Completed",
                value: "\(summary.completedTasks)",
                icon: "checkmark.circle.fill",
                color: .green
            )
            MetricCard(
                title: "Overdue",
                value: "\(summary.overdueTasks)",
                icon: "exclamationmark.triangle.fill",
                color: summary.overdueTasks > 0 ? .red : .green
            )
        }
    }

    // MARK: - Quick Stats

    @ViewBuilder
    private var quickStatsRow: some View {
        HStack(spacing: 16) {
            QuickStat(
                label: "Streak",
                value: "\(currentStreak)d",
                icon: "flame.fill",
                color: .orange
            )

            if let avg = avgTimeToComplete {
                QuickStat(
                    label: "Avg. Completion",
                    value: String(format: "%.1fd", avg),
                    icon: "clock.fill",
                    color: .purple
                )
            }

            QuickStat(
                label: "Pending",
                value: "\(summary?.pendingTasks ?? 0)",
                icon: "hourglass",
                color: .blue
            )
        }
    }

    // MARK: - Daily Chart

    @ViewBuilder
    private var dailyCompletionChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Daily Activity")
                .font(.headline)

            // Simple bar chart
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(dailyData) { day in
                    VStack(spacing: 4) {
                        // Completed bar
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.green)
                            .frame(
                                width: barWidth,
                                height: max(2, CGFloat(day.completed) * barScale)
                            )

                        // Day label
                        Text(day.dayLabel)
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 120)
            .frame(maxWidth: .infinity)

            HStack {
                Circle().fill(.green).frame(width: 8, height: 8)
                Text("Completed").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.background))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    private var barWidth: CGFloat { 16 }

    private var barScale: CGFloat {
        let maxVal = dailyData.map(\.completed).max() ?? 1
        guard maxVal > 0 else { return 1 }
        return 80.0 / CGFloat(maxVal)
    }

    // MARK: - Tag Breakdown

    @ViewBuilder
    private var tagBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("By Tag")
                .font(.headline)

            ForEach(tagData.prefix(8)) { tag in
                HStack {
                    Text(tag.tag)
                        .font(.subheadline)
                    Spacer()
                    Text("\(tag.completedTasks)/\(tag.totalTasks)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(.secondary.opacity(0.15))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(.blue)
                                .frame(width: geometry.size.width * tag.completionRate)
                        }
                    }
                    .frame(width: 60, height: 6)
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.background))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    // MARK: - Stack Breakdown

    @ViewBuilder
    private var stackBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("By Stack")
                .font(.headline)

            ForEach(stackData.prefix(6)) { stack in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(stack.stackTitle)
                            .font(.subheadline)
                        Spacer()
                        Text("\(stack.completedTasks)/\(stack.totalTasks)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(.secondary.opacity(0.15))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(.green)
                                .frame(width: geometry.size.width * stack.completionRate)
                        }
                    }
                    .frame(height: 6)

                    if let avg = stack.avgCompletionDays {
                        Text("Avg: \(String(format: "%.1f", avg)) days")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.background))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    // MARK: - Hourly Distribution

    @ViewBuilder
    private var hourlyDistribution: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Productive Hours")
                .font(.headline)

            // Simple hourly bar chart
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(hourlyData) { hour in
                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(hourColor(hour))
                            .frame(width: 10, height: max(2, CGFloat(hour.completions) * hourScale))

                        if hour.hour % 6 == 0 {
                            Text(hour.label)
                                .font(.system(size: 7))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(height: 80)
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.background))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    private var hourScale: CGFloat {
        let maxVal = hourlyData.map(\.completions).max() ?? 1
        guard maxVal > 0 else { return 1 }
        return 60.0 / CGFloat(maxVal)
    }

    private func hourColor(_ hour: HourlyProductivity) -> Color {
        let maxVal = hourlyData.map(\.completions).max() ?? 1
        guard maxVal > 0 else { return .secondary.opacity(0.3) }
        let intensity = Double(hour.completions) / Double(maxVal)
        return Color.blue.opacity(0.3 + intensity * 0.7)
    }

    // MARK: - Data Loading

    private func loadData() {
        isLoading = true
        let service = AnalyticsService(modelContext: modelContext)

        summary = service.getProductivitySummary()
        dailyData = service.getDailyCompletions(days: 14)
        tagData = service.getTagAnalytics()
        stackData = service.getStackAnalytics()
        hourlyData = service.getHourlyProductivity()
        avgTimeToComplete = service.averageTimeToComplete()
        currentStreak = service.getCurrentStreak()

        isLoading = false
    }
}

// MARK: - Metric Card

private struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.title.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(.background))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

// MARK: - Quick Stat

private struct QuickStat: View {
    let label: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Text(value)
                    .font(.subheadline.bold())
            }
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(.secondary.opacity(0.1)))
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        AnalyticsDashboardView()
    }
    .modelContainer(for: [QueueTask.self, Stack.self])
}
