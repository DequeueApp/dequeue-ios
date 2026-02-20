//
//  AppCommands.swift
//  Dequeue
//
//  Keyboard shortcuts and menu commands for macOS (DEQ-50)
//

import SwiftUI

/// Custom commands for macOS app menus and keyboard shortcuts
struct AppCommands: Commands {
    @FocusedValue(\.newStackAction) private var newStackAction
    @FocusedValue(\.newTaskAction) private var newTaskAction
    @FocusedValue(\.deleteItemAction) private var deleteItemAction
    @FocusedValue(\.openSettingsAction) private var openSettingsAction

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

        // Edit menu - Delete command
        CommandGroup(after: .undoRedo) {
            Divider()
            Button("Delete") {
                deleteItemAction?()
            }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(deleteItemAction == nil)
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
}
