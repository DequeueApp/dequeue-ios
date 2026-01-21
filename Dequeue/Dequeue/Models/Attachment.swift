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
    // Note: parentId index can be added when targeting iOS 18+ via #Index macro
    // For now, SwiftData will optimize queries automatically

    @Attribute(.unique) var id: String

    /// The ID of the parent Stack or Task
    var parentId: String

    /// Raw value storage for parentType (SwiftData predicate compatibility)
    var parentTypeRawValue: String

    /// Whether this attachment belongs to a Stack or Task
    var parentType: ParentType {
        get { ParentType(rawValue: parentTypeRawValue) ?? .stack }
        set { parentTypeRawValue = newValue.rawValue }
    }

    // File metadata
    var filename: String
    var mimeType: String
    var sizeBytes: Int64
    var remoteUrl: String?

    /// Path to the locally cached file (relative for new attachments, absolute for legacy).
    /// Use `resolvedLocalPath` to get the full absolute path at runtime.
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
        self.parentTypeRawValue = parentType.rawValue
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
    /// Returns the expected Attachments directory URL
    private static var attachmentsDirectoryURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Attachments")
    }

    /// Returns the expected Attachments directory path
    private static var attachmentsDirectory: String? {
        attachmentsDirectoryURL?.path
    }

    /// Resolves the stored localPath to an absolute path.
    ///
    /// The stored path may be:
    /// - A relative path (e.g., "attachment-id/filename.pdf") - preferred, container-relocation safe
    /// - An absolute path from older versions - supported for backward compatibility
    ///
    /// For relative paths, this reconstructs the full path using the current Documents directory.
    /// For absolute paths, returns them as-is (may fail if container was relocated).
    var resolvedLocalPath: String? {
        // Handle nil or empty/whitespace-only paths
        guard let localPath, !localPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        // If it's a relative path (doesn't start with /), resolve it against attachments directory
        if !localPath.hasPrefix("/") {
            // Security: Validate no path traversal attempts
            guard !localPath.contains("..") else { return nil }

            guard let attachmentsDir = Self.attachmentsDirectoryURL else { return nil }
            let resolved = attachmentsDir.appendingPathComponent(localPath).path

            // Security: Double-check resolved path is within attachments directory
            guard resolved.hasPrefix(attachmentsDir.path) else { return nil }

            return resolved
        }

        // Legacy: absolute path from older code - return as-is
        return localPath
    }

    /// Returns a human-readable file size string
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: sizeBytes)
    }

    /// Returns true if the file is available locally and within the expected directory
    /// - Note: Handles both relative paths (new) and absolute paths (legacy)
    var isAvailableLocally: Bool {
        guard let resolvedPath = resolvedLocalPath else { return false }

        // Security: Validate resolved path is within expected Attachments directory
        guard let expectedPrefix = Self.attachmentsDirectory,
              resolvedPath.hasPrefix(expectedPrefix) else {
            return false
        }

        return FileManager.default.fileExists(atPath: resolvedPath)
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

    /// Migrates an absolute localPath to a relative path if needed.
    ///
    /// This is used to fix attachments that were stored with absolute paths
    /// (which break when iOS relocates the container). After migration,
    /// paths are stored as relative paths like "attachment-id/filename.pdf".
    ///
    /// - Returns: `true` if the path was migrated, `false` if no migration was needed
    @discardableResult
    func migrateToRelativePath() -> Bool {
        guard let currentPath = localPath else { return false }

        // Already a relative path - no migration needed
        guard currentPath.hasPrefix("/") else { return false }

        // Extract the relative portion: Attachments/attachment-id/filename
        // We want just: attachment-id/filename
        // Use lastRange to handle edge cases where path might contain multiple /Attachments/
        if let attachmentsRange = currentPath.range(of: "/Attachments/", options: .backwards) {
            let relativePath = String(currentPath[attachmentsRange.upperBound...])
            localPath = relativePath
            return true
        }

        return false
    }
}
