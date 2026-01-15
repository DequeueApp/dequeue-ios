//
//  AttachmentGridView.swift
//  Dequeue
//
//  Reusable component for displaying attachments in grid or list layout
//

import SwiftUI

struct AttachmentGridView: View {
    let attachments: [Attachment]
    var layout: Layout = .list
    var onTap: ((Attachment) -> Void)?
    var onDelete: ((Attachment) -> Void)?

    enum Layout {
        case list
        case grid
    }

    var body: some View {
        switch layout {
        case .list:
            listLayout
        case .grid:
            gridLayout
        }
    }

    // MARK: - List Layout

    private var listLayout: some View {
        ForEach(attachments) { attachment in
            AttachmentRowView(
                attachment: attachment,
                onTap: onTap.map { tap in { tap(attachment) } },
                onDelete: onDelete.map { delete in { delete(attachment) } }
            )
        }
    }

    // MARK: - Grid Layout

    private var gridLayout: some View {
        LazyVGrid(columns: gridColumns, spacing: 12) {
            ForEach(attachments) { attachment in
                AttachmentGridCell(
                    attachment: attachment,
                    onTap: onTap.map { tap in { tap(attachment) } },
                    onDelete: onDelete.map { delete in { delete(attachment) } }
                )
            }
        }
    }

    private var gridColumns: [GridItem] {
        #if os(macOS)
        [GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 12)]
        #else
        [GridItem(.adaptive(minimum: 80, maximum: 120), spacing: 12)]
        #endif
    }
}

// MARK: - Grid Cell

struct AttachmentGridCell: View {
    let attachment: Attachment
    var onTap: (() -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        VStack(spacing: 6) {
            thumbnailView
            fileInfo
        }
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
        ZStack(alignment: .topTrailing) {
            thumbnailContent
            statusBadge
        }
    }

    @ViewBuilder
    private var thumbnailContent: some View {
        Group {
            if let thumbnailData = attachment.thumbnailData,
               let uiImage = platformImage(from: thumbnailData) {
                Image(platformImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.secondary.opacity(0.1)
                    Image(systemName: fileTypeIcon)
                        .font(.title)
                        .foregroundStyle(fileTypeColor)
                }
            }
        }
        .frame(width: 80, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var statusBadge: some View {
        Group {
            switch attachment.uploadState {
            case .pending:
                Image(systemName: "clock.fill")
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(.secondary)
                    .clipShape(Circle())

            case .uploading:
                ProgressView()
                    .controlSize(.mini)
                    .padding(4)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())

            case .completed:
                if !attachment.isAvailableLocally {
                    Image(systemName: "icloud.and.arrow.down")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(.blue)
                        .clipShape(Circle())
                }

            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(.red)
                    .clipShape(Circle())
            }
        }
        .offset(x: 4, y: -4)
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
        VStack(spacing: 2) {
            Text(attachment.filename)
                .font(.caption)
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)

            Text(attachment.formattedSize)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 80)
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

// MARK: - Previews

#Preview("List Layout") {
    List {
        AttachmentGridView(
            attachments: [
                Attachment(
                    parentId: "test",
                    parentType: .stack,
                    filename: "document.pdf",
                    mimeType: "application/pdf",
                    sizeBytes: 2_400_000,
                    uploadState: .completed
                ),
                Attachment(
                    parentId: "test",
                    parentType: .stack,
                    filename: "photo.jpg",
                    mimeType: "image/jpeg",
                    sizeBytes: 1_200_000,
                    uploadState: .uploading
                ),
                Attachment(
                    parentId: "test",
                    parentType: .stack,
                    filename: "video.mp4",
                    mimeType: "video/mp4",
                    sizeBytes: 45_600_000,
                    uploadState: .failed
                )
            ],
            layout: .list,
            onTap: { _ in },
            onDelete: { _ in }
        )
    }
}

#Preview("Grid Layout") {
    ScrollView {
        AttachmentGridView(
            attachments: [
                Attachment(
                    parentId: "test",
                    parentType: .stack,
                    filename: "document.pdf",
                    mimeType: "application/pdf",
                    sizeBytes: 2_400_000,
                    uploadState: .completed
                ),
                Attachment(
                    parentId: "test",
                    parentType: .stack,
                    filename: "photo.jpg",
                    mimeType: "image/jpeg",
                    sizeBytes: 1_200_000,
                    uploadState: .uploading
                ),
                Attachment(
                    parentId: "test",
                    parentType: .stack,
                    filename: "video.mp4",
                    mimeType: "video/mp4",
                    sizeBytes: 45_600_000,
                    uploadState: .pending
                ),
                Attachment(
                    parentId: "test",
                    parentType: .stack,
                    filename: "audio.mp3",
                    mimeType: "audio/mpeg",
                    sizeBytes: 5_000_000,
                    uploadState: .completed
                )
            ],
            layout: .grid,
            onTap: { _ in },
            onDelete: { _ in }
        )
        .padding()
    }
}
