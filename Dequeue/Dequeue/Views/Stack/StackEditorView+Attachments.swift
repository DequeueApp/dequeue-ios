//
//  StackEditorView+Attachments.swift
//  Dequeue
//
//  Attachments section for StackEditorView
//

import SwiftUI
import SwiftData

// MARK: - Attachments Section

extension StackEditorView {
    /// Attachments section for both create and edit modes.
    /// Uses @Query to reactively fetch attachments for the current stack.
    var attachmentsSection: some View {
        AttachmentsSectionView(
            stackId: currentStack?.id,
            isReadOnly: isReadOnly,
            onAddTap: handleAddAttachmentTap,
            onAttachmentTap: handleAttachmentTap,
            onDelete: handleDeleteAttachment
        )
    }

    /// Handles the add attachment button tap.
    /// In create mode without a draft, auto-creates a draft first so attachments can be attached.
    func handleAddAttachmentTap() {
        // If we already have a stack, proceed to file picker
        if currentStack != nil {
            showAttachmentPicker = true
            return
        }

        // In create mode without a draft, create the draft first
        if case .create = mode {
            let draftTitle = title.isEmpty ? "Untitled" : title
            createDraft(title: draftTitle)

            // Show the file picker - draftStack is now set
            if draftStack != nil {
                showAttachmentPicker = true
            }
        }
    }

    /// Handles files selected from the attachment picker.
    /// Creates attachment records and triggers uploads.
    func handleFilesSelected(_ urls: [URL]) {
        guard let stack = currentStack else {
            errorMessage = "No stack available for attachments"
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
                    // Stop accessing the security-scoped resource when done
                    url.stopAccessingSecurityScopedResource()
                }

                do {
                    // Create the attachment record (copies file locally)
                    let attachment = try service.createAttachment(
                        for: stack.id,
                        parentType: .stack,
                        fileURL: url
                    )

                    // Upload to cloud storage
                    if let coordinator = attachmentUploadCoordinator {
                        try await coordinator.uploadAttachment(attachment)
                    }
                } catch {
                    errorMessage = "Failed to add attachment: \(error.localizedDescription)"
                    showError = true
                    ErrorReportingService.capture(error: error, context: [
                        "view": "StackEditorView",
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
                // Use weak capture to prevent potential retain cycle if the closure
                // is retained longer than expected by the preview coordinator.
                downloadHandler: { [weak service = attachmentService] attachment in
                    guard let service else {
                        throw AttachmentServiceError.operationFailed(
                            underlying: NSError(domain: "StackEditorView", code: 1, userInfo: [
                                NSLocalizedDescriptionKey: "Attachment service not available"
                            ])
                        )
                    }
                    return try await service.downloadAttachment(attachment)
                }
            )
        }
    }

    func handleDeleteAttachment(_ attachment: Attachment) {
        // TODO: Delete attachment
        // For now, this is a placeholder - will be implemented with AttachmentService integration
    }
}

// MARK: - Attachments Section View

/// Internal view that uses @Query to fetch attachments for a specific stack.
/// Extracted to allow the @Query to work properly with a dynamic stackId.
struct AttachmentsSectionView: View {
    let stackId: String?
    let isReadOnly: Bool
    var onAddTap: (() -> Void)?
    var onAttachmentTap: ((Attachment) -> Void)?
    var onDelete: ((Attachment) -> Void)?

    /// Query for attachments belonging to this stack.
    /// The filter uses the stackId and filters for non-deleted attachments.
    @Query private var attachments: [Attachment]

    init(
        stackId: String?,
        isReadOnly: Bool,
        onAddTap: (() -> Void)? = nil,
        onAttachmentTap: ((Attachment) -> Void)? = nil,
        onDelete: ((Attachment) -> Void)? = nil
    ) {
        self.stackId = stackId
        self.isReadOnly = isReadOnly
        self.onAddTap = onAddTap
        self.onAttachmentTap = onAttachmentTap
        self.onDelete = onDelete

        // Configure @Query with predicate for this stack
        // Note: We filter only by parentId since IDs are globally unique (CUIDs).
        // No need to filter by parentType which can cause issues with SwiftData predicates.
        if let id = stackId {
            let predicate = #Predicate<Attachment> { attachment in
                attachment.parentId == id && !attachment.isDeleted
            }
            _attachments = Query(filter: predicate, sort: \.createdAt, order: .reverse)
        } else {
            // No stack yet - show empty state
            let predicate = #Predicate<Attachment> { _ in false }
            _attachments = Query(filter: predicate)
        }
    }

    var body: some View {
        Section {
            if attachments.isEmpty {
                emptyState
            } else {
                attachmentsList
            }
        } header: {
            sectionHeader
        }
    }

    // MARK: - Section Header

    private var sectionHeader: some View {
        HStack {
            Text("Attachments")
            Spacer()
            if !attachments.isEmpty {
                Text("\(attachments.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !isReadOnly {
                Button {
                    onAddTap?()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("addAttachmentButton")
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        HStack {
            Label("No attachments", systemImage: "paperclip")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Attachments List

    private var attachmentsList: some View {
        AttachmentGridView(
            attachments: attachments,
            layout: .list,
            onTap: onAttachmentTap,
            onDelete: isReadOnly ? nil : onDelete
        )
    }
}

// MARK: - Preview

#Preview("Empty State") {
    List {
        AttachmentsSectionView(
            stackId: nil,
            isReadOnly: false,
            onAddTap: { }
        )
    }
}

#Preview("With Attachments") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    // swiftlint:disable:next force_try
    let container = try! ModelContainer(
        for: Attachment.self,
        configurations: config
    )

    let stackId = "test-stack-id"
    let attachment1 = Attachment(
        parentId: stackId,
        parentType: .stack,
        filename: "document.pdf",
        mimeType: "application/pdf",
        sizeBytes: 2_400_000,
        uploadState: .completed
    )
    let attachment2 = Attachment(
        parentId: stackId,
        parentType: .stack,
        filename: "photo.jpg",
        mimeType: "image/jpeg",
        sizeBytes: 1_200_000,
        uploadState: .uploading
    )
    container.mainContext.insert(attachment1)
    container.mainContext.insert(attachment2)

    return List {
        AttachmentsSectionView(
            stackId: stackId,
            isReadOnly: false,
            onAddTap: { },
            onAttachmentTap: { _ in },
            onDelete: { _ in }
        )
    }
    .modelContainer(container)
}
