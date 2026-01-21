//
//  AttachmentTests.swift
//  DequeueTests
//
//  Tests for Attachment model
//

import Testing
import SwiftData
import Foundation
@testable import Dequeue

// Disambiguate from Swift Testing's Attachment type
private typealias Attachment = Dequeue.Attachment

/// Simple error type for test assertions
private struct TestError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

@Suite("Attachment Model Tests")
struct AttachmentTests {
    @Test("Attachment initializes with default values")
    func attachmentInitializesWithDefaults() {
        let attachment = Attachment(
            parentId: "stack-123",
            parentType: .stack,
            filename: "document.pdf",
            mimeType: "application/pdf",
            sizeBytes: 1024
        )

        #expect(!attachment.id.isEmpty)
        #expect(attachment.parentId == "stack-123")
        #expect(attachment.parentType == .stack)
        #expect(attachment.filename == "document.pdf")
        #expect(attachment.mimeType == "application/pdf")
        #expect(attachment.sizeBytes == 1024)
        #expect(attachment.remoteUrl == nil)
        #expect(attachment.localPath == nil)
        #expect(attachment.thumbnailData == nil)
        #expect(attachment.previewUrl == nil)
        #expect(attachment.isDeleted == false)
        #expect(attachment.userId == nil)
        #expect(attachment.deviceId == nil)
        #expect(attachment.syncState == .pending)
        #expect(attachment.uploadState == .pending)
        #expect(attachment.lastSyncedAt == nil)
        #expect(attachment.serverId == nil)
        #expect(attachment.revision == 1)
    }

    @Test("Attachment initializes with custom values")
    func attachmentInitializesWithCustomValues() {
        let id = "att-custom-123"
        let now = Date()
        let thumbnailData = Data([0x89, 0x50, 0x4E, 0x47])

        let attachment = Attachment(
            id: id,
            parentId: "task-456",
            parentType: .task,
            filename: "photo.jpg",
            mimeType: "image/jpeg",
            sizeBytes: 2_048_576,
            remoteUrl: "https://r2.example.com/attachments/photo.jpg",
            localPath: "/Documents/Attachments/att-123/photo.jpg",
            thumbnailData: thumbnailData,
            previewUrl: "https://r2.example.com/previews/photo_thumb.jpg",
            createdAt: now,
            updatedAt: now,
            isDeleted: false,
            userId: "user-123",
            deviceId: "device-456",
            syncState: .synced,
            uploadState: .completed,
            lastSyncedAt: now,
            serverId: "server-789",
            revision: 3
        )

        #expect(attachment.id == id)
        #expect(attachment.parentId == "task-456")
        #expect(attachment.parentType == .task)
        #expect(attachment.filename == "photo.jpg")
        #expect(attachment.mimeType == "image/jpeg")
        #expect(attachment.sizeBytes == 2_048_576)
        #expect(attachment.remoteUrl == "https://r2.example.com/attachments/photo.jpg")
        #expect(attachment.localPath == "/Documents/Attachments/att-123/photo.jpg")
        #expect(attachment.thumbnailData == thumbnailData)
        #expect(attachment.previewUrl == "https://r2.example.com/previews/photo_thumb.jpg")
        #expect(attachment.userId == "user-123")
        #expect(attachment.deviceId == "device-456")
        #expect(attachment.syncState == .synced)
        #expect(attachment.uploadState == .completed)
        #expect(attachment.lastSyncedAt == now)
        #expect(attachment.serverId == "server-789")
        #expect(attachment.revision == 3)
    }

    // MARK: - Convenience Properties

    @Test("formattedSize returns human-readable sizes")
    func formattedSizeReturnsReadableSizes() {
        let smallFile = Attachment(
            parentId: "stack-1",
            parentType: .stack,
            filename: "tiny.txt",
            mimeType: "text/plain",
            sizeBytes: 512
        )
        #expect(smallFile.formattedSize.contains("KB") || smallFile.formattedSize.contains("bytes"))

        let mediumFile = Attachment(
            parentId: "stack-1",
            parentType: .stack,
            filename: "medium.pdf",
            mimeType: "application/pdf",
            sizeBytes: 2_500_000
        )
        #expect(mediumFile.formattedSize.contains("MB"))

        let largeFile = Attachment(
            parentId: "stack-1",
            parentType: .stack,
            filename: "large.zip",
            mimeType: "application/zip",
            sizeBytes: 1_500_000_000
        )
        #expect(largeFile.formattedSize.contains("GB"))
    }

    @Test("isImage correctly identifies image MIME types")
    func isImageIdentifiesImageTypes() {
        let jpeg = Attachment(
            parentId: "stack-1",
            parentType: .stack,
            filename: "photo.jpg",
            mimeType: "image/jpeg",
            sizeBytes: 1024
        )
        #expect(jpeg.isImage == true)

        let png = Attachment(
            parentId: "stack-1",
            parentType: .stack,
            filename: "screenshot.png",
            mimeType: "image/png",
            sizeBytes: 1024
        )
        #expect(png.isImage == true)

        let pdf = Attachment(
            parentId: "stack-1",
            parentType: .stack,
            filename: "document.pdf",
            mimeType: "application/pdf",
            sizeBytes: 1024
        )
        #expect(pdf.isImage == false)
    }

    @Test("isPDF correctly identifies PDF files")
    func isPDFIdentifiesPDFFiles() {
        let pdf = Attachment(
            parentId: "stack-1",
            parentType: .stack,
            filename: "document.pdf",
            mimeType: "application/pdf",
            sizeBytes: 1024
        )
        #expect(pdf.isPDF == true)

        let jpeg = Attachment(
            parentId: "stack-1",
            parentType: .stack,
            filename: "photo.jpg",
            mimeType: "image/jpeg",
            sizeBytes: 1024
        )
        #expect(jpeg.isPDF == false)
    }

    @Test("fileExtension extracts extension correctly")
    func fileExtensionExtractsCorrectly() {
        let pdf = Attachment(
            parentId: "stack-1",
            parentType: .stack,
            filename: "document.pdf",
            mimeType: "application/pdf",
            sizeBytes: 1024
        )
        #expect(pdf.fileExtension == "pdf")

        let jpeg = Attachment(
            parentId: "stack-1",
            parentType: .stack,
            filename: "My Photo.JPEG",
            mimeType: "image/jpeg",
            sizeBytes: 1024
        )
        #expect(jpeg.fileExtension == "jpeg")

        let noExtension = Attachment(
            parentId: "stack-1",
            parentType: .stack,
            filename: "README",
            mimeType: "text/plain",
            sizeBytes: 1024
        )
        #expect(noExtension.fileExtension == nil)
    }

    @Test("isAvailableLocally returns false when localPath is nil")
    func isAvailableLocallyReturnsFalseWhenNil() {
        let attachment = Attachment(
            parentId: "stack-1",
            parentType: .stack,
            filename: "file.pdf",
            mimeType: "application/pdf",
            sizeBytes: 1024
        )
        #expect(attachment.isAvailableLocally == false)
    }

    @Test("isAvailableLocally returns false for paths outside Attachments directory")
    func isAvailableLocallyRejectsUnsafePaths() {
        // Security: Path traversal should be rejected
        let maliciousPath = Attachment(
            parentId: "stack-1",
            parentType: .stack,
            filename: "file.pdf",
            mimeType: "application/pdf",
            sizeBytes: 1024,
            localPath: "/etc/passwd"
        )
        #expect(maliciousPath.isAvailableLocally == false)

        // Relative path (not starting with expected prefix)
        let relativePath = Attachment(
            parentId: "stack-1",
            parentType: .stack,
            filename: "file.pdf",
            mimeType: "application/pdf",
            sizeBytes: 1024,
            localPath: "Documents/Attachments/file.pdf"
        )
        #expect(relativePath.isAvailableLocally == false)
    }

    @Test("isAvailableLocally returns true for valid existing file")
    func isAvailableLocallyReturnsTrueForExistingFile() throws {
        let fileManager = FileManager.default

        // Create the Attachments directory in Documents
        guard let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw TestError("Could not get documents directory")
        }

        let attachmentsDir = documentsDir.appendingPathComponent("Attachments")
        let testDir = attachmentsDir.appendingPathComponent("test-attachment")

        try fileManager.createDirectory(at: testDir, withIntermediateDirectories: true)

        let testFile = testDir.appendingPathComponent("test-file.pdf")
        try Data("test content".utf8).write(to: testFile)

        defer {
            try? fileManager.removeItem(at: testDir)
        }

        let attachment = Attachment(
            parentId: "stack-1",
            parentType: .stack,
            filename: "test-file.pdf",
            mimeType: "application/pdf",
            sizeBytes: 1024,
            localPath: testFile.path
        )
        #expect(attachment.isAvailableLocally == true)
    }

    @Test("isAvailableLocally returns false for non-existent file in valid path")
    func isAvailableLocallyReturnsFalseForMissingFile() {
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }

        let fakePath = documentsDir
            .appendingPathComponent("Attachments")
            .appendingPathComponent("non-existent")
            .appendingPathComponent("missing.pdf")
            .path

        let attachment = Attachment(
            parentId: "stack-1",
            parentType: .stack,
            filename: "missing.pdf",
            mimeType: "application/pdf",
            sizeBytes: 1024,
            localPath: fakePath
        )
        #expect(attachment.isAvailableLocally == false)
    }

    @Test("isUploaded returns correct state")
    func isUploadedReturnsCorrectState() {
        let pending = Attachment(
            parentId: "stack-1",
            parentType: .stack,
            filename: "file.pdf",
            mimeType: "application/pdf",
            sizeBytes: 1024,
            uploadState: .pending
        )
        #expect(pending.isUploaded == false)

        let uploading = Attachment(
            parentId: "stack-1",
            parentType: .stack,
            filename: "file.pdf",
            mimeType: "application/pdf",
            sizeBytes: 1024,
            uploadState: .uploading
        )
        #expect(uploading.isUploaded == false)

        let completedNoUrl = Attachment(
            parentId: "stack-1",
            parentType: .stack,
            filename: "file.pdf",
            mimeType: "application/pdf",
            sizeBytes: 1024,
            uploadState: .completed
        )
        #expect(completedNoUrl.isUploaded == false)

        let completedWithUrl = Attachment(
            parentId: "stack-1",
            parentType: .stack,
            filename: "file.pdf",
            mimeType: "application/pdf",
            sizeBytes: 1024,
            remoteUrl: "https://r2.example.com/file.pdf",
            uploadState: .completed
        )
        #expect(completedWithUrl.isUploaded == true)
    }

    // MARK: - SwiftData Integration

    @Test("Attachment persists in SwiftData")
    func attachmentPersistsInSwiftData() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Attachment.self, configurations: config)
        let context = ModelContext(container)

        let attachment = Attachment(
            parentId: "stack-123",
            parentType: .stack,
            filename: "test.pdf",
            mimeType: "application/pdf",
            sizeBytes: 5000
        )
        let attachmentId = attachment.id

        context.insert(attachment)
        try context.save()

        let descriptor = FetchDescriptor<Attachment>(
            predicate: #Predicate { $0.id == attachmentId }
        )
        let fetched = try context.fetch(descriptor)

        #expect(fetched.count == 1)
        #expect(fetched.first?.filename == "test.pdf")
        #expect(fetched.first?.parentId == "stack-123")
        #expect(fetched.first?.parentType == .stack)
    }

    @Test("Multiple attachments can be fetched by parentId")
    func multipleAttachmentsCanBeFetchedByParentId() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Attachment.self, configurations: config)
        let context = ModelContext(container)

        let stackId = "stack-456"

        let attachment1 = Attachment(
            parentId: stackId,
            parentType: .stack,
            filename: "file1.pdf",
            mimeType: "application/pdf",
            sizeBytes: 1000
        )
        let attachment2 = Attachment(
            parentId: stackId,
            parentType: .stack,
            filename: "file2.jpg",
            mimeType: "image/jpeg",
            sizeBytes: 2000
        )
        let attachment3 = Attachment(
            parentId: "other-stack",
            parentType: .stack,
            filename: "file3.png",
            mimeType: "image/png",
            sizeBytes: 3000
        )

        context.insert(attachment1)
        context.insert(attachment2)
        context.insert(attachment3)
        try context.save()

        let descriptor = FetchDescriptor<Attachment>(
            predicate: #Predicate { $0.parentId == stackId && !$0.isDeleted }
        )
        let fetched = try context.fetch(descriptor)

        #expect(fetched.count == 2)
    }

}

// MARK: - Path Migration & Resolution Tests

@Suite("Attachment Path Migration Tests")
struct AttachmentPathMigrationTests {
    @Test("migrateToRelativePath converts absolute path to relative")
    func migrateToRelativePathConvertsAbsolutePath() {
        let attachment = Attachment(
            parentId: "stack-1",
            parentType: .stack,
            filename: "document.pdf",
            mimeType: "application/pdf",
            sizeBytes: 1024,
            localPath: "/var/mobile/Containers/Data/Application/ABC-123/Documents/Attachments/att-456/document.pdf"
        )

        let migrated = attachment.migrateToRelativePath()

        #expect(migrated == true)
        #expect(attachment.localPath == "att-456/document.pdf")
    }

    @Test("migrateToRelativePath does not modify already relative path")
    func migrateToRelativePathSkipsRelativePath() {
        let attachment = Attachment(
            parentId: "stack-1",
            parentType: .stack,
            filename: "document.pdf",
            mimeType: "application/pdf",
            sizeBytes: 1024,
            localPath: "att-456/document.pdf"
        )

        let migrated = attachment.migrateToRelativePath()

        #expect(migrated == false)
        #expect(attachment.localPath == "att-456/document.pdf")
    }

    @Test("migrateToRelativePath returns false for nil localPath")
    func migrateToRelativePathHandlesNil() {
        let attachment = Attachment(
            parentId: "stack-1",
            parentType: .stack,
            filename: "document.pdf",
            mimeType: "application/pdf",
            sizeBytes: 1024
        )

        let migrated = attachment.migrateToRelativePath()

        #expect(migrated == false)
        #expect(attachment.localPath == nil)
    }

    @Test("migrateToRelativePath handles path with multiple Attachments directories")
    func migrateToRelativePathHandlesMultipleAttachmentsDirectories() {
        // Edge case: path contains /Attachments/ multiple times (e.g., nested backup scenario)
        let attachment = Attachment(
            parentId: "stack-1",
            parentType: .stack,
            filename: "document.pdf",
            mimeType: "application/pdf",
            sizeBytes: 1024,
            localPath: "/Users/backup/Attachments/old/restore/Documents/Attachments/att-789/document.pdf"
        )

        let migrated = attachment.migrateToRelativePath()

        #expect(migrated == true)
        // Should use the LAST /Attachments/ occurrence (the actual attachments directory)
        #expect(attachment.localPath == "att-789/document.pdf")
    }

    @Test("migrateToRelativePath returns false for path without Attachments directory")
    func migrateToRelativePathHandlesNoAttachmentsDir() {
        let attachment = Attachment(
            parentId: "stack-1",
            parentType: .stack,
            filename: "document.pdf",
            mimeType: "application/pdf",
            sizeBytes: 1024,
            localPath: "/var/mobile/Documents/Other/document.pdf"
        )

        let migrated = attachment.migrateToRelativePath()

        #expect(migrated == false)
        #expect(attachment.localPath == "/var/mobile/Documents/Other/document.pdf")
    }

    @Test("resolvedLocalPath resolves relative path to full path")
    func resolvedLocalPathResolvesRelativePath() {
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }

        let attachment = Attachment(
            parentId: "stack-1",
            parentType: .stack,
            filename: "document.pdf",
            mimeType: "application/pdf",
            sizeBytes: 1024,
            localPath: "att-123/document.pdf"
        )

        let expectedPath = documentsDir
            .appendingPathComponent("Attachments")
            .appendingPathComponent("att-123/document.pdf")
            .path

        #expect(attachment.resolvedLocalPath == expectedPath)
    }

    @Test("resolvedLocalPath returns absolute path unchanged")
    func resolvedLocalPathReturnsAbsolutePathUnchanged() {
        let absolutePath = "/var/mobile/Documents/Attachments/att-123/document.pdf"

        let attachment = Attachment(
            parentId: "stack-1",
            parentType: .stack,
            filename: "document.pdf",
            mimeType: "application/pdf",
            sizeBytes: 1024,
            localPath: absolutePath
        )

        #expect(attachment.resolvedLocalPath == absolutePath)
    }

    @Test("resolvedLocalPath returns nil for nil localPath")
    func resolvedLocalPathReturnsNilForNilPath() {
        let attachment = Attachment(
            parentId: "stack-1",
            parentType: .stack,
            filename: "document.pdf",
            mimeType: "application/pdf",
            sizeBytes: 1024
        )

        #expect(attachment.resolvedLocalPath == nil)
    }

    @Test("resolvedLocalPath blocks path traversal attempts")
    func resolvedLocalPathBlocksPathTraversal() {
        // Security: Attempt to escape attachments directory with ..
        let attachment = Attachment(
            parentId: "stack-1",
            parentType: .stack,
            filename: "document.pdf",
            mimeType: "application/pdf",
            sizeBytes: 1024,
            localPath: "../../../etc/passwd"
        )

        #expect(attachment.resolvedLocalPath == nil)
    }

    @Test("resolvedLocalPath blocks embedded path traversal")
    func resolvedLocalPathBlocksEmbeddedPathTraversal() {
        // Security: Path traversal embedded in middle of path
        let attachment = Attachment(
            parentId: "stack-1",
            parentType: .stack,
            filename: "document.pdf",
            mimeType: "application/pdf",
            sizeBytes: 1024,
            localPath: "att-123/../../../etc/passwd"
        )

        #expect(attachment.resolvedLocalPath == nil)
    }

    @Test("isAvailableLocally works with relative paths")
    func isAvailableLocallyWorksWithRelativePaths() throws {
        let fileManager = FileManager.default

        guard let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            Issue.record("Could not get documents directory")
            return
        }

        let attachmentsDir = documentsDir.appendingPathComponent("Attachments")
        let testDir = attachmentsDir.appendingPathComponent("relative-test")

        try fileManager.createDirectory(at: testDir, withIntermediateDirectories: true)

        let testFile = testDir.appendingPathComponent("test-file.pdf")
        try Data("test content".utf8).write(to: testFile)

        defer {
            try? fileManager.removeItem(at: testDir)
        }

        // Use relative path (new format)
        let attachment = Attachment(
            parentId: "stack-1",
            parentType: .stack,
            filename: "test-file.pdf",
            mimeType: "application/pdf",
            sizeBytes: 1024,
            localPath: "relative-test/test-file.pdf"
        )

        #expect(attachment.isAvailableLocally == true)
    }
}
