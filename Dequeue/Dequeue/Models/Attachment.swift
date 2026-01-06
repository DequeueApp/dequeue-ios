//
//  Attachment.swift
//  Dequeue
//
//  File attachment for Stacks and Tasks
//

import Foundation
import SwiftData

@Model
final class Attachment {
    @Attribute(.unique) var id: String
    var parentId: String
    var parentType: ParentType

    // File metadata
    var filename: String
    var mimeType: String
    var sizeBytes: Int64
    var remoteUrl: String?
    var localPath: String?

    // Preview
    var thumbnailData: Data?
    var previewUrl: String?

    // Timestamps
    var createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool

    // Sync fields
    var syncState: SyncState
    var uploadState: UploadState
    var lastSyncedAt: Date?

    init(
        id: String = CUID.generate(),
        parentId: String,
        parentType: ParentType,
        filename: String,
        mimeType: String,
        sizeBytes: Int64,
        remoteUrl: String? = nil,
        localPath: String? = nil,
        thumbnailData: Data? = nil,
        previewUrl: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isDeleted: Bool = false,
        syncState: SyncState = .pending,
        uploadState: UploadState = .pending,
        lastSyncedAt: Date? = nil
    ) {
        self.id = id
        self.parentId = parentId
        self.parentType = parentType
        self.filename = filename
        self.mimeType = mimeType
        self.sizeBytes = sizeBytes
        self.remoteUrl = remoteUrl
        self.localPath = localPath
        self.thumbnailData = thumbnailData
        self.previewUrl = previewUrl
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isDeleted = isDeleted
        self.syncState = syncState
        self.uploadState = uploadState
        self.lastSyncedAt = lastSyncedAt
    }
}

// MARK: - Convenience

extension Attachment {
    /// Returns a human-readable file size string
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: sizeBytes)
    }

    /// Returns true if the file is available locally
    var isAvailableLocally: Bool {
        guard let localPath else { return false }
        return FileManager.default.fileExists(atPath: localPath)
    }

    /// Returns true if the file has been uploaded to remote storage
    var isUploaded: Bool {
        uploadState == .completed && remoteUrl != nil
    }

    /// Returns true if the attachment is an image based on MIME type
    var isImage: Bool {
        mimeType.hasPrefix("image/")
    }

    /// Returns true if the attachment is a PDF
    var isPDF: Bool {
        mimeType == "application/pdf"
    }

    /// Returns the file extension from the filename
    var fileExtension: String? {
        let components = filename.components(separatedBy: ".")
        guard components.count > 1 else { return nil }
        return components.last?.lowercased()
    }
}
