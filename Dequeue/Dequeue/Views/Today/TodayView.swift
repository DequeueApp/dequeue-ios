//
//  TodayView.swift
//  Dequeue
//
//  Unified view of today's tasks across all stacks, with sections for
//  overdue, today, and upcoming tasks.
//

import SwiftUI
import SwiftData
import os

private let logger = Logger(subsystem: "com.dequeue", category: "TodayView")

// MARK: - Today Section

/// Represents a logical section in the Today view
enum TodaySection: Identifiable, CaseIterable {
    case overdue
    case today
    case tomorrow
    case thisWeek

    var id: String { title }

    var title: String {
        switch self {
        case .overdue: return "Overdue"
        case .today: return "Today"
        case .tomorrow: return "Tomorrow"
        case .thisWeek: return "This Week"
        }
    }

    var icon: String {
        switch self {
        case .overdue: return "exclamationmark.circle.fill"
        case .today: return "sun.max.fill"
        case .tomorrow: return "sunrise.fill"
        case .thisWeek: return "calendar"
        }
    }

    var tintColor: Color {
        switch self {
        case .overdue: return .red
        case .today: return .blue
        case .tomorrow: return .orange
        case .thisWeek: return .purple
        }
    }
}

// MARK: - Today View Model

@MainActor
@Observable
final class TodayViewModel {
    var overdueTasks: [QueueTask] = []
    var todayTasks: [QueueTask] = []
    var tomorrowTasks: [QueueTask] = []
    var thisWeekTasks: [QueueTask] = []
    var isLoading = false

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    var totalTaskCount: Int {
        overdueTasks.count + todayTasks.count + tomorrowTasks.count + thisWeekTasks.count
    }

    var completedTodayCount: Int {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())

        let predicate = #Predicate<QueueTask> { task in
            task.isDeleted == false
        }
        let descriptor = FetchDescriptor<QueueTask>(predicate: predicate)

        do {
            return try modelContext.fetch(descriptor)
                .filter { task in
                    task.status == .completed &&
                    task.updatedAt >= startOfDay
                }
                .count
        } catch {
            return 0
        }
    }

    func refresh() {
        isLoading = true
        defer { isLoading = false }

        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        guard let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday),
              let startOfDayAfterTomorrow = calendar.date(byAdding: .day, value: 2, to: startOfToday),
              let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfToday) else {
            return
        }

        let predicate = #Predicate<QueueTask> { task in
            task.isDeleted == false &&
            task.dueTime != nil
        }
        let descriptor = FetchDescriptor<QueueTask>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.dueTime)]
        )

        do {
            let allTasks = try modelContext.fetch(descriptor)
                .filter { $0.status != .completed }

            overdueTasks = allTasks.filter { task in
                guard let due = task.dueTime else { return false }
                return due < startOfToday
            }

            todayTasks = allTasks.filter { task in
                guard let due = task.dueTime else { return false }
                return due >= startOfToday && due < startOfTomorrow
            }

            tomorrowTasks = allTasks.filter { task in
                guard let due = task.dueTime else { return false }
                return due >= startOfTomorrow && due < startOfDayAfterTomorrow
            }

            thisWeekTasks = allTasks.filter { task in
                guard let due = task.dueTime else { return false }
                return due >= startOfDayAfterTomorrow && due < endOfWeek
            }
        } catch {
            logger.error("Failed to fetch tasks: \(error)")
        }
    }
}

// MARK: - Today View

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: TodayViewModel?

    var body: some View {
        Group {
            if let vm = viewModel {
                TodayContentView(viewModel: vm)
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if viewModel == nil {
                let vm = TodayViewModel(modelContext: modelContext)
                vm.refresh()
                viewModel = vm
            }
        }
    }
}

// MARK: - Today Content View

private struct TodayContentView: View {
    @Bindable var viewModel: TodayViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Summary Header
                TodaySummaryHeader(
                    totalTasks: viewModel.totalTaskCount,
                    completedToday: viewModel.completedTodayCount,
                    overdueCount: viewModel.overdueTasks.count
                )
                .padding(.horizontal)

                // Sections
                if viewModel.totalTaskCount == 0 {
                    EmptyTodayView()
                        .padding(.top, 40)
                } else {
                    LazyVStack(spacing: 12, pinnedViews: .sectionHeaders) {
                        if !viewModel.overdueTasks.isEmpty {
                            TodaySectionView(
                                section: .overdue,
                                tasks: viewModel.overdueTasks,
                                onRefresh: { viewModel.refresh() }
                            )
                        }

                        if !viewModel.todayTasks.isEmpty {
                            TodaySectionView(
                                section: .today,
                                tasks: viewModel.todayTasks,
                                onRefresh: { viewModel.refresh() }
                            )
                        }

                        if !viewModel.tomorrowTasks.isEmpty {
                            TodaySectionView(
                                section: .tomorrow,
                                tasks: viewModel.tomorrowTasks,
                                onRefresh: { viewModel.refresh() }
                            )
                        }

                        if !viewModel.thisWeekTasks.isEmpty {
                            TodaySectionView(
                                section: .thisWeek,
                                tasks: viewModel.thisWeekTasks,
                                onRefresh: { viewModel.refresh() }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Today")
        .refreshable {
            viewModel.refresh()
        }
    }
}

// MARK: - Summary Header

struct TodaySummaryHeader: View {
    let totalTasks: Int
    let completedToday: Int
    let overdueCount: Int

    var body: some View {
        HStack(spacing: 16) {
            SummaryPill(
                value: "\(totalTasks)",
                label: "Due",
                color: .blue
            )

            SummaryPill(
                value: "\(completedToday)",
                label: "Done",
                color: .green
            )

            if overdueCount > 0 {
                SummaryPill(
                    value: "\(overdueCount)",
                    label: "Overdue",
                    color: .red
                )
            }
        }
    }
}

// MARK: - Summary Pill

private struct SummaryPill: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Section View

private struct TodaySectionView: View {
    let section: TodaySection
    let tasks: [QueueTask]
    let onRefresh: () -> Void

    var body: some View {
        Section {
            ForEach(tasks) { task in
                TodayTaskRow(task: task, section: section, onComplete: onRefresh)
            }
        } header: {
            HStack(spacing: 8) {
                Image(systemName: section.icon)
                    .foregroundStyle(section.tintColor)
                Text(section.title)
                    .font(.headline)
                Spacer()
                Text("\(tasks.count)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.15), in: Capsule())
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
        }
    }
}

// MARK: - Task Row

private struct TodayTaskRow: View {
    let task: QueueTask
    let section: TodaySection
    let onComplete: () -> Void

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HStack(spacing: 12) {
            // Priority indicator
            Circle()
                .fill(priorityColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    if let stackTitle = task.stack?.title {
                        Label(stackTitle, systemImage: "tray.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if let dueTime = task.dueTime {
                        Label(
                            dueTime.formatted(date: section == .today ? .omitted : .abbreviated, time: .shortened),
                            systemImage: "clock"
                        )
                        .font(.caption2)
                        .foregroundStyle(section == .overdue ? .red : .secondary)
                    }
                }
            }

            Spacer()

            // Complete button
            Button {
                completeTask()
            } label: {
                Image(systemName: "checkmark.circle")
                    .font(.title3)
                    .foregroundStyle(.green)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.background)
                .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        )
    }

    private var priorityColor: Color {
        switch task.priority {
        case 3: return .red
        case 2: return .orange
        case 1: return .blue
        default: return .gray.opacity(0.3)
        }
    }

    private func completeTask() {
        task.status = .completed
        task.updatedAt = Date()
        try? modelContext.save()
        onComplete()
    }
}

// MARK: - Empty State

private struct EmptyTodayView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("All Clear!")
                .font(.title2.bold())

            Text("No tasks due today or this week.\nEnjoy your free time! 🎉")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        TodayView()
    }
    .modelContainer(for: [QueueTask.self, Stack.self])
}
