//
//  AttachmentFileCacheTests.swift
//  DequeueTests
//
//  Tests for AttachmentFileCache file operations
//

import Testing
import Foundation
@testable import Dequeue

@Suite("AttachmentFileCache Tests")
@MainActor
struct AttachmentFileCacheTests {
    // MARK: - FileCacheError Tests

    @Test("FileCacheError has descriptive messages")
    func errorHasDescriptiveMessages() {
        let errors: [FileCacheError] = [
            .fileNotFound(path: "/path/to/file"),
            .copyFailed("Permission denied"),
            .deleteFailed("File in use"),
            .directoryCreationFailed("Disk full"),
            .invalidPath
        ]

        for error in errors {
            #expect(error.errorDescription != nil)
            if let description = error.errorDescription {
                #expect(!description.isEmpty)
            }
        }
    }

    @Test("FileCacheError equality works correctly")
    func errorEquality() {
        #expect(FileCacheError.invalidPath == FileCacheError.invalidPath)
        #expect(FileCacheError.fileNotFound(path: "/a") == FileCacheError.fileNotFound(path: "/a"))
        #expect(FileCacheError.fileNotFound(path: "/a") != FileCacheError.fileNotFound(path: "/b"))
        #expect(FileCacheError.copyFailed("a") == FileCacheError.copyFailed("a"))
        #expect(FileCacheError.invalidPath != FileCacheError.copyFailed("error"))
    }

    // MARK: - Real Cache Tests

    @Test("Cache creates root directory")
    func cacheCreatesRootDirectory() async {
        let cache = AttachmentFileCache()
        let rootDir = await cache.rootDirectory

        #expect(FileManager.default.fileExists(atPath: rootDir.path))
    }

    @Test("Cache returns nil for non-existent file")
    func cacheReturnsNilForMissingFile() async {
        let cache = AttachmentFileCache()

        let result = await cache.getCachedFile(for: "nonexistent", filename: "file.txt")

        #expect(result == nil)
    }

    @Test("Cache reports false for non-existent file")
    func cacheReportsFileNotExists() async {
        let cache = AttachmentFileCache()

        let exists = await cache.fileExists(for: "nonexistent", filename: "file.txt")

        #expect(!exists)
    }

    @Test("Cache returns empty array for non-existent attachment")
    func cacheReturnsEmptyForNonexistentAttachment() async {
        let cache = AttachmentFileCache()

        let files = await cache.getAllCachedFiles(for: "nonexistent")

        #expect(files.isEmpty)
    }

    @Test("Cache remove handles non-existent attachment gracefully")
    func cacheRemoveNonexistent() async throws {
        let cache = AttachmentFileCache()

        // Should not throw
        try await cache.removeCachedFile(for: "nonexistent")
    }

    @Test("Cache can cache and retrieve file")
    func cacheCachesAndRetrievesFile() async throws {
        let cache = AttachmentFileCache()
        let attachmentId = "test-\(UUID().uuidString)"

        // Create a temporary file
        let tempDir = FileManager.default.temporaryDirectory
        let sourceURL = tempDir.appendingPathComponent("test-source.txt")
        try "Test content".write(to: sourceURL, atomically: true, encoding: .utf8)

        defer {
            // Cleanup
            try? FileManager.default.removeItem(at: sourceURL)
            Task { try? await cache.removeCachedFile(for: attachmentId) }
        }

        // Cache the file
        let cachedURL = try await cache.cacheFile(sourceURL, for: attachmentId)

        #expect(FileManager.default.fileExists(atPath: cachedURL.path))
        #expect(cachedURL.lastPathComponent == "test-source.txt")

        // Verify we can retrieve it
        let retrieved = await cache.getCachedFile(for: attachmentId, filename: "test-source.txt")
        #expect(retrieved == cachedURL)
    }

    @Test("Cache can cache data directly")
    func cacheCachesData() async throws {
        let cache = AttachmentFileCache()
        let attachmentId = "test-\(UUID().uuidString)"
        let testData = try #require("Hello, World!".data(using: .utf8))

        defer {
            Task { try? await cache.removeCachedFile(for: attachmentId) }
        }

        let cachedURL = try await cache.cacheData(testData, filename: "test.txt", for: attachmentId)

        #expect(FileManager.default.fileExists(atPath: cachedURL.path))

        let readBack = try Data(contentsOf: cachedURL)
        #expect(readBack == testData)
    }

    @Test("Cache throws for non-existent source file")
    func cacheThrowsForMissingSource() async {
        let cache = AttachmentFileCache()
        let nonexistentURL = URL(fileURLWithPath: "/nonexistent/path/file.txt")

        await #expect(throws: FileCacheError.self) {
            _ = try await cache.cacheFile(nonexistentURL, for: "test-id")
        }
    }

    @Test("Cache size calculation works")
    func cacheSizeCalculation() async throws {
        let cache = AttachmentFileCache()
        let attachmentId = "test-size-\(UUID().uuidString)"
        let testData = Data(repeating: 0x42, count: 1_024) // 1KB

        defer {
            Task { try? await cache.removeCachedFile(for: attachmentId) }
        }

        let sizeBefore = await cache.getCacheSize()

        _ = try await cache.cacheData(testData, filename: "test.bin", for: attachmentId)

        let sizeAfter = await cache.getCacheSize()

        #expect(sizeAfter >= sizeBefore + 1_024)
    }

    @Test("Cache formatted size returns non-empty string")
    func cacheFormattedSize() async {
        let cache = AttachmentFileCache()

        let formatted = await cache.getFormattedCacheSize()

        #expect(!formatted.isEmpty)
    }

    @Test("Cache attachment count works")
    func cacheAttachmentCount() async throws {
        let cache = AttachmentFileCache()
        let attachmentId1 = "test-count-1-\(UUID().uuidString)"
        let attachmentId2 = "test-count-2-\(UUID().uuidString)"
        let testData = Data([0x01, 0x02, 0x03])

        defer {
            Task {
                try? await cache.removeCachedFile(for: attachmentId1)
                try? await cache.removeCachedFile(for: attachmentId2)
            }
        }

        let countBefore = await cache.getCachedAttachmentCount()

        _ = try await cache.cacheData(testData, filename: "file1.bin", for: attachmentId1)
        _ = try await cache.cacheData(testData, filename: "file2.bin", for: attachmentId2)

        let countAfter = await cache.getCachedAttachmentCount()

        #expect(countAfter >= countBefore + 2)
    }

    // MARK: - MockAttachmentFileCache Tests

    @Test("Mock tracks cache file calls")
    func mockTracksCacheFileCalls() async throws {
        let mock = MockAttachmentFileCache()
        let fileURL = URL(fileURLWithPath: "/tmp/test.txt")

        _ = try await mock.cacheFile(fileURL, for: "test-123")

        let callCount = await mock.cacheFileCallCount
        #expect(callCount == 1)
    }

    @Test("Mock tracks cache data calls")
    func mockTracksCacheDataCalls() async throws {
        let mock = MockAttachmentFileCache()
        let testData = Data([0x01])

        _ = try await mock.cacheData(testData, filename: "test.bin", for: "test-123")

        let callCount = await mock.cacheDataCallCount
        #expect(callCount == 1)
    }

    @Test("Mock throws mock error")
    func mockThrowsError() async {
        let mock = MockAttachmentFileCache()
        await mock.setMockError(.invalidPath)
        let fileURL = URL(fileURLWithPath: "/tmp/test.txt")

        await #expect(throws: FileCacheError.self) {
            _ = try await mock.cacheFile(fileURL, for: "test-123")
        }
    }

    @Test("Mock stores and retrieves cached files")
    func mockStoresAndRetrieves() async throws {
        let mock = MockAttachmentFileCache()
        let fileURL = URL(fileURLWithPath: "/tmp/test.txt")

        let cachedURL = try await mock.cacheFile(fileURL, for: "test-123")

        let retrieved = await mock.getCachedFile(for: "test-123", filename: "test.txt")
        #expect(retrieved == cachedURL)
    }

    @Test("Mock tracks remove calls")
    func mockTracksRemoveCalls() async throws {
        let mock = MockAttachmentFileCache()

        _ = try await mock.cacheData(Data(), filename: "f.txt", for: "test-123")
        try await mock.removeCachedFile(for: "test-123")

        let removeCount = await mock.removeCallCount
        #expect(removeCount == 1)

        let retrieved = await mock.getCachedFile(for: "test-123", filename: "f.txt")
        #expect(retrieved == nil)
    }

    @Test("Mock tracks clear calls")
    func mockTracksClearCalls() async throws {
        let mock = MockAttachmentFileCache()

        try await mock.clearCache()

        let clearCount = await mock.clearCallCount
        #expect(clearCount == 1)
    }

    @Test("Mock returns configured cache size")
    func mockReturnsCacheSize() async {
        let mock = MockAttachmentFileCache()
        await mock.setMockCacheSize(1_048_576) // 1MB

        let size = await mock.getCacheSize()
        #expect(size == 1_048_576)
    }
}
