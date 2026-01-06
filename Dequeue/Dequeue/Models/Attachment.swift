//
//  Attachment.swift
//  Dequeue
//
//  File attachment for Stacks and Tasks
//
//  Note: Uses parentId/parentType instead of SwiftData @Relationship because:
//  1. An attachment can belong to either a Stack OR a Task (polymorphic)
//  2. Matches the backend event-first architecture where events use IDs
//  3. Allows flexible querying without complex relationship navigation
//  The existing Stack.attachments: [String] and QueueTask.attachments: [String]
//  will be deprecated once the Attachment model is fully integrated.
//

import Foundation
import SwiftData

@Model
final class Attachment {
    @Attribute(.unique) var id: String

    /// The ID of the parent Stack or Task
    var parentId: String

    /// Whether this attachment belongs to a Stack or Task
    var parentType: ParentType

    // File metadata
    var filename: String
    var mimeType: String
    var sizeBytes: Int64
    var remoteUrl: String?

    /// Absolute path to the locally cached file in Documents/Attachments/
    var localPath: String?

    // Preview
    var thumbnailData: Data?
    var previewUrl: String?

    // Timestamps
    var createdAt: Date
    var updatedAt: Date
    var isDeleted: Bool

    // Sync fields
    var userId: String?
    var deviceId: String?
    var syncState: SyncState
    var uploadState: UploadState
    var lastSyncedAt: Date?
    var serverId: String?
    var revision: Int

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
        userId: String? = nil,
        deviceId: String? = nil,
        syncState: SyncState = .pending,
        uploadState: UploadState = .pending,
        lastSyncedAt: Date? = nil,
        serverId: String? = nil,
        revision: Int = 1
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
        self.userId = userId
        self.deviceId = deviceId
        self.syncState = syncState
        self.uploadState = uploadState
        self.lastSyncedAt = lastSyncedAt
        self.serverId = serverId
        self.revision = revision
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
