//
//  AttachmentService.swift
//  Dequeue
//
//  Business logic for Attachment operations
//

import Foundation
import SwiftData
import UniformTypeIdentifiers

// MARK: - Attachment Service Errors

/// Errors that can occur during attachment operations
enum AttachmentServiceError: LocalizedError, Equatable {
    /// File could not be found at the specified URL
    case fileNotFound(URL)
    /// File is too large (exceeds 50 MB limit)
    case fileTooLarge(sizeBytes: Int64, maxBytes: Int64)
    /// Failed to determine MIME type for file
    case unknownMimeType
    /// Failed to copy file to attachments directory
    case fileCopyFailed(underlying: String)
    /// Parent entity (Stack or Task) not found
    case parentNotFound(id: String, type: ParentType)
    /// Attachment not found
    case attachmentNotFound(id: String)
    /// Operation failed and changes were not saved
    case operationFailed(underlying: Error)
    /// Attachment has no remote URL for download
    case noRemoteUrl(attachmentId: String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "File not found at \(url.lastPathComponent)"
        case let .fileTooLarge(sizeBytes, maxBytes):
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            let size = formatter.string(fromByteCount: sizeBytes)
            let max = formatter.string(fromByteCount: maxBytes)
            return "File is too large (\(size)). Maximum size is \(max)."
        case .unknownMimeType:
            return "Could not determine file type"
        case .fileCopyFailed(let underlying):
            return "Failed to copy file: \(underlying)"
        case let .parentNotFound(id, type):
            return "Parent \(type.rawValue) not found: \(id)"
        case .attachmentNotFound(let id):
            return "Attachment not found: \(id)"
        case .operationFailed(let underlying):
            return "Attachment operation failed: \(underlying.localizedDescription)"
        case .noRemoteUrl(let attachmentId):
            return "Attachment \(attachmentId) has no remote URL for download"
        }
    }

    static func == (lhs: AttachmentServiceError, rhs: AttachmentServiceError) -> Bool {
        switch (lhs, rhs) {
        case let (.fileNotFound(lhsURL), .fileNotFound(rhsURL)):
            return lhsURL == rhsURL
        case let (.fileTooLarge(lhsSize, lhsMax), .fileTooLarge(rhsSize, rhsMax)):
            return lhsSize == rhsSize && lhsMax == rhsMax
        case (.unknownMimeType, .unknownMimeType):
            return true
        case let (.fileCopyFailed(lhsError), .fileCopyFailed(rhsError)):
            return lhsError == rhsError
        case let (.parentNotFound(lhsId, lhsType), .parentNotFound(rhsId, rhsType)):
            return lhsId == rhsId && lhsType == rhsType
        case let (.attachmentNotFound(lhsId), .attachmentNotFound(rhsId)):
            return lhsId == rhsId
        case let (.operationFailed(lhsError), .operationFailed(rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        case let (.noRemoteUrl(lhsId), .noRemoteUrl(rhsId)):
            return lhsId == rhsId
        default:
            return false
        }
    }
}

// MARK: - Attachment Service

// Note: @MainActor is required on the entire class because SwiftData's ModelContext
// requires main actor isolation for all operations. File I/O operations (which could
// theoretically be async) are minimal and fast enough that the main actor overhead
// is acceptable. The EventService also requires main actor access.
@MainActor
final class AttachmentService {
    /// Maximum file size in bytes (50 MB)
    static let maxFileSizeBytes: Int64 = 50 * 1_024 * 1_024

    private let modelContext: ModelContext
    private let eventService: EventService
    private let userId: String
    private let deviceId: String
    private let syncManager: SyncManager?
    private let fileManager: FileManager
    private let downloadManager: DownloadManager

    init(
        modelContext: ModelContext,
        userId: String,
        deviceId: String,
        syncManager: SyncManager? = nil,
        fileManager: FileManager = .default,
        downloadManager: DownloadManager = DownloadManager()
    ) {
        self.modelContext = modelContext
        self.userId = userId
        self.deviceId = deviceId
        self.eventService = EventService(modelContext: modelContext, userId: userId, deviceId: deviceId)
        self.syncManager = syncManager
        self.fileManager = fileManager
        self.downloadManager = downloadManager
    }

    // MARK: - Create

    /// Creates a new attachment from a local file URL.
    ///
    /// - Parameters:
    ///   - parentId: The ID of the parent Stack or Task
    ///   - parentType: Whether the parent is a Stack or Task
    ///   - fileURL: The local URL of the file to attach
    /// - Returns: The created Attachment
    /// - Throws: AttachmentServiceError if the operation fails
    func createAttachment(
        for parentId: String,
        parentType: ParentType,
        fileURL: URL
    ) async throws -> Attachment {
        // Validate file exists
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw AttachmentServiceError.fileNotFound(fileURL)
        }

        // Get file attributes
        let attributes = try fileManager.attributesOfItem(atPath: fileURL.path)
        guard let sizeBytes = attributes[.size] as? Int64 else {
            throw AttachmentServiceError.operationFailed(
                underlying: NSError(domain: "AttachmentService", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Could not determine file size"
                ])
            )
        }

        // Validate file size
        guard sizeBytes <= Self.maxFileSizeBytes else {
            throw AttachmentServiceError.fileTooLarge(sizeBytes: sizeBytes, maxBytes: Self.maxFileSizeBytes)
        }

        // Determine MIME type
        let mimeType = Self.mimeType(for: fileURL)

        // Validate parent exists
        try validateParentExists(parentId: parentId, parentType: parentType)

        // Create attachment record
        let attachment = Attachment(
            parentId: parentId,
            parentType: parentType,
            filename: fileURL.lastPathComponent,
            mimeType: mimeType,
            sizeBytes: sizeBytes,
            userId: userId,
            deviceId: deviceId,
            syncState: .pending,
            uploadState: .pending
        )

        // Copy file to attachments directory
        let localPath = try copyFileToAttachmentsDirectory(fileURL: fileURL, attachmentId: attachment.id)
        attachment.localPath = localPath

        // Generate thumbnail for supported image types
        if attachment.supportsThumbnail {
            do {
                let generator = ThumbnailGenerator()
                let thumbnailData = try await generator.generateThumbnail(from: URL(fileURLWithPath: localPath))
                attachment.thumbnailData = thumbnailData
            } catch {
                // Non-fatal: log but continue - thumbnail generation failure shouldn't block attachment creation
                ErrorReportingService.capture(
                    error: error,
                    context: ["attachmentId": attachment.id, "mimeType": mimeType]
                )
            }
        }

        // Insert into context and save - clean up file if save fails
        modelContext.insert(attachment)

        do {
            try await eventService.recordAttachmentAdded(attachment)
            try modelContext.save()
        } catch {
            // Rollback: clean up the copied file since database save failed
            cleanupCopiedFile(at: localPath)
            throw AttachmentServiceError.operationFailed(underlying: error)
        }

        syncManager?.triggerImmediatePush()

        return attachment
    }

    // MARK: - Read

    /// Gets all attachments for a parent entity.
    ///
    /// - Parameters:
    ///   - parentId: The ID of the parent Stack or Task
    ///   - parentType: Whether the parent is a Stack or Task
    /// - Returns: Array of attachments belonging to the parent
    func getAttachments(for parentId: String, parentType: ParentType) throws -> [Attachment] {
        let parentTypeRaw = parentType.rawValue
        let predicate = #Predicate<Attachment> { attachment in
            attachment.parentId == parentId &&
            attachment.parentTypeRawValue == parentTypeRaw &&
            attachment.isDeleted == false
        }
        let descriptor = FetchDescriptor<Attachment>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Gets a single attachment by ID.
    ///
    /// - Parameter id: The attachment ID
    /// - Returns: The attachment if found
    /// - Throws: AttachmentServiceError.attachmentNotFound if not found
    func getAttachment(byId id: String) throws -> Attachment {
        let predicate = #Predicate<Attachment> { attachment in
            attachment.id == id && attachment.isDeleted == false
        }
        let descriptor = FetchDescriptor<Attachment>(predicate: predicate)
        let results = try modelContext.fetch(descriptor)

        guard let attachment = results.first else {
            throw AttachmentServiceError.attachmentNotFound(id: id)
        }

        return attachment
    }

    // MARK: - Update

    /// Updates the upload state of an attachment.
    ///
    /// - Parameters:
    ///   - attachment: The attachment to update
    ///   - state: The new upload state
    ///   - remoteUrl: The remote URL (required when state is .completed)
    func updateUploadState(
        _ attachment: Attachment,
        state: UploadState,
        remoteUrl: String? = nil
    ) throws {
        attachment.uploadState = state
        if let remoteUrl {
            attachment.remoteUrl = remoteUrl
        }
        attachment.updatedAt = Date()
        attachment.syncState = .pending

        try modelContext.save()
    }

    // MARK: - Download

    /// Downloads an attachment from its remote URL to local storage.
    ///
    /// - Parameter attachment: The attachment to download (must have a remoteUrl)
    /// - Returns: The local URL where the file was saved
    /// - Throws: AttachmentServiceError if download fails or no remote URL exists
    func downloadAttachment(_ attachment: Attachment) async throws -> URL {
        guard let remoteUrlString = attachment.remoteUrl,
              let remoteUrl = URL(string: remoteUrlString) else {
            throw AttachmentServiceError.noRemoteUrl(attachmentId: attachment.id)
        }

        // Start the download
        let (_, _) = try await downloadManager.downloadFile(
            from: remoteUrl,
            attachmentId: attachment.id,
            filename: attachment.filename
        )

        // Wait for download to complete
        let localURL = try await downloadManager.waitForCompletion(attachmentId: attachment.id)

        // Update attachment with relative path (container-relocation safe)
        // DownloadManager saves to: Attachments/attachment-id/filename
        attachment.localPath = "\(attachment.id)/\(attachment.filename)"
        attachment.updatedAt = Date()

        // Generate thumbnail for supported image types if not already present
        if attachment.supportsThumbnail && attachment.thumbnailData == nil {
            do {
                let generator = ThumbnailGenerator()
                let thumbnailData = try await generator.generateThumbnail(from: localURL)
                attachment.thumbnailData = thumbnailData
            } catch {
                // Non-fatal: log but continue - thumbnail generation failure shouldn't block download
                ErrorReportingService.capture(
                    error: error,
                    context: ["attachmentId": attachment.id, "mimeType": attachment.mimeType]
                )
            }
        }

        do {
            try modelContext.save()
        } catch {
            // Clean up downloaded file if DB save fails to maintain consistency
            try? fileManager.removeItem(at: localURL.deletingLastPathComponent())
            throw AttachmentServiceError.operationFailed(underlying: error)
        }

        return localURL
    }

    // MARK: - Delete

    /// Soft deletes an attachment.
    ///
    /// - Parameter attachment: The attachment to delete
    func deleteAttachment(_ attachment: Attachment) async throws {
        attachment.isDeleted = true
        attachment.updatedAt = Date()
        attachment.syncState = .pending

        try await eventService.recordAttachmentRemoved(attachment)
        try modelContext.save()
        syncManager?.triggerImmediatePush()

        // Clean up local file using resolved path
        if let resolvedPath = attachment.resolvedLocalPath {
            try? fileManager.removeItem(atPath: resolvedPath)
        }
    }

    /// Deletes all attachments for a parent entity.
    ///
    /// - Parameters:
    ///   - parentId: The ID of the parent Stack or Task
    ///   - parentType: Whether the parent is a Stack or Task
    func deleteAttachments(for parentId: String, parentType: ParentType) async throws {
        let attachments = try getAttachments(for: parentId, parentType: parentType)
        for attachment in attachments {
            try await deleteAttachment(attachment)
        }
    }

    // MARK: - Migration

    /// Migrates all attachments from absolute paths to relative paths.
    ///
    /// This should be called once on app startup to fix attachments that were
    /// stored with absolute paths (which break when iOS relocates the container).
    ///
    /// - Returns: The number of attachments that were migrated
    @discardableResult
    func migrateAttachmentPaths() throws -> Int {
        let descriptor = FetchDescriptor<Attachment>()
        let attachments = try modelContext.fetch(descriptor)

        var migratedCount = 0
        for attachment in attachments where attachment.migrateToRelativePath() {
            migratedCount += 1
        }

        if migratedCount > 0 {
            try modelContext.save()
        }

        return migratedCount
    }

    // MARK: - Private Helpers

    /// Validates that the parent entity exists.
    private func validateParentExists(parentId: String, parentType: ParentType) throws {
        switch parentType {
        case .stack:
            let predicate = #Predicate<Stack> { stack in
                stack.id == parentId && stack.isDeleted == false
            }
            let descriptor = FetchDescriptor<Stack>(predicate: predicate)
            let results = try modelContext.fetch(descriptor)
            guard results.first != nil else {
                throw AttachmentServiceError.parentNotFound(id: parentId, type: parentType)
            }
        case .task:
            let predicate = #Predicate<QueueTask> { task in
                task.id == parentId && task.isDeleted == false
            }
            let descriptor = FetchDescriptor<QueueTask>(predicate: predicate)
            let results = try modelContext.fetch(descriptor)
            guard results.first != nil else {
                throw AttachmentServiceError.parentNotFound(id: parentId, type: parentType)
            }
        case .arc:
            let predicate = #Predicate<Arc> { arc in
                arc.id == parentId && arc.isDeleted == false
            }
            let descriptor = FetchDescriptor<Arc>(predicate: predicate)
            let results = try modelContext.fetch(descriptor)
            guard results.first != nil else {
                throw AttachmentServiceError.parentNotFound(id: parentId, type: parentType)
            }
        }
    }

    /// Copies a file to the attachments directory.
    ///
    /// - Parameters:
    ///   - fileURL: The source file URL
    ///   - attachmentId: The attachment ID (used for directory naming)
    /// - Returns: The relative path to the copied file (e.g., "attachment-id/filename.pdf")
    /// - Note: Returns a relative path to be resilient to iOS container relocation.
    ///         Use `Attachment.resolvedLocalPath` to get the full absolute path at runtime.
    private func copyFileToAttachmentsDirectory(fileURL: URL, attachmentId: String) throws -> String {
        let attachmentsDir = try attachmentsDirectory()
        let attachmentDir = attachmentsDir.appendingPathComponent(attachmentId)

        // Create attachment directory
        try fileManager.createDirectory(at: attachmentDir, withIntermediateDirectories: true)

        // Copy file
        let filename = fileURL.lastPathComponent
        let destinationURL = attachmentDir.appendingPathComponent(filename)
        do {
            try fileManager.copyItem(at: fileURL, to: destinationURL)
        } catch {
            // Clean up the directory we created if copy fails
            try? fileManager.removeItem(at: attachmentDir)
            throw AttachmentServiceError.fileCopyFailed(underlying: error.localizedDescription)
        }

        // Return relative path (container-relocation safe)
        return "\(attachmentId)/\(filename)"
    }

    /// Cleans up a copied file if database operations fail.
    ///
    /// - Parameter localPath: The relative path to the file to clean up
    private func cleanupCopiedFile(at localPath: String) {
        guard let attachmentsDir = try? attachmentsDirectory() else { return }

        // Resolve relative path to absolute path
        let absolutePath: String
        if localPath.hasPrefix("/") {
            absolutePath = localPath
        } else {
            absolutePath = attachmentsDir.appendingPathComponent(localPath).path
        }

        let fileURL = URL(fileURLWithPath: absolutePath)
        // Remove the file and its parent directory (attachment-specific directory)
        try? fileManager.removeItem(at: fileURL.deletingLastPathComponent())
    }

    /// Returns the attachments directory URL, creating it if necessary.
    private func attachmentsDirectory() throws -> URL {
        guard let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw AttachmentServiceError.operationFailed(
                underlying: NSError(domain: "AttachmentService", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "Could not locate Documents directory"
                ])
            )
        }

        let attachmentsDir = documentsDir.appendingPathComponent("Attachments")

        if !fileManager.fileExists(atPath: attachmentsDir.path) {
            try fileManager.createDirectory(at: attachmentsDir, withIntermediateDirectories: true)
        }

        return attachmentsDir
    }

    /// Determines the MIME type for a file URL.
    static func mimeType(for url: URL) -> String {
        if let utType = UTType(filenameExtension: url.pathExtension) {
            return utType.preferredMIMEType ?? "application/octet-stream"
        }
        return "application/octet-stream"
    }
}
