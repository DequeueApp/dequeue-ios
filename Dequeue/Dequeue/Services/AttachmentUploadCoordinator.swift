//
//  AttachmentUploadCoordinator.swift
//  Dequeue
//
//  Orchestrates the complete attachment upload flow: presigned URL → upload → state update
//

import Foundation
import SwiftData
import SwiftUI
import os

private let logger = Logger(subsystem: "com.dequeue", category: "AttachmentUploadCoordinator")

// MARK: - Environment Key

private struct AttachmentUploadCoordinatorKey: EnvironmentKey {
    static let defaultValue: AttachmentUploadCoordinator? = nil
}

extension EnvironmentValues {
    var attachmentUploadCoordinator: AttachmentUploadCoordinator? {
        get { self[AttachmentUploadCoordinatorKey.self] }
        set { self[AttachmentUploadCoordinatorKey.self] = newValue }
    }
}

// MARK: - Upload Coordinator

/// Orchestrates the complete attachment upload flow.
/// This coordinator connects AttachmentService (local record creation) with
/// AttachmentUploadService (cloud upload) to provide a unified upload experience.
@MainActor
@Observable
final class AttachmentUploadCoordinator {
    private let modelContext: ModelContext
    private let uploadService: AttachmentUploadServiceProtocol
    private let fileManager: FileManager

    /// Tracks currently uploading attachments
    private(set) var uploadingAttachments: Set<String> = []

    init(
        modelContext: ModelContext,
        uploadService: AttachmentUploadServiceProtocol,
        fileManager: FileManager = .default
    ) {
        self.modelContext = modelContext
        self.uploadService = uploadService
        self.fileManager = fileManager
    }

    /// Uploads an attachment that was created with a pending state.
    /// This method orchestrates the complete upload flow:
    /// 1. Validates local file exists
    /// 2. Updates state to .uploading
    /// 3. Requests presigned URL from backend
    /// 4. Uploads file to presigned URL
    /// 5. Updates attachment with download URL and .completed state
    ///
    /// - Parameter attachment: The attachment to upload (must have localPath set)
    /// - Throws: AttachmentUploadError if any step fails
    func uploadAttachment(_ attachment: Attachment) async throws {
        let attachmentId = attachment.id

        // Prevent duplicate uploads
        guard !uploadingAttachments.contains(attachmentId) else {
            logger.warning("Attachment \(attachmentId) is already being uploaded")
            return
        }

        uploadingAttachments.insert(attachmentId)
        defer { uploadingAttachments.remove(attachmentId) }

        logger.info("Starting upload for attachment: \(attachmentId)")

        // Step 1: Validate local file exists
        guard let localPath = attachment.localPath else {
            logger.error("Attachment \(attachmentId) has no local path")
            throw AttachmentUploadError.noLocalFile
        }

        let fileURL = URL(fileURLWithPath: localPath)
        guard fileManager.fileExists(atPath: localPath) else {
            logger.error("Local file not found at: \(localPath)")
            throw AttachmentUploadError.fileNotFound(localPath)
        }

        // Step 2: Update state to uploading
        attachment.uploadState = .uploading
        try modelContext.save()

        do {
            // Step 3: Request presigned upload URL
            logger.debug("Requesting presigned URL for: \(attachment.filename)")
            let presignedInfo = try await uploadService.requestPresignedUploadURL(
                filename: attachment.filename,
                mimeType: attachment.mimeType,
                sizeBytes: attachment.sizeBytes
            )

            // Step 4: Read file data and upload
            logger.debug("Reading file data from: \(localPath)")
            let fileData = try Data(contentsOf: fileURL)

            logger.debug("Uploading \(fileData.count) bytes to presigned URL")
            try await uploadService.uploadToPresignedURL(
                data: fileData,
                presignedURL: presignedInfo.uploadUrl,
                mimeType: attachment.mimeType
            )

            // Step 5: Update attachment with success state
            attachment.remoteUrl = presignedInfo.downloadUrl.absoluteString
            attachment.uploadState = .completed
            attachment.updatedAt = Date()
            try modelContext.save()

            logger.info("Upload completed for attachment: \(attachmentId)")
        } catch {
            // Handle upload failure
            logger.error("Upload failed for \(attachmentId): \(error.localizedDescription)")
            attachment.uploadState = .failed
            attachment.updatedAt = Date()
            try? modelContext.save()

            throw error
        }
    }

    /// Retries a failed upload
    func retryUpload(_ attachment: Attachment) async throws {
        guard attachment.uploadState == .failed else {
            logger.warning("Cannot retry upload - attachment is not in failed state")
            return
        }

        // Reset to pending and try again
        attachment.uploadState = .pending
        try modelContext.save()

        try await uploadAttachment(attachment)
    }
}
