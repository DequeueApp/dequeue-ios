//
//  WidgetDataService.swift
//  Dequeue
//
//  Writes widget data to App Group UserDefaults so the widget extension can display
//  current stacks, tasks, and stats. Called whenever relevant data changes.
//
//  DEQ-120, DEQ-121
//

import Foundation
import SwiftData
import WidgetKit
import os.log

/// Service responsible for updating widget data in the shared App Group container.
///
/// Call `updateAllWidgets(context:)` after any data mutation (task creation, completion,
/// stack activation, etc.) to keep widgets in sync with the app state.
@MainActor
enum WidgetDataService {
    private static let logger = Logger(subsystem: "com.dequeue", category: "WidgetDataService")

    /// Updates all widget data and triggers a timeline reload.
    /// Call this after any data change that could affect widgets.
    static func updateAllWidgets(context: ModelContext) {
        guard let defaults = AppGroupConfig.sharedDefaults else {
            logger.warning("App Group UserDefaults not available — widgets cannot be updated")
            return
        }

        updateActiveStack(context: context, defaults: defaults)
        updateUpNext(context: context, defaults: defaults)
        updateStats(context: context, defaults: defaults)
        defaults.set(Date(), forKey: AppGroupConfig.lastUpdateKey)

        // Tell WidgetKit to refresh all timelines
        WidgetCenter.shared.reloadAllTimelines()
        logger.debug("Widget data updated and timelines reloaded")
    }

    // MARK: - Active Stack

    private static func updateActiveStack(context: ModelContext, defaults: UserDefaults) {
        do {
            // Find the currently active stack
            let predicate = #Predicate<Stack> { stack in
                stack.isActive == true && stack.isDeleted == false
            }
            var descriptor = FetchDescriptor<Stack>(predicate: predicate)
            descriptor.fetchLimit = 1

            guard let activeStack = try context.fetch(descriptor).first else {
                // No active stack — clear widget data
                defaults.removeObject(forKey: AppGroupConfig.activeStackKey)
                return
            }

            let pendingTasks = activeStack.pendingTasks
            let activeTask = activeStack.activeTask

            let data = WidgetActiveStackData(
                stackTitle: activeStack.title,
                stackId: activeStack.id,
                activeTaskTitle: activeTask?.title,
                activeTaskId: activeTask?.id,
                pendingTaskCount: pendingTasks.count,
                totalTaskCount: activeStack.tasks.filter { !$0.isDeleted }.count,
                dueDate: activeStack.dueTime,
                priority: activeStack.priority,
                tags: activeStack.tagNames
            )

            let encoded = try JSONEncoder.widgetEncoder.encode(data)
            defaults.set(encoded, forKey: AppGroupConfig.activeStackKey)
        } catch {
            logger.error("Failed to update active stack widget: \(error.localizedDescription)")
        }
    }

    // MARK: - Up Next

    private static func updateUpNext(context: ModelContext, defaults: UserDefaults) {
        do {
            let now = Date()

            // Fetch pending tasks that have a due date
            // Note: #Predicate requires explicit enum comparisons via local variables
            let pendingRaw = TaskStatus.pending.rawValue
            let predicate = #Predicate<QueueTask> { task in
                task.isDeleted == false && task.status.rawValue == pendingRaw && task.dueTime != nil
            }
            var descriptor = FetchDescriptor<QueueTask>(
                predicate: predicate,
                sortBy: [SortDescriptor(\.dueTime, order: .forward)]
            )
            descriptor.fetchLimit = 10

            let tasks = try context.fetch(descriptor)

            let taskItems = tasks.map { task in
                WidgetTaskItem(
                    id: task.id,
                    title: task.title,
                    stackTitle: task.stack?.title ?? "Unknown",
                    stackId: task.stack?.id ?? "",
                    dueDate: task.dueTime,
                    priority: task.priority,
                    isOverdue: task.dueTime.map { $0 < now } ?? false
                )
            }

            let overdueCount = taskItems.filter(\.isOverdue).count

            let data = WidgetUpNextData(
                upcomingTasks: taskItems,
                overdueCount: overdueCount
            )

            let encoded = try JSONEncoder.widgetEncoder.encode(data)
            defaults.set(encoded, forKey: AppGroupConfig.upNextKey)
        } catch {
            logger.error("Failed to update up next widget: \(error.localizedDescription)")
        }
    }

    // MARK: - Stats

    private static func updateStats(context: ModelContext, defaults: UserDefaults) {
        do {
            let now = Date()
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: now)

            // Count tasks completed today
            let completedRaw = TaskStatus.completed.rawValue
            let completedPredicate = #Predicate<QueueTask> { task in
                task.isDeleted == false && task.status.rawValue == completedRaw && task.updatedAt >= startOfDay
            }
            let completedToday = try context.fetchCount(FetchDescriptor<QueueTask>(predicate: completedPredicate))

            // Count pending tasks across all stacks
            let pendingRaw = TaskStatus.pending.rawValue
            let pendingPredicate = #Predicate<QueueTask> { task in
                task.isDeleted == false && task.status.rawValue == pendingRaw
            }
            let pendingTotal = try context.fetchCount(FetchDescriptor<QueueTask>(predicate: pendingPredicate))

            // Count active stacks (using raw value since Stack.status uses statusRawValue)
            let activeRaw = StackStatus.active.rawValue
            let activeStackPredicate = #Predicate<Stack> { stack in
                stack.isDeleted == false && stack.statusRawValue == activeRaw
            }
            let activeStackCount = try context.fetchCount(FetchDescriptor<Stack>(predicate: activeStackPredicate))

            // Count overdue tasks — fetch pending and filter in memory
            // (Date comparisons with optionals are tricky in #Predicate)
            let pendingWithDuePredicate = #Predicate<QueueTask> { task in
                task.isDeleted == false && task.status.rawValue == pendingRaw && task.dueTime != nil
            }
            let pendingWithDue = try context.fetch(FetchDescriptor<QueueTask>(predicate: pendingWithDuePredicate))
            let overdueCount = pendingWithDue.filter { ($0.dueTime ?? .distantFuture) < now }.count

            // Calculate completion rate
            let allTasksPredicate = #Predicate<QueueTask> { task in
                task.isDeleted == false
            }
            let allTaskCount = try context.fetchCount(FetchDescriptor<QueueTask>(predicate: allTasksPredicate))
            let allCompletedPredicate = #Predicate<QueueTask> { task in
                task.isDeleted == false && task.status.rawValue == completedRaw
            }
            let allCompleted = try context.fetchCount(FetchDescriptor<QueueTask>(predicate: allCompletedPredicate))

            let completionRate = allTaskCount > 0
                ? Double(allCompleted) / Double(allTaskCount)
                : 0.0

            let data = WidgetStatsData(
                completedToday: completedToday,
                pendingTotal: pendingTotal,
                activeStackCount: activeStackCount,
                overdueCount: overdueCount,
                completionRate: completionRate
            )

            let encoded = try JSONEncoder.widgetEncoder.encode(data)
            defaults.set(encoded, forKey: AppGroupConfig.statsKey)
        } catch {
            logger.error("Failed to update stats widget: \(error.localizedDescription)")
        }
    }
}
