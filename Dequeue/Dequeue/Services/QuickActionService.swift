//
//  QuickActionService.swift
//  Dequeue
//
//  Home screen Quick Actions (3D Touch / Haptic Touch shortcuts)
//

import SwiftUI
import SwiftData
import os.log

// MARK: - Quick Action Types

/// Defines the available home screen quick actions
enum QuickActionType: String {
    case addTask = "com.ardonos.Dequeue.addTask"
    case viewActiveStack = "com.ardonos.Dequeue.viewActiveStack"
    case search = "com.ardonos.Dequeue.search"
    case newStack = "com.ardonos.Dequeue.newStack"

    /// SF Symbol icon name for the shortcut
    var iconName: String {
        switch self {
        case .addTask: return "plus.circle"
        case .viewActiveStack: return "tray.fill"
        case .search: return "magnifyingglass"
        case .newStack: return "folder.badge.plus"
        }
    }

    /// User-visible title
    var title: String {
        switch self {
        case .addTask: return "Add Task"
        case .viewActiveStack: return "Active Stack"
        case .search: return "Search"
        case .newStack: return "New Stack"
        }
    }

    /// User-visible subtitle (optional)
    var subtitle: String? {
        switch self {
        case .addTask: return "Add a task to current stack"
        case .viewActiveStack: return nil
        case .search: return "Search stacks and tasks"
        case .newStack: return "Create a new stack"
        }
    }

    /// Convert to a dequeue:// deep link URL for the existing DeepLinkManager
    var deepLinkURL: URL? {
        switch self {
        case .addTask:
            return URL(string: "dequeue://action/add-task")
        case .viewActiveStack:
            return URL(string: "dequeue://action/active-stack")
        case .search:
            return URL(string: "dequeue://action/search")
        case .newStack:
            return URL(string: "dequeue://action/new-stack")
        }
    }
}

// MARK: - Quick Action Notification

extension Notification.Name {
    /// Posted when a quick action is triggered from the home screen
    static let quickActionTriggered = Notification.Name("com.dequeue.quickActionTriggered")
}

// MARK: - Quick Action Service

/// Manages home screen quick actions (3D Touch / Haptic Touch shortcuts).
///
/// Quick actions provide fast access to common tasks directly from the app icon:
/// - Add Task: Opens the add task sheet for the active stack
/// - Active Stack: Navigates to the currently active stack
/// - Search: Opens the search view
/// - New Stack: Opens the new stack creation sheet
///
/// Dynamic shortcuts are updated when the app becomes active or after sync,
/// allowing the "Active Stack" subtitle to show the current stack name.
@MainActor
final class QuickActionService {
    static let shared = QuickActionService()

    /// The action type that was triggered (set before scene becomes active)
    private(set) var pendingAction: QuickActionType?

    private init() {}

    // MARK: - Setup Dynamic Shortcuts

    /// Updates the home screen quick action items with current context.
    /// Call this when the app becomes active or after significant data changes.
    func updateShortcutItems(activeStackName: String? = nil) {
        #if os(iOS)
        let addTask = UIApplicationShortcutItem(
            type: QuickActionType.addTask.rawValue,
            localizedTitle: QuickActionType.addTask.title,
            localizedSubtitle: activeStackName.map { "Add to \($0)" } ?? QuickActionType.addTask.subtitle,
            icon: UIApplicationShortcutIcon(systemImageName: QuickActionType.addTask.iconName)
        )

        let activeStack = UIApplicationShortcutItem(
            type: QuickActionType.viewActiveStack.rawValue,
            localizedTitle: activeStackName ?? QuickActionType.viewActiveStack.title,
            localizedSubtitle: activeStackName != nil ? "View active stack" : "No active stack",
            icon: UIApplicationShortcutIcon(systemImageName: QuickActionType.viewActiveStack.iconName)
        )

        let search = UIApplicationShortcutItem(
            type: QuickActionType.search.rawValue,
            localizedTitle: QuickActionType.search.title,
            localizedSubtitle: QuickActionType.search.subtitle,
            icon: UIApplicationShortcutIcon(systemImageName: QuickActionType.search.iconName)
        )

        let newStack = UIApplicationShortcutItem(
            type: QuickActionType.newStack.rawValue,
            localizedTitle: QuickActionType.newStack.title,
            localizedSubtitle: QuickActionType.newStack.subtitle,
            icon: UIApplicationShortcutIcon(systemImageName: QuickActionType.newStack.iconName)
        )

        UIApplication.shared.shortcutItems = [addTask, activeStack, search, newStack]
        os_log("[QuickActions] Updated shortcut items (activeStack: \(activeStackName ?? "none"))")
        #endif
    }

    // MARK: - Handle Shortcut

    #if os(iOS)
    /// Handles a shortcut item that was triggered from the home screen.
    /// Returns true if the shortcut was recognized and handled.
    @discardableResult
    func handleShortcutItem(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
        guard let actionType = QuickActionType(rawValue: shortcutItem.type) else {
            os_log("[QuickActions] Unknown shortcut type: \(shortcutItem.type)")
            return false
        }

        os_log("[QuickActions] Handling action: \(actionType.rawValue)")
        pendingAction = actionType

        // Post notification for the app to handle
        NotificationCenter.default.post(
            name: .quickActionTriggered,
            object: nil,
            userInfo: ["actionType": actionType]
        )

        return true
    }
    #endif

    /// Clears the pending action after it has been consumed by the UI.
    func clearPendingAction() {
        pendingAction = nil
    }

    // MARK: - Active Stack Name Helper

    /// Fetches the name of the currently active stack from SwiftData.
    static func fetchActiveStackName(modelContext: ModelContext) -> String? {
        let descriptor = FetchDescriptor<Stack>(
            predicate: #Predicate<Stack> { stack in
                stack.isActive == true
            }
        )
        return (try? modelContext.fetch(descriptor))?.first?.title
    }
}
