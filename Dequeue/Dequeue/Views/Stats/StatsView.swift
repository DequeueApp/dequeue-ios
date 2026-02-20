//
//  StatsView.swift
//  Dequeue
//
//  Task statistics dashboard
//

import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.dequeue", category: "StatsView")

struct StatsView: View {
    @Environment(\.statsService) private var statsService
    @State private var stats: StatsResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && stats == nil {
                    loadingView
                } else if let stats {
                    statsContent(stats)
                } else if let errorMessage {
                    errorView(errorMessage)
                } else {
                    loadingView
                }
            }
            .navigationTitle("Statistics")
            .refreshable {
                await loadStats()
            }
            .task {
                await loadStats()
            }
        }
    }

    // MARK: - Loading & Error

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading statistics...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Unable to Load", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") {
                Task { await loadStats() }
            }
        }
    }

    // MARK: - Stats Content

    private func statsContent(_ stats: StatsResponse) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Overview cards
                overviewSection(stats)

                // Productivity section
                productivitySection(stats)

                // Priority breakdown
                prioritySection(stats.priority)

                // Stacks & Arcs section
                stacksSection(stats.stacks)
            }
            .padding()
        }
    }

    // MARK: - Overview Section

    private func overviewSection(_ stats: StatsResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overview")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                StatCard(
                    title: "Total Tasks",
                    value: "\(stats.tasks.total)",
                    icon: "list.bullet",
                    color: .blue
                )
                StatCard(
                    title: "Active",
                    value: "\(stats.tasks.active)",
                    icon: "bolt.fill",
                    color: .green
                )
                StatCard(
                    title: "Completed",
                    value: "\(stats.tasks.completed)",
                    icon: "checkmark.circle.fill",
                    color: .mint
                )
                StatCard(
                    title: "Overdue",
                    value: "\(stats.tasks.overdue)",
                    icon: "exclamationmark.triangle.fill",
                    color: stats.tasks.overdue > 0 ? .red : .gray
                )
            }
        }
    }

    // MARK: - Productivity Section

    private func productivitySection(_ stats: StatsResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Productivity")
                .font(.headline)

            VStack(spacing: 8) {
                // Completion rate
                HStack {
                    Text("Completion Rate")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(stats.tasks.completionRate * 100))%")
                        .font(.headline)
                        .foregroundStyle(.mint)
                }
                ProgressView(value: stats.tasks.completionRate)
                    .tint(.mint)
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Streak
            if stats.completionStreak > 0 {
                HStack {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.orange)
                    Text("\(stats.completionStreak)-day streak")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // Today & This Week
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Created")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("\(stats.tasks.createdToday)")
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("Completed")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("\(stats.tasks.completedToday)")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundStyle(.green)
                        }
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text("This Week")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Created")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("\(stats.tasks.createdThisWeek)")
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("Completed")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("\(stats.tasks.completedThisWeek)")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundStyle(.green)
                        }
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    // MARK: - Priority Section

    private func prioritySection(_ priority: PriorityBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Priority Breakdown")
                .font(.headline)

            VStack(spacing: 8) {
                PriorityRow(label: "High", count: priority.high, total: priority.total, color: .red)
                PriorityRow(label: "Medium", count: priority.medium, total: priority.total, color: .orange)
                PriorityRow(label: "Low", count: priority.low, total: priority.total, color: .blue)
                PriorityRow(label: "None", count: priority.none, total: priority.total, color: .gray)
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Stacks Section

    private func stacksSection(_ stacks: StackStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Stacks & Arcs")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                StatCard(
                    title: "Stacks",
                    value: "\(stacks.total)",
                    icon: "square.stack.3d.up",
                    color: .purple
                )
                StatCard(
                    title: "Active",
                    value: "\(stacks.active)",
                    icon: "bolt.fill",
                    color: .green
                )
                StatCard(
                    title: "Arcs",
                    value: "\(stacks.totalArcs)",
                    icon: "rays",
                    color: .indigo
                )
            }
        }
    }

    // MARK: - Data Loading

    @MainActor
    private func loadStats() async {
        guard let statsService else {
            errorMessage = "Statistics are not available."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            stats = try await statsService.getStats()
        } catch {
            logger.error("Failed to load stats: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

// MARK: - Stat Card

struct StatCard: View {
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
                .font(.title2)
                .fontWeight(.bold)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Priority Row

struct PriorityRow: View {
    let label: String
    let count: Int
    let total: Int
    let color: Color

    private var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(count) / Double(total)
    }

    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.subheadline)
            Spacer()
            Text("\(count)")
                .font(.subheadline)
                .fontWeight(.medium)
            ProgressView(value: fraction)
                .frame(maxWidth: 60)
                .tint(color)
        }
    }
}

#Preview {
    StatsView()
}
