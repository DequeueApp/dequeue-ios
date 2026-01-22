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

        Task {
            do {
                if let arc = editingArc {
                    // Update existing arc
                    try await arcService?.updateArc(
                        arc,
                        title: trimmedTitle,
                        description: arcDescription.isEmpty ? nil : arcDescription,
                        colorHex: selectedColorHex
                    )
                    logger.info("Updated arc: \(arc.id)")
                } else {
                    // Create new arc
                    let arc = try await arcService?.createArc(
                        title: trimmedTitle,
                        description: arcDescription.isEmpty ? nil : arcDescription,
                        colorHex: selectedColorHex
                    )
                    logger.info("Created arc: \(arc?.id ?? "unknown")")
                }
                dismiss()
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
