//
//  StackEditorView+Reminders.swift
//  Dequeue
//
//  Reminders section for StackEditorView
//

import SwiftUI

// MARK: - Reminders Section

extension StackEditorView {
    var remindersSection: some View {
        Section {
            if let stack = currentStack, !stack.activeReminders.isEmpty {
                remindersList
            } else {
                HStack {
                    Label("No reminders", systemImage: "bell.slash")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        } header: {
            HStack {
                Text("Reminders")
                Spacer()
                // Show add button when: not read-only AND (stack exists OR in create mode)
                if !isReadOnly && (currentStack != nil || mode == .create) {
                    Button {
                        handleAddReminderTap()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("addStackReminderButton")
                }
            }
        }
    }

    /// Handles the add reminder button tap.
    /// In create mode without a draft, auto-creates a draft first so reminders can be attached.
    func handleAddReminderTap() {
        // If we already have a stack, just show the sheet
        if currentStack != nil {
            showAddReminder = true
            return
        }

        // In create mode without a draft, create the draft first
        if case .create = mode {
            // Use the current title or "Untitled" as fallback
            let draftTitle = title.isEmpty ? "Untitled" : title
            createDraft(title: draftTitle)

            // Show the sheet - draftStack is now set
            if draftStack != nil {
                showAddReminder = true
            }
        }
    }

    @ViewBuilder
    var remindersList: some View {
        if let stack = currentStack {
            ForEach(stack.activeReminders) { reminder in
                ReminderRowView(
                    reminder: reminder,
                    onTap: isReadOnly ? nil : {
                        selectedReminderForEdit = reminder
                        showEditReminder = true
                    },
                    onSnooze: isReadOnly ? nil : {
                        selectedReminderForSnooze = reminder
                        showSnoozePicker = true
                    },
                    onDismiss: (isReadOnly || !reminder.isPastDue) ? nil : {
                        reminderActionHandler?.dismiss(reminder)
                    },
                    onDelete: isReadOnly ? nil : {
                        reminderToDelete = reminder
                        showDeleteReminderConfirmation = true
                    }
                )
            }
        }
    }
}
