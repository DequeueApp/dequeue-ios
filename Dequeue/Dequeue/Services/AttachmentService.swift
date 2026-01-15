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
        default:
            return false
        }
    }
}

// MARK: - Attachment Service

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

    init(
        modelContext: ModelContext,
        userId: String,
        deviceId: String,
        syncManager: SyncManager? = nil,
        fileManager: FileManager = .default
    ) {
        self.modelContext = modelContext
        self.userId = userId
        self.deviceId = deviceId
        self.eventService = EventService(modelContext: modelContext, userId: userId, deviceId: deviceId)
        self.syncManager = syncManager
        self.fileManager = fileManager
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
    ) throws -> Attachment {
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

        // Insert into context and save - clean up file if save fails
        modelContext.insert(attachment)

        do {
            try eventService.recordAttachmentAdded(attachment)
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

    // MARK: - Delete

    /// Soft deletes an attachment.
    ///
    /// - Parameter attachment: The attachment to delete
    func deleteAttachment(_ attachment: Attachment) throws {
        attachment.isDeleted = true
        attachment.updatedAt = Date()
        attachment.syncState = .pending

        try eventService.recordAttachmentRemoved(attachment)
        try modelContext.save()
        syncManager?.triggerImmediatePush()

        // Clean up local file
        if let localPath = attachment.localPath {
            try? fileManager.removeItem(atPath: localPath)
        }
    }

    /// Deletes all attachments for a parent entity.
    ///
    /// - Parameters:
    ///   - parentId: The ID of the parent Stack or Task
    ///   - parentType: Whether the parent is a Stack or Task
    func deleteAttachments(for parentId: String, parentType: ParentType) throws {
        let attachments = try getAttachments(for: parentId, parentType: parentType)
        for attachment in attachments {
            try deleteAttachment(attachment)
        }
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
        }
    }

    /// Copies a file to the attachments directory.
    ///
    /// - Parameters:
    ///   - fileURL: The source file URL
    ///   - attachmentId: The attachment ID (used for directory naming)
    /// - Returns: The absolute path to the copied file
    private func copyFileToAttachmentsDirectory(fileURL: URL, attachmentId: String) throws -> String {
        let attachmentsDir = try attachmentsDirectory()
        let attachmentDir = attachmentsDir.appendingPathComponent(attachmentId)

        // Create attachment directory
        try fileManager.createDirectory(at: attachmentDir, withIntermediateDirectories: true)

        // Copy file
        let destinationURL = attachmentDir.appendingPathComponent(fileURL.lastPathComponent)
        do {
            try fileManager.copyItem(at: fileURL, to: destinationURL)
        } catch {
            // Clean up the directory we created if copy fails
            try? fileManager.removeItem(at: attachmentDir)
            throw AttachmentServiceError.fileCopyFailed(underlying: error.localizedDescription)
        }

        return destinationURL.path
    }

    /// Cleans up a copied file if database operations fail.
    ///
    /// - Parameter localPath: The path to the file to clean up
    private func cleanupCopiedFile(at localPath: String) {
        let fileURL = URL(fileURLWithPath: localPath)
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
