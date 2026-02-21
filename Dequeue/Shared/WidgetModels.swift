//
//  WidgetModels.swift
//  Dequeue
//
//  Shared data models for widget data exchange between the main app and widget extension.
//  These are lightweight Codable structs — NOT SwiftData models — so they can be
//  serialized to App Group UserDefaults for the widget to read.
//
//  DEQ-120, DEQ-121
//

import Foundation

// MARK: - App Group Configuration

enum AppGroupConfig {
    /// App Group identifier shared between the main app and widget extension
    static let suiteName = "group.com.ardonos.Dequeue"

    /// UserDefaults key for the active stack widget data
    static let activeStackKey = "widget.activeStack"

    /// UserDefaults key for the up next widget data
    static let upNextKey = "widget.upNext"

    /// UserDefaults key for the stats widget data
    static let statsKey = "widget.stats"

    /// UserDefaults key for the last update timestamp
    static let lastUpdateKey = "widget.lastUpdate"

    /// Shared UserDefaults instance for the App Group
    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }
}

// MARK: - Active Stack Widget Data

/// Data for the Active Stack widget — shows the current focused stack and its top task
struct WidgetActiveStackData: Codable, Sendable {
    /// Name of the active stack
    let stackTitle: String

    /// ID of the active stack (for deep linking)
    let stackId: String

    /// The current/next task in this stack
    let activeTaskTitle: String?

    /// ID of the active task (for deep linking)
    let activeTaskId: String?

    /// Number of pending tasks remaining in this stack
    let pendingTaskCount: Int

    /// Total tasks in this stack (including completed)
    let totalTaskCount: Int

    /// Due date of the stack, if set
    let dueDate: Date?

    /// Priority level (nil = no priority, 1 = low, 2 = medium, 3 = high)
    let priority: Int?

    /// Tags on the active stack
    let tags: [String]
}

// MARK: - Up Next Widget Data

/// Data for the Up Next widget — shows upcoming tasks with due dates
struct WidgetUpNextData: Codable, Sendable {
    /// Ordered list of upcoming tasks (nearest due first)
    let upcomingTasks: [WidgetTaskItem]

    /// Total number of overdue tasks (for badge-style display)
    let overdueCount: Int
}

/// A single task item for the widget
struct WidgetTaskItem: Codable, Sendable, Identifiable {
    let id: String
    let title: String
    let stackTitle: String
    let stackId: String
    let dueDate: Date?
    let priority: Int?
    let isOverdue: Bool
}

// MARK: - Stats Widget Data

/// Data for the Quick Stats widget — shows completion counts and streaks
struct WidgetStatsData: Codable, Sendable {
    /// Tasks completed today
    let completedToday: Int

    /// Tasks remaining (pending across all active stacks)
    let pendingTotal: Int

    /// Active stacks count
    let activeStackCount: Int

    /// Overdue tasks count
    let overdueCount: Int

    /// Completion percentage (0.0 - 1.0)
    let completionRate: Double
}

// MARK: - Widget Data Reader

/// Reads widget data from the shared App Group UserDefaults.
/// Used by the widget extension to get the latest data from the main app.
enum WidgetDataReader {
    static func readActiveStack() -> WidgetActiveStackData? {
        guard let defaults = AppGroupConfig.sharedDefaults,
              let data = defaults.data(forKey: AppGroupConfig.activeStackKey) else {
            return nil
        }
        return try? JSONDecoder.widgetDecoder.decode(WidgetActiveStackData.self, from: data)
    }

    static func readUpNext() -> WidgetUpNextData? {
        guard let defaults = AppGroupConfig.sharedDefaults,
              let data = defaults.data(forKey: AppGroupConfig.upNextKey) else {
            return nil
        }
        return try? JSONDecoder.widgetDecoder.decode(WidgetUpNextData.self, from: data)
    }

    static func readStats() -> WidgetStatsData? {
        guard let defaults = AppGroupConfig.sharedDefaults,
              let data = defaults.data(forKey: AppGroupConfig.statsKey) else {
            return nil
        }
        return try? JSONDecoder.widgetDecoder.decode(WidgetStatsData.self, from: data)
    }

    static func lastUpdateDate() -> Date? {
        AppGroupConfig.sharedDefaults?.object(forKey: AppGroupConfig.lastUpdateKey) as? Date
    }
}

// MARK: - JSON Coding Helpers

extension JSONEncoder {
    static let widgetEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension JSONDecoder {
    static let widgetDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
