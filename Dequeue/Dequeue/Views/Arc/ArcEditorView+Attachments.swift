//
//  ArcEditorView+Attachments.swift
//  Dequeue
//
//  Attachments section for ArcEditorView
//

import SwiftUI

// MARK: - Attachments Section

extension ArcEditorView {
    /// Attachments section for arc edit mode.
    /// Uses AttachmentsSectionView with the arc's ID.
    var attachmentsSection: some View {
        AttachmentsSectionView(
            stackId: editingArc?.id,
            isReadOnly: false,
            onAddTap: { showAttachmentPicker = true },
            onAttachmentTap: handleAttachmentTap,
            onDelete: handleDeleteAttachment
        )
    }

    /// Handles files selected from the attachment picker.
    /// Creates attachment records and triggers uploads.
    func handleFilesSelected(_ urls: [URL]) {
        guard let arc = editingArc else {
            errorMessage = "No arc available for attachments"
            showError = true
            return
        }

        guard let service = attachmentService else {
            errorMessage = "Attachment service not available"
            showError = true
            return
        }

        Task {
            for url in urls {
                defer {
                    url.stopAccessingSecurityScopedResource()
                }

                do {
                    let attachment = try service.createAttachment(
                        for: arc.id,
                        parentType: .arc,
                        fileURL: url
                    )

                    if let coordinator = attachmentUploadCoordinator {
                        try await coordinator.uploadAttachment(attachment)
                    }
                } catch {
                    errorMessage = "Failed to add attachment: \(error.localizedDescription)"
                    showError = true
                    ErrorReportingService.capture(error: error, context: [
                        "view": "ArcEditorView",
                        "action": "handleFilesSelected",
                        "filename": url.lastPathComponent
                    ])
                }
            }
        }
    }

    func handleAttachmentTap(_ attachment: Attachment) {
        Task {
            await previewCoordinator.preview(
                attachment: attachment,
                downloadHandler: nil
            )
        }
    }

    func handleDeleteAttachment(_ attachment: Attachment) {
        attachmentToDelete = attachment
        showDeleteAttachmentConfirmation = true
    }
}
