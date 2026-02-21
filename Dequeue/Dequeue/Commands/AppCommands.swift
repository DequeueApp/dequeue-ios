//
//  AppCommands.swift
//  Dequeue
//
//  Keyboard shortcuts and menu commands for macOS (DEQ-50)
//

import SwiftUI

/// Custom commands for macOS app menus and keyboard shortcuts
struct AppCommands: Commands {
    // Existing actions
    @FocusedValue(\.newStackAction) private var newStackAction
    @FocusedValue(\.newTaskAction) private var newTaskAction
    @FocusedValue(\.deleteItemAction) private var deleteItemAction
    @FocusedValue(\.openSettingsAction) private var openSettingsAction

    // New actions
    @FocusedValue(\.completeTaskAction) private var completeTaskAction
    @FocusedValue(\.searchAction) private var searchAction
    @FocusedValue(\.syncAction) private var syncAction
    @FocusedValue(\.navigateToStacksAction) private var navigateToStacksAction
    @FocusedValue(\.navigateToActivityAction) private var navigateToActivityAction
    @FocusedValue(\.navigateToRemindersAction) private var navigateToRemindersAction
    @FocusedValue(\.navigateToArcsAction) private var navigateToArcsAction
    @FocusedValue(\.navigateToTagsAction) private var navigateToTagsAction
    @FocusedValue(\.editItemAction) private var editItemAction
    @FocusedValue(\.activateStackAction) private var activateStackAction

    var body: some Commands {
        // File menu commands
        CommandGroup(after: .newItem) {
            Button("New Stack") {
                newStackAction?()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(newStackAction == nil)

            Button("New Task") {
                newTaskAction?()
            }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(newTaskAction == nil)
        }

        // Settings command (typically in app menu on macOS)
        CommandGroup(replacing: .appSettings) {
            Button("Settings...") {
                openSettingsAction?()
            }
            .keyboardShortcut(",", modifiers: .command)
            .disabled(openSettingsAction == nil)
        }

        // Edit menu - Delete and Edit commands
        CommandGroup(after: .undoRedo) {
            Divider()

            Button("Edit") {
                editItemAction?()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(editItemAction == nil)

            Button("Delete") {
                deleteItemAction?()
            }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(deleteItemAction == nil)
        }

        // View menu - Navigation shortcuts
        CommandMenu("Navigate") {
            Button("Stacks") {
                navigateToStacksAction?()
            }
            .keyboardShortcut("1", modifiers: .command)
            .disabled(navigateToStacksAction == nil)

            Button("Activity") {
                navigateToActivityAction?()
            }
            .keyboardShortcut("2", modifiers: .command)
            .disabled(navigateToActivityAction == nil)

            Button("Reminders") {
                navigateToRemindersAction?()
            }
            .keyboardShortcut("3", modifiers: .command)
            .disabled(navigateToRemindersAction == nil)

            Button("Arcs") {
                navigateToArcsAction?()
            }
            .keyboardShortcut("4", modifiers: .command)
            .disabled(navigateToArcsAction == nil)

            Button("Tags") {
                navigateToTagsAction?()
            }
            .keyboardShortcut("5", modifiers: .command)
            .disabled(navigateToTagsAction == nil)

            Divider()

            Button("Search") {
                searchAction?()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(searchAction == nil)
        }

        // Stack menu - Stack-specific operations
        CommandMenu("Stack") {
            Button("Complete Current Task") {
                completeTaskAction?()
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(completeTaskAction == nil)

            Button("Activate Stack") {
                activateStackAction?()
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(activateStackAction == nil)

            Divider()

            Button("Sync Now") {
                syncAction?()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(syncAction == nil)
        }
    }
}

// MARK: - Focused Value Keys

/// Action to create a new stack
struct NewStackActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

/// Action to create a new task (context-sensitive)
struct NewTaskActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

/// Action to delete the currently selected item
struct DeleteItemActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

/// Action to open settings
struct OpenSettingsActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

/// Action to complete the current/selected task
struct CompleteTaskActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

/// Action to open search
struct SearchActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

/// Action to trigger sync
struct SyncActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

/// Action to navigate to Stacks tab
struct NavigateToStacksActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

/// Action to navigate to Activity tab
struct NavigateToActivityActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

/// Action to navigate to Reminders tab
struct NavigateToRemindersActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

/// Action to navigate to Arcs tab
struct NavigateToArcsActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

/// Action to navigate to Tags tab
struct NavigateToTagsActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

/// Action to edit the currently selected item
struct EditItemActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

/// Action to activate the selected stack
struct ActivateStackActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var newStackAction: NewStackActionKey.Value? {
        get { self[NewStackActionKey.self] }
        set { self[NewStackActionKey.self] = newValue }
    }

    var newTaskAction: NewTaskActionKey.Value? {
        get { self[NewTaskActionKey.self] }
        set { self[NewTaskActionKey.self] = newValue }
    }

    var deleteItemAction: DeleteItemActionKey.Value? {
        get { self[DeleteItemActionKey.self] }
        set { self[DeleteItemActionKey.self] = newValue }
    }

    var openSettingsAction: OpenSettingsActionKey.Value? {
        get { self[OpenSettingsActionKey.self] }
        set { self[OpenSettingsActionKey.self] = newValue }
    }

    var completeTaskAction: CompleteTaskActionKey.Value? {
        get { self[CompleteTaskActionKey.self] }
        set { self[CompleteTaskActionKey.self] = newValue }
    }

    var searchAction: SearchActionKey.Value? {
        get { self[SearchActionKey.self] }
        set { self[SearchActionKey.self] = newValue }
    }

    var syncAction: SyncActionKey.Value? {
        get { self[SyncActionKey.self] }
        set { self[SyncActionKey.self] = newValue }
    }

    var navigateToStacksAction: NavigateToStacksActionKey.Value? {
        get { self[NavigateToStacksActionKey.self] }
        set { self[NavigateToStacksActionKey.self] = newValue }
    }

    var navigateToActivityAction: NavigateToActivityActionKey.Value? {
        get { self[NavigateToActivityActionKey.self] }
        set { self[NavigateToActivityActionKey.self] = newValue }
    }

    var navigateToRemindersAction: NavigateToRemindersActionKey.Value? {
        get { self[NavigateToRemindersActionKey.self] }
        set { self[NavigateToRemindersActionKey.self] = newValue }
    }

    var navigateToArcsAction: NavigateToArcsActionKey.Value? {
        get { self[NavigateToArcsActionKey.self] }
        set { self[NavigateToArcsActionKey.self] = newValue }
    }

    var navigateToTagsAction: NavigateToTagsActionKey.Value? {
        get { self[NavigateToTagsActionKey.self] }
        set { self[NavigateToTagsActionKey.self] = newValue }
    }

    var editItemAction: EditItemActionKey.Value? {
        get { self[EditItemActionKey.self] }
        set { self[EditItemActionKey.self] = newValue }
    }

    var activateStackAction: ActivateStackActionKey.Value? {
        get { self[ActivateStackActionKey.self] }
        set { self[ActivateStackActionKey.self] = newValue }
    }
}
