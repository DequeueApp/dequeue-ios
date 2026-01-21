//
//  ArcEditorView+Reminders.swift
//  Dequeue
//
//  Reminders section for ArcEditorView
//

import SwiftUI

// MARK: - Reminders Section

extension ArcEditorView {
    var remindersSection: some View {
        Section {
            if let arc = editingArc, !arc.activeReminders.isEmpty {
                remindersList(for: arc)
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
                if editingArc != nil {
                    Button {
                        showAddReminder = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("addArcReminderButton")
                }
            }
        }
    }

    @ViewBuilder
    private func remindersList(for arc: Arc) -> some View {
        ForEach(arc.activeReminders) { reminder in
            ReminderRowView(
                reminder: reminder,
                onTap: {
                    selectedReminderForEdit = reminder
                    showEditReminder = true
                },
                onSnooze: {
                    selectedReminderForSnooze = reminder
                    showSnoozePicker = true
                },
                onDismiss: reminder.isPastDue ? {
                    reminderActionHandler?.dismiss(reminder)
                } : nil,
                onDelete: {
                    reminderToDelete = reminder
                    showDeleteReminderConfirmation = true
                }
            )
        }
    }
}
