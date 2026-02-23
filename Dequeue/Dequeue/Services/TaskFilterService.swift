//
//  TaskFilterService.swift
//  Dequeue
//
//  Applies TaskFilter criteria to task arrays with sorting.
//

import Foundation
import SwiftData
import os

private let logger = Logger(subsystem: "com.dequeue", category: "TaskFilter")

@MainActor
final class TaskFilterService {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Apply Filter

    /// Applies filter and sort to a list of tasks
    func apply(filter: TaskFilter, to tasks: [QueueTask]) -> [QueueTask] {
        var result = tasks

        // Status filter
        result = applyStatusFilter(filter.statusFilter, to: result)

        // Priority filter
        result = applyPriorityFilter(filter.priorityFilter, to: result)

        // Date range filter
        result = applyDateRangeFilter(filter, to: result)

        // Tag filter
        if !filter.selectedTagIds.isEmpty {
            result = result.filter { task in
                !Set(task.tags).isDisjoint(with: filter.selectedTagIds)
            }
        }

        // Stack filter
        if !filter.selectedStackIds.isEmpty {
            result = result.filter { task in
                guard let stackId = task.stack?.id else { return false }
                return filter.selectedStackIds.contains(stackId)
            }
        }

        // Only with due date
        if filter.showOnlyWithDueDate {
            result = result.filter { $0.dueTime != nil }
        }

        // Search text
        if !filter.searchText.isEmpty {
            let query = filter.searchText.lowercased()
            result = result.filter { task in
                task.title.lowercased().contains(query) ||
                (task.taskDescription?.lowercased().contains(query) ?? false) ||
                task.tags.contains { $0.lowercased().contains(query) }
            }
        }

        // Sort
        result = applySorting(filter.sortBy, ascending: filter.sortAscending, to: result)

        return result
    }

    // MARK: - Fetch & Filter

    /// Fetches all non-deleted tasks and applies filter
    func fetchFiltered(filter: TaskFilter) -> [QueueTask] {
        let predicate = #Predicate<QueueTask> { task in
            task.isDeleted == false
        }
        let descriptor = FetchDescriptor<QueueTask>(predicate: predicate)

        do {
            let allTasks = try modelContext.fetch(descriptor)
            return apply(filter: filter, to: allTasks)
        } catch {
            logger.error("Failed to fetch tasks for filtering: \(error)")
            return []
        }
    }

    // MARK: - Private Helpers

    private func applyStatusFilter(_ status: StatusFilter, to tasks: [QueueTask]) -> [QueueTask] {
        switch status {
        case .any:
            return tasks
        case .pending:
            return tasks.filter { $0.status == .pending }
        case .completed:
            return tasks.filter { $0.status == .completed }
        case .blocked:
            return tasks.filter { $0.status == .blocked }
        }
    }

    private func applyPriorityFilter(_ priority: PriorityFilter, to tasks: [QueueTask]) -> [QueueTask] {
        switch priority {
        case .any:
            return tasks
        default:
            return tasks.filter { ($0.priority ?? 0) == priority.rawValue }
        }
    }

    private func applyDateRangeFilter(_ filter: TaskFilter, to tasks: [QueueTask]) -> [QueueTask] {
        switch filter.dateRangeFilter {
        case .any:
            return tasks
        case .noDueDate:
            return tasks.filter { $0.dueTime == nil }
        case .custom:
            return tasks.filter { task in
                guard let due = task.dueTime else { return false }
                let afterStart = filter.customStartDate.map { due >= $0 } ?? true
                let beforeEnd = filter.customEndDate.map { due < $0 } ?? true
                return afterStart && beforeEnd
            }
        default:
            let range = filter.dateRangeFilter.dateRange()
            return tasks.filter { task in
                guard let due = task.dueTime else { return false }
                let afterStart = range.start.map { due >= $0 } ?? true
                let beforeEnd = range.end.map { due < $0 } ?? true
                return afterStart && beforeEnd
            }
        }
    }

    private func applySorting(_ sortBy: TaskSortOption, ascending: Bool, to tasks: [QueueTask]) -> [QueueTask] {
        tasks.sorted { lhs, rhs in
            let result: Bool
            switch sortBy {
            case .dueDate:
                let lhsDate = lhs.dueTime ?? (ascending ? Date.distantFuture : Date.distantPast)
                let rhsDate = rhs.dueTime ?? (ascending ? Date.distantFuture : Date.distantPast)
                result = lhsDate < rhsDate
            case .priority:
                result = (lhs.priority ?? 0) < (rhs.priority ?? 0)
            case .title:
                result = lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            case .createdAt:
                result = lhs.createdAt < rhs.createdAt
            case .updatedAt:
                result = lhs.updatedAt < rhs.updatedAt
            case .sortOrder:
                result = lhs.sortOrder < rhs.sortOrder
            }
            return ascending ? result : !result
        }
    }

    // MARK: - Preset Management

    private static let presetsKey = "savedFilterPresets"

    /// Loads saved filter presets from UserDefaults
    func loadPresets(from userDefaults: UserDefaults = .standard) -> [FilterPreset] {
        guard let data = userDefaults.data(forKey: Self.presetsKey),
              let presets = try? JSONDecoder().decode([FilterPreset].self, from: data) else {
            return []
        }
        return presets
    }

    /// Saves filter presets to UserDefaults
    func savePresets(_ presets: [FilterPreset], to userDefaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(presets) {
            userDefaults.set(data, forKey: Self.presetsKey)
        }
    }

    /// Adds a new preset
    func addPreset(
        name: String,
        icon: String = "line.3.horizontal.decrease.circle",
        filter: TaskFilter,
        userDefaults: UserDefaults = .standard
    ) -> FilterPreset {
        var presets = loadPresets(from: userDefaults)
        let preset = FilterPreset(name: name, icon: icon, filter: filter)
        presets.append(preset)
        savePresets(presets, to: userDefaults)
        return preset
    }

    /// Removes a preset by ID
    func removePreset(id: String, userDefaults: UserDefaults = .standard) {
        var presets = loadPresets(from: userDefaults)
        presets.removeAll { $0.id == id }
        savePresets(presets, to: userDefaults)
    }
}
