//
//  FileTypeIcon.swift
//  Dequeue
//
//  SF Symbols icons for file types based on MIME type
//

import SwiftUI

// MARK: - File Type Icon Mapping

/// Maps MIME types to appropriate SF Symbols
// swiftlint:disable type_body_length cyclomatic_complexity function_body_length
enum FileTypeIcon {
    /// Returns the SF Symbol name for a given MIME type
    static func symbolName(for mimeType: String) -> String {
        let lowerMimeType = mimeType.lowercased()

        // Check prefixes first (audio/*, video/*, image/*)
        if lowerMimeType.hasPrefix("audio/") {
            return "waveform"
        }
        if lowerMimeType.hasPrefix("video/") {
            return "film"
        }
        if lowerMimeType.hasPrefix("image/") {
            return "photo"
        }
        if lowerMimeType.hasPrefix("text/") {
            return textTypeSymbol(for: lowerMimeType)
        }

        // Check specific MIME types
        switch lowerMimeType {
        // PDF
        case "application/pdf":
            return "doc.fill"

        // Microsoft Office - Word
        case "application/msword",
             "application/vnd.openxmlformats-officedocument.wordprocessingml.document":
            return "doc.text.fill"

        // Microsoft Office - Excel
        case "application/vnd.ms-excel",
             "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet":
            return "tablecells.fill"

        // Microsoft Office - PowerPoint
        case "application/vnd.ms-powerpoint",
             "application/vnd.openxmlformats-officedocument.presentationml.presentation":
            return "rectangle.split.3x3.fill"

        // Apple iWork
        case "application/vnd.apple.pages":
            return "doc.text.fill"
        case "application/vnd.apple.numbers":
            return "tablecells.fill"
        case "application/vnd.apple.keynote":
            return "rectangle.split.3x3.fill"

        // Archives
        case "application/zip",
             "application/x-zip-compressed",
             "application/x-rar-compressed",
             "application/x-7z-compressed",
             "application/gzip",
             "application/x-tar":
            return "doc.zipper"

        // Code/Programming
        case "application/json",
             "application/xml",
             "application/javascript",
             "application/x-javascript",
             "application/typescript":
            return "chevron.left.forwardslash.chevron.right"

        // Executables
        case "application/x-apple-diskimage",
             "application/octet-stream":
            return "app.fill"

        // Calendar
        case "text/calendar",
             "application/ics":
            return "calendar"

        // VCard
        case "text/vcard",
             "text/x-vcard":
            return "person.crop.rectangle.fill"

        // Default
        default:
            return "doc.fill"
        }
    }

    /// Returns symbol for text/* MIME types
    private static func textTypeSymbol(for mimeType: String) -> String {
        switch mimeType {
        case "text/html":
            return "globe"
        case "text/css":
            return "chevron.left.forwardslash.chevron.right"
        case "text/javascript":
            return "chevron.left.forwardslash.chevron.right"
        case "text/markdown":
            return "doc.richtext"
        case "text/csv":
            return "tablecells"
        case "text/calendar":
            return "calendar"
        default:
            return "doc.plaintext.fill"
        }
    }

    /// Returns the primary color for a file type
    static func color(for mimeType: String) -> Color {
        let lowerMimeType = mimeType.lowercased()

        if lowerMimeType.hasPrefix("audio/") {
            return .purple
        }
        if lowerMimeType.hasPrefix("video/") {
            return .pink
        }
        if lowerMimeType.hasPrefix("image/") {
            return .green
        }

        switch lowerMimeType {
        case "application/pdf":
            return .red

        case "application/msword",
             "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
             "application/vnd.apple.pages":
            return .blue

        case "application/vnd.ms-excel",
             "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
             "application/vnd.apple.numbers":
            return .green

        case "application/vnd.ms-powerpoint",
             "application/vnd.openxmlformats-officedocument.presentationml.presentation",
             "application/vnd.apple.keynote":
            return .orange

        case "application/zip",
             "application/x-zip-compressed",
             "application/x-rar-compressed",
             "application/x-7z-compressed",
             "application/gzip",
             "application/x-tar":
            return .brown

        case "application/json",
             "application/xml",
             "application/javascript",
             "text/css",
             "text/javascript":
            return .cyan

        default:
            return .secondary
        }
    }
}
// swiftlint:enable type_body_length cyclomatic_complexity function_body_length

// MARK: - File Type Icon View

/// A view displaying an SF Symbol icon for a file type
struct FileTypeIconView: View {
    let mimeType: String
    var size: CGFloat = 40

    private var symbolName: String {
        FileTypeIcon.symbolName(for: mimeType)
    }

    private var iconColor: Color {
        FileTypeIcon.color(for: mimeType)
    }

    var body: some View {
        Image(systemName: symbolName)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .foregroundStyle(iconColor)
    }
}

// MARK: - Attachment File Icon View

/// A view displaying file icon with filename and size for attachments without thumbnails
struct AttachmentFileIconView: View {
    let attachment: Attachment
    var iconSize: CGFloat = 48
    var showDetails: Bool = true

    var body: some View {
        VStack(spacing: 8) {
            FileTypeIconView(mimeType: attachment.mimeType, size: iconSize)

            if showDetails {
                VStack(spacing: 2) {
                    Text(attachment.filename)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    Text(attachment.formattedSize)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Attachment Extension

extension Attachment {
    /// Returns the SF Symbol name for this attachment's file type
    var fileTypeIconName: String {
        FileTypeIcon.symbolName(for: mimeType)
    }

    /// Returns the color for this attachment's file type icon
    var fileTypeIconColor: Color {
        FileTypeIcon.color(for: mimeType)
    }
}

// MARK: - Previews

#Preview("File Type Icons") {
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 20) {
            ForEach([
                "application/pdf",
                "application/msword",
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                "application/vnd.ms-powerpoint",
                "application/zip",
                "image/jpeg",
                "video/mp4",
                "audio/mpeg",
                "text/plain",
                "application/json",
                "text/html",
                "application/octet-stream"
            ], id: \.self) { mimeType in
                VStack {
                    FileTypeIconView(mimeType: mimeType, size: 40)
                    Text(mimeType.components(separatedBy: "/").last ?? mimeType)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 100, height: 80)
            }
        }
        .padding()
    }
}

#Preview("Attachment File Icon") {
    VStack(spacing: 24) {
        AttachmentFileIconView(
            attachment: Attachment(
                parentId: "test",
                parentType: .stack,
                filename: "quarterly_report.xlsx",
                mimeType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                sizeBytes: 2_500_000
            )
        )

        AttachmentFileIconView(
            attachment: Attachment(
                parentId: "test",
                parentType: .stack,
                filename: "presentation.pptx",
                mimeType: "application/vnd.openxmlformats-officedocument.presentationml.presentation",
                sizeBytes: 5_000_000
            )
        )

        AttachmentFileIconView(
            attachment: Attachment(
                parentId: "test",
                parentType: .stack,
                filename: "archive.zip",
                mimeType: "application/zip",
                sizeBytes: 10_000_000
            )
        )
    }
    .padding()
}
