//
//  AttachmentRowView.swift
//  Dequeue
//
//  Row view for displaying attachment in lists
//

import SwiftUI

struct AttachmentRowView: View {
    let attachment: Attachment
    var onTap: (() -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            thumbnailView
            fileInfo
            Spacer()
            statusIndicator
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
        .contextMenu {
            contextMenuContent
        }
    }

    // MARK: - Thumbnail

    @ViewBuilder
    private var thumbnailView: some View {
        Group {
            if let thumbnailData = attachment.thumbnailData,
               let uiImage = platformImage(from: thumbnailData) {
                Image(platformImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: fileTypeIcon)
                    .font(.title2)
                    .foregroundStyle(fileTypeColor)
            }
        }
        .frame(width: 44, height: 44)
        .background(Color.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var fileTypeIcon: String {
        if attachment.isImage {
            return "photo"
        } else if attachment.isPDF {
            return "doc.fill"
        } else if attachment.mimeType.hasPrefix("video/") {
            return "video.fill"
        } else if attachment.mimeType.hasPrefix("audio/") {
            return "waveform"
        } else {
            return "doc"
        }
    }

    private var fileTypeColor: Color {
        if attachment.isImage {
            return .blue
        } else if attachment.isPDF {
            return .red
        } else if attachment.mimeType.hasPrefix("video/") {
            return .purple
        } else if attachment.mimeType.hasPrefix("audio/") {
            return .orange
        } else {
            return .secondary
        }
    }

    // MARK: - File Info

    private var fileInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(attachment.filename)
                .lineLimit(1)
                .truncationMode(.middle)

            Text(attachment.formattedSize)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Status Indicator

    @ViewBuilder
    private var statusIndicator: some View {
        switch attachment.uploadState {
        case .pending:
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Pending upload")

        case .uploading:
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Uploading")

        case .completed:
            if attachment.isAvailableLocally {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("Available")
            } else {
                Image(systemName: "icloud.and.arrow.down")
                    .foregroundStyle(.blue)
                    .accessibilityLabel("Not downloaded")
            }

        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .accessibilityLabel("Upload failed")
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuContent: some View {
        if let onTap {
            Button {
                onTap()
            } label: {
                Label("Open", systemImage: "eye")
            }
        }

        if !attachment.isAvailableLocally && attachment.uploadState == .completed {
            Button {
                // Download action - to be implemented
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
        }

        if let onDelete {
            Divider()
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Platform Helpers

    #if os(iOS)
    private func platformImage(from data: Data) -> UIImage? {
        UIImage(data: data)
    }
    #elseif os(macOS)
    private func platformImage(from data: Data) -> NSImage? {
        NSImage(data: data)
    }
    #endif
}

// MARK: - Platform Image Extension

#if os(iOS)
private extension Image {
    init(platformImage: UIImage) {
        self.init(uiImage: platformImage)
    }
}
#elseif os(macOS)
private extension Image {
    init(platformImage: NSImage) {
        self.init(nsImage: platformImage)
    }
}
#endif

// MARK: - Preview

#Preview("Pending Upload") {
    List {
        AttachmentRowView(
            attachment: Attachment(
                parentId: "test-stack",
                parentType: .stack,
                filename: "document.pdf",
                mimeType: "application/pdf",
                sizeBytes: 2_400_000,
                uploadState: .pending
            ),
            onTap: { },
            onDelete: { }
        )
    }
}

#Preview("Uploading") {
    List {
        AttachmentRowView(
            attachment: Attachment(
                parentId: "test-stack",
                parentType: .stack,
                filename: "photo.jpg",
                mimeType: "image/jpeg",
                sizeBytes: 1_200_000,
                uploadState: .uploading
            ),
            onTap: { },
            onDelete: { }
        )
    }
}

#Preview("Completed - Local") {
    List {
        AttachmentRowView(
            attachment: Attachment(
                parentId: "test-stack",
                parentType: .stack,
                filename: "video-recording-2024.mp4",
                mimeType: "video/mp4",
                sizeBytes: 45_600_000,
                localPath: "/mock/path",
                uploadState: .completed
            ),
            onTap: { },
            onDelete: { }
        )
    }
}

#Preview("Failed") {
    List {
        AttachmentRowView(
            attachment: Attachment(
                parentId: "test-stack",
                parentType: .stack,
                filename: "failed-upload.png",
                mimeType: "image/png",
                sizeBytes: 500_000,
                uploadState: .failed
            ),
            onTap: { },
            onDelete: { }
        )
    }
}
