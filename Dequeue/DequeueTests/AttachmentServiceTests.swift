//
//  AttachmentServiceTests.swift
//  DequeueTests
//
//  Tests for AttachmentService - file attachment CRUD operations (DEQ-72)
//

import Testing
import SwiftData
import Foundation
@testable import Dequeue

// MARK: - Test Helpers

/// Creates an in-memory model container for AttachmentService tests
private func makeTestContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: Stack.self,
        QueueTask.self,
        Reminder.self,
        Event.self,
        Attachment.self,
        Tag.self,
        Device.self,
        configurations: config
    )
}

/// Creates a temporary test file with the given content
private func createTemporaryFile(
    named filename: String = "test-file.txt",
    content: String = "Test file content"
) throws -> URL {
    let tempDir = FileManager.default.temporaryDirectory
    let fileURL = tempDir.appendingPathComponent(UUID().uuidString).appendingPathComponent(filename)
    try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try content.data(using: .utf8)?.write(to: fileURL)
    return fileURL
}

/// Cleans up temporary test files
private func cleanupTemporaryFile(_ url: URL) {
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

@Suite("AttachmentService Tests", .serialized)
struct AttachmentServiceTests {
    // MARK: - Create Attachment Tests

    @Test("createAttachment creates attachment for stack")
    @MainActor
    func createAttachmentForStack() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        let fileURL = try createTemporaryFile(named: "document.txt", content: "Hello, World!")
        defer { cleanupTemporaryFile(fileURL) }

        let service = AttachmentService(modelContext: context, userId: "test-user", deviceId: "test-device")
        let attachment = try service.createAttachment(for: stack.id, parentType: .stack, fileURL: fileURL)

        #expect(attachment.parentId == stack.id)
        #expect(attachment.parentType == .stack)
        #expect(attachment.filename == "document.txt")
        #expect(attachment.mimeType == "text/plain")
        #expect(attachment.sizeBytes > 0)
        #expect(attachment.uploadState == .pending)
        #expect(attachment.syncState == .pending)
        #expect(attachment.localPath != nil)
    }

    @Test("createAttachment creates attachment for task")
    @MainActor
    func createAttachmentForTask() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        let task = QueueTask(title: "Test Task", stack: stack)
        context.insert(task)
        try context.save()

        let fileURL = try createTemporaryFile(named: "notes.txt")
        defer { cleanupTemporaryFile(fileURL) }

        let service = AttachmentService(modelContext: context, userId: "test-user", deviceId: "test-device")
        let attachment = try service.createAttachment(for: task.id, parentType: .task, fileURL: fileURL)

        #expect(attachment.parentId == task.id)
        #expect(attachment.parentType == .task)
        #expect(attachment.filename == "notes.txt")
    }

    @Test("createAttachment throws for non-existent parent stack")
    @MainActor
    func createAttachmentThrowsForMissingStack() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let fileURL = try createTemporaryFile()
        defer { cleanupTemporaryFile(fileURL) }

        let service = AttachmentService(modelContext: context, userId: "test-user", deviceId: "test-device")

        #expect(throws: AttachmentServiceError.self) {
            _ = try service.createAttachment(for: "non-existent-id", parentType: .stack, fileURL: fileURL)
        }
    }

    @Test("createAttachment throws for non-existent parent task")
    @MainActor
    func createAttachmentThrowsForMissingTask() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let fileURL = try createTemporaryFile()
        defer { cleanupTemporaryFile(fileURL) }

        let service = AttachmentService(modelContext: context, userId: "test-user", deviceId: "test-device")

        #expect(throws: AttachmentServiceError.self) {
            _ = try service.createAttachment(for: "non-existent-id", parentType: .task, fileURL: fileURL)
        }
    }

    @Test("createAttachment throws for missing file")
    @MainActor
    func createAttachmentThrowsForMissingFile() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        let nonExistentURL = URL(fileURLWithPath: "/tmp/non-existent-file.txt")
        let service = AttachmentService(modelContext: context, userId: "test-user", deviceId: "test-device")

        #expect(throws: AttachmentServiceError.self) {
            _ = try service.createAttachment(for: stack.id, parentType: .stack, fileURL: nonExistentURL)
        }
    }

    @Test("createAttachment throws for file exceeding size limit")
    @MainActor
    func createAttachmentThrowsForOversizedFile() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        // Create a mock file manager that reports a large file size
        let mockFileManager = MockFileManager(reportedFileSize: 60 * 1024 * 1024) // 60 MB
        let service = AttachmentService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device",
            fileManager: mockFileManager
        )

        // Create a real file but use mock file manager to report large size
        let fileURL = try createTemporaryFile()
        defer { cleanupTemporaryFile(fileURL) }
        mockFileManager.existingPaths.insert(fileURL.path)

        #expect(throws: AttachmentServiceError.self) {
            _ = try service.createAttachment(for: stack.id, parentType: .stack, fileURL: fileURL)
        }
    }

    @Test("createAttachment records event")
    @MainActor
    func createAttachmentRecordsEvent() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        let fileURL = try createTemporaryFile()
        defer { cleanupTemporaryFile(fileURL) }

        let service = AttachmentService(modelContext: context, userId: "test-user", deviceId: "test-device")
        let attachment = try service.createAttachment(for: stack.id, parentType: .stack, fileURL: fileURL)

        // Check that an event was recorded
        let eventDescriptor = FetchDescriptor<Event>(
            predicate: #Predicate { $0.entityId == attachment.id }
        )
        let events = try context.fetch(eventDescriptor)
        #expect(events.count == 1)
        #expect(events.first?.type == EventType.attachmentAdded.rawValue)
    }

    // MARK: - Read Attachment Tests

    @Test("getAttachments returns attachments for parent")
    @MainActor
    func getAttachmentsForParent() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        let service = AttachmentService(modelContext: context, userId: "test-user", deviceId: "test-device")

        // Create multiple attachments
        let file1 = try createTemporaryFile(named: "file1.txt")
        let file2 = try createTemporaryFile(named: "file2.txt")
        defer {
            cleanupTemporaryFile(file1)
            cleanupTemporaryFile(file2)
        }

        _ = try service.createAttachment(for: stack.id, parentType: .stack, fileURL: file1)
        _ = try service.createAttachment(for: stack.id, parentType: .stack, fileURL: file2)

        let attachments = try service.getAttachments(for: stack.id, parentType: .stack)
        #expect(attachments.count == 2)
    }

    @Test("getAttachments excludes deleted attachments")
    @MainActor
    func getAttachmentsExcludesDeleted() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        let service = AttachmentService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let file1 = try createTemporaryFile(named: "file1.txt")
        let file2 = try createTemporaryFile(named: "file2.txt")
        defer {
            cleanupTemporaryFile(file1)
            cleanupTemporaryFile(file2)
        }

        let attachment1 = try service.createAttachment(for: stack.id, parentType: .stack, fileURL: file1)
        _ = try service.createAttachment(for: stack.id, parentType: .stack, fileURL: file2)

        // Delete one attachment
        try service.deleteAttachment(attachment1)

        let attachments = try service.getAttachments(for: stack.id, parentType: .stack)
        #expect(attachments.count == 1)
    }

    @Test("getAttachment returns attachment by ID")
    @MainActor
    func getAttachmentById() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        let fileURL = try createTemporaryFile()
        defer { cleanupTemporaryFile(fileURL) }

        let service = AttachmentService(modelContext: context, userId: "test-user", deviceId: "test-device")
        let created = try service.createAttachment(for: stack.id, parentType: .stack, fileURL: fileURL)

        let fetched = try service.getAttachment(byId: created.id)
        #expect(fetched.id == created.id)
    }

    @Test("getAttachment throws for non-existent ID")
    @MainActor
    func getAttachmentThrowsForMissingId() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let service = AttachmentService(modelContext: context, userId: "test-user", deviceId: "test-device")

        #expect(throws: AttachmentServiceError.self) {
            _ = try service.getAttachment(byId: "non-existent-id")
        }
    }

    // MARK: - Update Attachment Tests

    @Test("updateUploadState updates state correctly")
    @MainActor
    func updateUploadState() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        let fileURL = try createTemporaryFile()
        defer { cleanupTemporaryFile(fileURL) }

        let service = AttachmentService(modelContext: context, userId: "test-user", deviceId: "test-device")
        let attachment = try service.createAttachment(for: stack.id, parentType: .stack, fileURL: fileURL)

        try service.updateUploadState(attachment, state: .uploading)
        #expect(attachment.uploadState == .uploading)

        try service.updateUploadState(attachment, state: .completed, remoteUrl: "https://example.com/file.txt")
        #expect(attachment.uploadState == .completed)
        #expect(attachment.remoteUrl == "https://example.com/file.txt")
    }

    // MARK: - Delete Attachment Tests

    @Test("deleteAttachment soft deletes attachment")
    @MainActor
    func deleteAttachmentSoftDeletes() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        let fileURL = try createTemporaryFile()
        defer { cleanupTemporaryFile(fileURL) }

        let service = AttachmentService(modelContext: context, userId: "test-user", deviceId: "test-device")
        let attachment = try service.createAttachment(for: stack.id, parentType: .stack, fileURL: fileURL)

        try service.deleteAttachment(attachment)

        #expect(attachment.isDeleted == true)
    }

    @Test("deleteAttachment records event")
    @MainActor
    func deleteAttachmentRecordsEvent() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        let fileURL = try createTemporaryFile()
        defer { cleanupTemporaryFile(fileURL) }

        let service = AttachmentService(modelContext: context, userId: "test-user", deviceId: "test-device")
        let attachment = try service.createAttachment(for: stack.id, parentType: .stack, fileURL: fileURL)
        let attachmentId = attachment.id

        try service.deleteAttachment(attachment)

        // Check for removal event
        let eventDescriptor = FetchDescriptor<Event>(
            predicate: #Predicate { $0.entityId == attachmentId && $0.type == "attachment.removed" }
        )
        let events = try context.fetch(eventDescriptor)
        #expect(events.count == 1)
    }

    @Test("deleteAttachments deletes all attachments for parent")
    @MainActor
    func deleteAttachmentsForParent() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let stack = Stack(title: "Test Stack")
        context.insert(stack)
        try context.save()

        let service = AttachmentService(modelContext: context, userId: "test-user", deviceId: "test-device")

        let file1 = try createTemporaryFile(named: "file1.txt")
        let file2 = try createTemporaryFile(named: "file2.txt")
        defer {
            cleanupTemporaryFile(file1)
            cleanupTemporaryFile(file2)
        }

        _ = try service.createAttachment(for: stack.id, parentType: .stack, fileURL: file1)
        _ = try service.createAttachment(for: stack.id, parentType: .stack, fileURL: file2)

        try service.deleteAttachments(for: stack.id, parentType: .stack)

        let attachments = try service.getAttachments(for: stack.id, parentType: .stack)
        #expect(attachments.isEmpty)
    }

    // MARK: - MIME Type Tests

    @Test("mimeType returns correct type for common extensions")
    func mimeTypeForCommonExtensions() {
        #expect(AttachmentService.mimeType(for: URL(fileURLWithPath: "/test.txt")) == "text/plain")
        #expect(AttachmentService.mimeType(for: URL(fileURLWithPath: "/test.pdf")) == "application/pdf")
        #expect(AttachmentService.mimeType(for: URL(fileURLWithPath: "/test.jpg")) == "image/jpeg")
        #expect(AttachmentService.mimeType(for: URL(fileURLWithPath: "/test.png")) == "image/png")
        #expect(AttachmentService.mimeType(for: URL(fileURLWithPath: "/test.json")) == "application/json")
    }

    @Test("mimeType returns octet-stream for unknown extensions")
    func mimeTypeForUnknownExtension() {
        #expect(AttachmentService.mimeType(for: URL(fileURLWithPath: "/test.xyz123")) == "application/octet-stream")
    }
}

// MARK: - Mock FileManager for Testing

/// A mock FileManager that allows controlling file existence and size for testing
private class MockFileManager: FileManager {
    var existingPaths: Set<String> = []
    let reportedFileSize: Int64

    init(reportedFileSize: Int64 = 1024) {
        self.reportedFileSize = reportedFileSize
        super.init()
    }

    override func fileExists(atPath path: String) -> Bool {
        existingPaths.contains(path)
    }

    override func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        guard existingPaths.contains(path) else {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)
        }
        return [.size: reportedFileSize]
    }

    // Allow directory creation to succeed
    override func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]? = nil
    ) throws {
        // No-op for testing
    }

    // Allow file copy to succeed
    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        // No-op for testing
    }
}
