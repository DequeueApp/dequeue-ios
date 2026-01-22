//
//  TaskDetailView+Attachments.swift
//  Dequeue
//
//  Attachments section for TaskDetailView
//

import SwiftUI
import SwiftData

// MARK: - Attachments Section

extension TaskDetailView {
    /// Attachments section for task detail view.
    /// Uses @Query to reactively fetch attachments for the current task.
    var attachmentsSection: some View {
        TaskAttachmentsSectionView(
            taskId: task.id,
            onAddTap: handleAddAttachmentTap,
            onAttachmentTap: handleAttachmentTap,
            onDelete: handleDeleteAttachment
        )
    }

    /// Handles the add attachment button tap - shows the file picker.
    func handleAddAttachmentTap() {
        showAttachmentPicker = true
    }

    /// Handles files selected from the attachment picker.
    /// Creates attachment records and triggers uploads.
    func handleFilesSelected(_ urls: [URL]) {
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
                    let attachment = try await service.createAttachment(
                        for: task.id,
                        parentType: .task,
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
                        "view": "TaskDetailView",
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
                downloadHandler: nil  // TODO: Add download handler for remote-only attachments
            )
        }
    }

    func handleDeleteAttachment(_ attachment: Attachment) {
        // TODO: Delete attachment (will be implemented with AttachmentService integration)
    }
}

// MARK: - Task Attachments Section View

/// Internal view that uses @Query to fetch attachments for a specific task.
/// Extracted to allow the @Query to work properly with a dynamic taskId.
struct TaskAttachmentsSectionView: View {
    let taskId: String
    var onAddTap: (() -> Void)?
    var onAttachmentTap: ((Attachment) -> Void)?
    var onDelete: ((Attachment) -> Void)?

    /// Query for attachments belonging to this task.
    /// The filter uses the taskId and filters for non-deleted attachments.
    @Query private var attachments: [Attachment]

    init(
        taskId: String,
        onAddTap: (() -> Void)? = nil,
        onAttachmentTap: ((Attachment) -> Void)? = nil,
        onDelete: ((Attachment) -> Void)? = nil
    ) {
        self.taskId = taskId
        self.onAddTap = onAddTap
        self.onAttachmentTap = onAttachmentTap
        self.onDelete = onDelete

        // Configure @Query with predicate for this task
        // Note: We filter only by parentId since IDs are globally unique (CUIDs).
        let predicate = #Predicate<Attachment> { attachment in
            attachment.parentId == taskId && !attachment.isDeleted
        }
        _attachments = Query(filter: predicate, sort: \.createdAt, order: .reverse)
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
            Button {
                onAddTap?()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("addTaskAttachmentButton")
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
            onDelete: onDelete
        )
    }
}

// MARK: - Preview

#Preview("Empty State") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    // swiftlint:disable:next force_try
    let container = try! ModelContainer(for: Attachment.self, configurations: config)

    return List {
        TaskAttachmentsSectionView(
            taskId: "test-task-id",
            onAddTap: { }
        )
    }
    .modelContainer(container)
}

#Preview("With Attachments") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    // swiftlint:disable:next force_try
    let container = try! ModelContainer(
        for: Attachment.self,
        configurations: config
    )

    let taskId = "test-task-id"
    let attachment1 = Attachment(
        parentId: taskId,
        parentType: .task,
        filename: "notes.txt",
        mimeType: "text/plain",
        sizeBytes: 1_200,
        uploadState: .completed
    )
    let attachment2 = Attachment(
        parentId: taskId,
        parentType: .task,
        filename: "screenshot.png",
        mimeType: "image/png",
        sizeBytes: 540_000,
        uploadState: .uploading
    )
    container.mainContext.insert(attachment1)
    container.mainContext.insert(attachment2)

    return List {
        TaskAttachmentsSectionView(
            taskId: taskId,
            onAddTap: { },
            onAttachmentTap: { _ in },
            onDelete: { _ in }
        )
    }
    .modelContainer(container)
}
