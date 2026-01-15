//
//  AttachmentActions.swift
//  Dequeue
//
//  Context menu and swipe actions for attachments
//

import SwiftUI

// MARK: - Attachment Action Handler

/// Protocol for handling attachment actions
protocol AttachmentActionHandler {
    func open(_ attachment: Attachment)
    func share(_ attachment: Attachment)
    func download(_ attachment: Attachment)
    func removeLocalCopy(_ attachment: Attachment)
    func delete(_ attachment: Attachment)
}

// MARK: - Context Menu Builder

/// Builds context menu for an attachment based on its state
struct AttachmentContextMenu: View {
    let attachment: Attachment
    var onOpen: (() -> Void)?
    var onShare: (() -> Void)?
    var onDownload: (() -> Void)?
    var onRemoveLocalCopy: (() -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        Group {
            // Open action - available when file is local
            if attachment.isAvailableLocally, let onOpen {
                Button {
                    onOpen()
                } label: {
                    Label("Open", systemImage: "eye")
                }
            }

            // Share action - available when file is local
            if attachment.isAvailableLocally, let onShare {
                Button {
                    onShare()
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }

            // Download action - available when uploaded but not local
            if !attachment.isAvailableLocally && attachment.isUploaded, let onDownload {
                Button {
                    onDownload()
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }
            }

            // Remove local copy - available when file is local and uploaded
            if attachment.isAvailableLocally && attachment.isUploaded, let onRemoveLocalCopy {
                Button {
                    onRemoveLocalCopy()
                } label: {
                    Label("Remove Local Copy", systemImage: "icloud.slash")
                }
            }

            if onDelete != nil || onShare != nil {
                Divider()
            }

            // Delete action - always available
            if let onDelete {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}

// MARK: - Swipe Actions

/// Swipe actions for attachment rows in list view
struct AttachmentSwipeActions: ViewModifier {
    let attachment: Attachment
    var onDelete: (() -> Void)?
    var onDownload: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if let onDelete {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if !attachment.isAvailableLocally && attachment.isUploaded, let onDownload {
                    Button {
                        onDownload()
                    } label: {
                        Label("Download", systemImage: "arrow.down.circle")
                    }
                    .tint(.blue)
                }
            }
    }
}

extension View {
    /// Adds swipe actions for attachment management
    func attachmentSwipeActions(
        for attachment: Attachment,
        onDelete: (() -> Void)? = nil,
        onDownload: (() -> Void)? = nil
    ) -> some View {
        modifier(AttachmentSwipeActions(
            attachment: attachment,
            onDelete: onDelete,
            onDownload: onDownload
        ))
    }
}

// MARK: - Delete Confirmation Dialog

/// State object for managing delete confirmation
@Observable
final class AttachmentDeleteConfirmation {
    var isPresented = false
    var attachmentToDelete: Attachment?
    var parentType: String = "item"

    func requestDelete(_ attachment: Attachment, parentType: ParentType) {
        self.attachmentToDelete = attachment
        self.parentType = parentType == .stack ? "Stack" : "Task"
        self.isPresented = true
    }

    func reset() {
        attachmentToDelete = nil
        isPresented = false
    }
}

/// View modifier for showing delete confirmation dialog
struct AttachmentDeleteConfirmationModifier: ViewModifier {
    @Bindable var confirmation: AttachmentDeleteConfirmation
    var onConfirmDelete: (Attachment) -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Remove Attachment?",
                isPresented: $confirmation.isPresented,
                titleVisibility: .visible,
                presenting: confirmation.attachmentToDelete
            ) { attachment in
                Button("Remove", role: .destructive) {
                    onConfirmDelete(attachment)
                    confirmation.reset()
                }
                Button("Cancel", role: .cancel) {
                    confirmation.reset()
                }
            } message: { attachment in
                Text("The file \"\(attachment.filename)\" will be removed from this \(confirmation.parentType).")
            }
    }
}

extension View {
    /// Adds delete confirmation dialog for attachments
    func attachmentDeleteConfirmation(
        _ confirmation: AttachmentDeleteConfirmation,
        onConfirmDelete: @escaping (Attachment) -> Void
    ) -> some View {
        modifier(AttachmentDeleteConfirmationModifier(
            confirmation: confirmation,
            onConfirmDelete: onConfirmDelete
        ))
    }
}

// MARK: - Share Sheet

#if os(iOS)
/// Share sheet for iOS
struct AttachmentShareSheet: UIViewControllerRepresentable {
    let url: URL
    var onComplete: (() -> Void)?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )
        controller.completionWithItemsHandler = { _, _, _, _ in
            onComplete?()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

// MARK: - Quick Look Preview

#if os(iOS)
import QuickLook

/// Quick Look preview for viewing attachments
struct AttachmentQuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
#endif

// MARK: - Previews

#Preview("Context Menu - Local File") {
    List {
        Text("Long press for menu")
            .contextMenu {
                AttachmentContextMenu(
                    attachment: Attachment(
                        parentId: "test",
                        parentType: .stack,
                        filename: "document.pdf",
                        mimeType: "application/pdf",
                        sizeBytes: 1_000_000,
                        localPath: "/path/to/file",
                        uploadState: .completed
                    ),
                    onOpen: { },
                    onShare: { },
                    onRemoveLocalCopy: { },
                    onDelete: { }
                )
            }
    }
}

#Preview("Context Menu - Cloud Only") {
    List {
        Text("Long press for menu")
            .contextMenu {
                AttachmentContextMenu(
                    attachment: Attachment(
                        parentId: "test",
                        parentType: .stack,
                        filename: "document.pdf",
                        mimeType: "application/pdf",
                        sizeBytes: 1_000_000,
                        remoteUrl: "https://example.com/file",
                        uploadState: .completed
                    ),
                    onDownload: { },
                    onDelete: { }
                )
            }
    }
}
