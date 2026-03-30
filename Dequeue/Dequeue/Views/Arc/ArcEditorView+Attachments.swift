//
//  ArcEditorView+Attachments.swift
//  Dequeue
//
//  Attachments section for ArcEditorView
//

import PhotosUI
import SwiftUI

// MARK: - Attachments Section

extension ArcEditorView {
    /// Attachments section for arc edit mode.
    /// Uses AttachmentsSectionView with the arc's ID.
    var attachmentsSection: some View {
        AttachmentsSectionView(
            stackId: editingArc?.id,
            isReadOnly: false,
            onAddTap: {
                #if os(iOS)
                showAttachmentSourcePicker = true
                #else
                showAttachmentPicker = true
                #endif
            },
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
                    let attachment = try await service.createAttachment(
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
        Task { @MainActor in
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

    #if os(iOS)
    /// Saves a selected PhotosPickerItem to a temporary file and passes it through the upload flow.
    @MainActor
    func handlePhotoSelected(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)
            try data.write(to: tempURL)
            handleFilesSelected([tempURL])
        } catch {
            errorMessage = "Failed to load photo: \(error.localizedDescription)"
            showError = true
        }
    }
    #endif
}
