//
//  ArcEditorView+Actions.swift
//  Dequeue
//
//  Arc editor action handlers (save, pause, resume, complete, delete)
//

import SwiftUI
import os

private let logger = Logger(subsystem: "com.dequeue", category: "ArcEditorView+Actions")

// MARK: - Actions Extension

extension ArcEditorView {
    // MARK: - Arc Actions

    func saveArc() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        // Determine if we need to prompt for due date reminder (on create with due date)
        let isCreatingWithDueDate = editingArc == nil && hasDueDate && dueDate != nil

        Task {
            do {
                if let arc = editingArc {
                    // Update existing arc
                    try await arcService?.updateArc(
                        arc,
                        title: trimmedTitle,
                        description: arcDescription.isEmpty ? nil : arcDescription,
                        colorHex: selectedColorHex,
                        startTime: hasStartDate ? (startDate.map { .set($0) } ?? .clear) : .clear,
                        dueTime: hasDueDate ? (dueDate.map { .set($0) } ?? .clear) : .clear
                    )
                    logger.info("Updated arc: \(arc.id)")
                    dismiss()
                } else {
                    // Create new arc
                    let newArc = try await arcService?.createArc(
                        title: trimmedTitle,
                        description: arcDescription.isEmpty ? nil : arcDescription,
                        colorHex: selectedColorHex,
                        startTime: hasStartDate ? startDate : nil,
                        dueTime: hasDueDate ? dueDate : nil
                    )
                    logger.info("Created arc: \(newArc?.id ?? "unknown")")

                    // If created with due date, offer to create reminder
                    if isCreatingWithDueDate, let arc = newArc {
                        await createDueDateReminderIfNeeded(for: arc)
                    }
                    dismiss()
                }
            } catch ArcServiceError.maxActiveArcsExceeded(let limit) {
                errorMessage = "You can have up to \(limit) active arcs. Complete or pause an existing arc first."
                showError = true
            } catch {
                logger.error("Failed to save arc: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
                showError = true
                ErrorReportingService.capture(error: error, context: ["action": "save_arc"])
            }
        }
    }

    /// Creates a reminder for the due date if appropriate
    private func createDueDateReminderIfNeeded(for arc: Arc) async {
        guard let dueDate = dueDate,
              let reminderDate = dueDate.morningReminderTime() else { return }

        // Note: For create flow, we automatically create the reminder without prompting
        // since the user explicitly set a due date. The prompt is shown during edit flow.
        do {
            try await createDueDateReminder(for: arc, at: reminderDate)
        } catch {
            // Silent failure for create flow - just log, don't interrupt the user
            logger.error("Failed to create due date reminder: \(error.localizedDescription)")
        }
    }

    /// Shared helper to create a due date reminder for an arc
    /// Throws on failure so callers can handle errors appropriately
    func createDueDateReminder(for arc: Arc, at reminderDate: Date) async throws {
        let userId = authService.currentUserId ?? ""
        let reminderService = ReminderService(
            modelContext: modelContext,
            userId: userId,
            deviceId: cachedDeviceId,
            syncManager: syncManager
        )
        _ = try await reminderService.createReminder(for: arc, at: reminderDate)
        logger.info("Created due date reminder for arc: \(arc.id)")
    }

    func pauseArc() {
        guard let arc = editingArc else { return }
        Task {
            do {
                try await arcService?.pause(arc)
                logger.info("Paused arc: \(arc.id)")
            } catch {
                handleError(error, action: "pause_arc")
            }
        }
    }

    func resumeArc() {
        guard let arc = editingArc else { return }
        Task {
            do {
                try await arcService?.resume(arc)
                logger.info("Resumed arc: \(arc.id)")
            } catch {
                handleError(error, action: "resume_arc")
            }
        }
    }

    func completeArc() {
        guard let arc = editingArc else { return }
        Task {
            do {
                try await arcService?.markAsCompleted(arc)
                logger.info("Completed arc: \(arc.id)")
                dismiss()
            } catch {
                handleError(error, action: "complete_arc")
            }
        }
    }

    func reopenArc() {
        guard let arc = editingArc else { return }
        Task {
            do {
                try await arcService?.resume(arc)
                logger.info("Reopened arc: \(arc.id)")
            } catch {
                handleError(error, action: "reopen_arc")
            }
        }
    }

    func unarchiveArc() {
        guard let arc = editingArc else { return }
        Task {
            do {
                try await arcService?.resume(arc)
                logger.info("Unarchived arc: \(arc.id)")
            } catch {
                handleError(error, action: "unarchive_arc")
            }
        }
    }

    func deleteArc() {
        guard let arc = editingArc else { return }
        Task {
            do {
                try await arcService?.deleteArc(arc)
                logger.info("Deleted arc: \(arc.id)")
                dismiss()
            } catch {
                handleError(error, action: "delete_arc")
            }
        }
    }

    func handleError(_ error: Error, action: String) {
        logger.error("Failed to \(action): \(error.localizedDescription)")
        errorMessage = error.localizedDescription
        showError = true
        ErrorReportingService.capture(error: error, context: ["action": action])
    }
}
