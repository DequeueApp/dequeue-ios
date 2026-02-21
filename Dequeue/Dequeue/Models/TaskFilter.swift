//
//  TaskFilter.swift
//  Dequeue
//
//  Defines filter and sort criteria for tasks, with preset support.
//

import Foundation

// MARK: - Task Sort Option

enum TaskSortOption: String, Codable, CaseIterable, Identifiable, Sendable {
    case dueDate = "dueDate"
    case priority = "priority"
    case title = "title"
    case createdAt = "createdAt"
    case updatedAt = "updatedAt"
    case sortOrder = "sortOrder"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dueDate: return "Due Date"
        case .priority: return "Priority"
        case .title: return "Title"
        case .createdAt: return "Created"
        case .updatedAt: return "Last Updated"
        case .sortOrder: return "Manual Order"
        }
    }

    var icon: String {
        switch self {
        case .dueDate: return "calendar"
        case .priority: return "flag.fill"
        case .title: return "textformat"
        case .createdAt: return "clock"
        case .updatedAt: return "arrow.clockwise"
        case .sortOrder: return "list.number"
        }
    }
}

// MARK: - Date Range Filter

enum DateRangeFilter: String, Codable, CaseIterable, Identifiable, Sendable {
    case any = "any"
    case overdue = "overdue"
    case today = "today"
    case tomorrow = "tomorrow"
    case thisWeek = "thisWeek"
    case nextWeek = "nextWeek"
    case thisMonth = "thisMonth"
    case noDueDate = "noDueDate"
    case custom = "custom"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .any: return "Any Time"
        case .overdue: return "Overdue"
        case .today: return "Today"
        case .tomorrow: return "Tomorrow"
        case .thisWeek: return "This Week"
        case .nextWeek: return "Next Week"
        case .thisMonth: return "This Month"
        case .noDueDate: return "No Due Date"
        case .custom: return "Custom Range"
        }
    }

    var icon: String {
        switch self {
        case .any: return "infinity"
        case .overdue: return "exclamationmark.circle"
        case .today: return "sun.max"
        case .tomorrow: return "sunrise"
        case .thisWeek: return "calendar"
        case .nextWeek: return "calendar.badge.plus"
        case .thisMonth: return "calendar.circle"
        case .noDueDate: return "calendar.badge.minus"
        case .custom: return "calendar.badge.clock"
        }
    }

    /// Returns the date range for this filter option
    func dateRange(from referenceDate: Date = Date()) -> (start: Date?, end: Date?) {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: referenceDate)

        switch self {
        case .any:
            return (nil, nil)
        case .overdue:
            return (nil, startOfToday)
        case .today:
            let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday)
            return (startOfToday, endOfToday)
        case .tomorrow:
            let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)
            let endOfTomorrow = calendar.date(byAdding: .day, value: 2, to: startOfToday)
            return (startOfTomorrow, endOfTomorrow)
        case .thisWeek:
            let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfToday)
            return (startOfToday, endOfWeek)
        case .nextWeek:
            let startOfNext = calendar.date(byAdding: .day, value: 7, to: startOfToday)
            let endOfNext = calendar.date(byAdding: .day, value: 14, to: startOfToday)
            return (startOfNext, endOfNext)
        case .thisMonth:
            let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfToday)
            return (startOfToday, endOfMonth)
        case .noDueDate:
            return (nil, nil) // Special: filter for nil dueTime
        case .custom:
            return (nil, nil) // Handled separately with custom dates
        }
    }
}

// MARK: - Priority Filter

enum PriorityFilter: Int, Codable, CaseIterable, Identifiable, Sendable {
    case any = -1
    case none = 0
    case low = 1
    case medium = 2
    case high = 3

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .any: return "Any"
        case .none: return "None"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    var color: String {
        switch self {
        case .any: return "gray"
        case .none: return "gray"
        case .low: return "blue"
        case .medium: return "orange"
        case .high: return "red"
        }
    }
}

// MARK: - Status Filter

enum StatusFilter: String, Codable, CaseIterable, Identifiable, Sendable {
    case any = "any"
    case pending = "pending"
    case completed = "completed"
    case blocked = "blocked"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .any: return "Any"
        case .pending: return "Active"
        case .completed: return "Completed"
        case .blocked: return "Blocked"
        }
    }
}

// MARK: - Task Filter

/// Complete filter + sort configuration for tasks
struct TaskFilter: Codable, Equatable, Sendable {
    var searchText: String = ""
    var statusFilter: StatusFilter = .any
    var priorityFilter: PriorityFilter = .any
    var dateRangeFilter: DateRangeFilter = .any
    var customStartDate: Date?
    var customEndDate: Date?
    var selectedTagIds: Set<String> = []
    var selectedStackIds: Set<String> = []
    var sortBy: TaskSortOption = .sortOrder
    var sortAscending: Bool = true
    var showOnlyWithDueDate: Bool = false

    /// Whether any filter is active (not default)
    var isActive: Bool {
        !searchText.isEmpty ||
        statusFilter != .any ||
        priorityFilter != .any ||
        dateRangeFilter != .any ||
        !selectedTagIds.isEmpty ||
        !selectedStackIds.isEmpty ||
        showOnlyWithDueDate
    }

    /// Number of active filters
    var activeFilterCount: Int {
        var count = 0
        if !searchText.isEmpty { count += 1 }
        if statusFilter != .any { count += 1 }
        if priorityFilter != .any { count += 1 }
        if dateRangeFilter != .any { count += 1 }
        if !selectedTagIds.isEmpty { count += 1 }
        if !selectedStackIds.isEmpty { count += 1 }
        if showOnlyWithDueDate { count += 1 }
        return count
    }

    /// Resets all filters to defaults
    mutating func reset() {
        searchText = ""
        statusFilter = .any
        priorityFilter = .any
        dateRangeFilter = .any
        customStartDate = nil
        customEndDate = nil
        selectedTagIds = []
        selectedStackIds = []
        sortBy = .sortOrder
        sortAscending = true
        showOnlyWithDueDate = false
    }

    static let `default` = TaskFilter()
}

// MARK: - Filter Preset

/// A saved filter configuration
struct FilterPreset: Codable, Identifiable, Sendable {
    let id: String
    var name: String
    var icon: String
    var filter: TaskFilter

    init(id: String = UUID().uuidString, name: String, icon: String = "line.3.horizontal.decrease.circle", filter: TaskFilter) {
        self.id = id
        self.name = name
        self.icon = icon
        self.filter = filter
    }

    /// Built-in presets
    static let builtInPresets: [FilterPreset] = [
        FilterPreset(
            name: "Overdue",
            icon: "exclamationmark.circle.fill",
            filter: {
                var f = TaskFilter()
                f.dateRangeFilter = .overdue
                f.statusFilter = .pending
                return f
            }()
        ),
        FilterPreset(
            name: "Due Today",
            icon: "sun.max.fill",
            filter: {
                var f = TaskFilter()
                f.dateRangeFilter = .today
                f.statusFilter = .pending
                return f
            }()
        ),
        FilterPreset(
            name: "High Priority",
            icon: "flag.fill",
            filter: {
                var f = TaskFilter()
                f.priorityFilter = .high
                f.statusFilter = .pending
                return f
            }()
        ),
        FilterPreset(
            name: "Blocked",
            icon: "hand.raised.fill",
            filter: {
                var f = TaskFilter()
                f.statusFilter = .blocked
                return f
            }()
        ),
        FilterPreset(
            name: "Recently Updated",
            icon: "arrow.clockwise",
            filter: {
                var f = TaskFilter()
                f.sortBy = .updatedAt
                f.sortAscending = false
                return f
            }()
        ),
    ]
}
