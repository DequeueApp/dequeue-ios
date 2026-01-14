//
//  AttachmentFileCache.swift
//  Dequeue
//
//  Manages local file caching for attachments in Documents directory
//

import Foundation
import os.log

// MARK: - File Cache Error

enum FileCacheError: LocalizedError, Equatable {
    case fileNotFound(path: String)
    case copyFailed(String)
    case deleteFailed(String)
    case directoryCreationFailed(String)
    case invalidPath

    var errorDescription: String? {
        switch self {
        case let .fileNotFound(path):
            return "File not found at: \(path)"
        case let .copyFailed(message):
            return "Failed to copy file: \(message)"
        case let .deleteFailed(message):
            return "Failed to delete file: \(message)"
        case let .directoryCreationFailed(message):
            return "Failed to create directory: \(message)"
        case .invalidPath:
            return "Invalid file path."
        }
    }
}

// MARK: - Attachment File Cache

/// Actor that manages local file caching for attachments.
///
/// Directory structure:
/// ```
/// Documents/
///   Attachments/
///     {attachmentId}/
///       {original_filename}
///       thumbnail.jpg (if applicable)
/// ```
actor AttachmentFileCache {
    /// The root directory for all cached attachments
    private let cacheDirectory: URL

    /// File manager for file operations
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        // Set up cache directory in Documents
        let documentsDirectory = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first!
        self.cacheDirectory = documentsDirectory.appendingPathComponent("Attachments")

        // Create root directory if needed
        try? fileManager.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
    }

    /// Caches a file for an attachment.
    ///
    /// Copies the source file to the attachment's cache directory, preserving the original filename.
    ///
    /// - Parameters:
    ///   - sourceURL: The source file URL to cache
    ///   - attachmentId: The unique identifier for the attachment
    /// - Returns: The URL of the cached file
    /// - Throws: `FileCacheError` on failure
    func cacheFile(_ sourceURL: URL, for attachmentId: String) throws -> URL {
        // Verify source exists
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw FileCacheError.fileNotFound(path: sourceURL.path)
        }

        // Create attachment directory
        let attachmentDir = cacheDirectory.appendingPathComponent(attachmentId)
        do {
            try fileManager.createDirectory(at: attachmentDir, withIntermediateDirectories: true)
        } catch {
            throw FileCacheError.directoryCreationFailed(error.localizedDescription)
        }

        // Determine destination (preserve original filename)
        let filename = sourceURL.lastPathComponent
        let destinationURL = attachmentDir.appendingPathComponent(filename)

        // Remove existing file if present
        if fileManager.fileExists(atPath: destinationURL.path) {
            try? fileManager.removeItem(at: destinationURL)
        }

        // Copy file
        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            os_log("[AttachmentFileCache] Cached file for \(attachmentId): \(filename)")
            return destinationURL
        } catch {
            throw FileCacheError.copyFailed(error.localizedDescription)
        }
    }

    /// Caches data as a file for an attachment.
    ///
    /// - Parameters:
    ///   - data: The data to write
    ///   - filename: The filename to use
    ///   - attachmentId: The unique identifier for the attachment
    /// - Returns: The URL of the cached file
    /// - Throws: `FileCacheError` on failure
    func cacheData(_ data: Data, filename: String, for attachmentId: String) throws -> URL {
        // Create attachment directory
        let attachmentDir = cacheDirectory.appendingPathComponent(attachmentId)
        do {
            try fileManager.createDirectory(at: attachmentDir, withIntermediateDirectories: true)
        } catch {
            throw FileCacheError.directoryCreationFailed(error.localizedDescription)
        }

        let destinationURL = attachmentDir.appendingPathComponent(filename)

        // Remove existing file if present
        if fileManager.fileExists(atPath: destinationURL.path) {
            try? fileManager.removeItem(at: destinationURL)
        }

        // Write data
        do {
            try data.write(to: destinationURL)
            os_log("[AttachmentFileCache] Cached data for \(attachmentId): \(filename)")
            return destinationURL
        } catch {
            throw FileCacheError.copyFailed(error.localizedDescription)
        }
    }

    /// Returns the cached file URL for an attachment, if it exists.
    ///
    /// - Parameters:
    ///   - attachmentId: The unique identifier for the attachment
    ///   - filename: The filename to look for
    /// - Returns: The URL if the file exists, nil otherwise
    func getCachedFile(for attachmentId: String, filename: String) -> URL? {
        let fileURL = cacheDirectory
            .appendingPathComponent(attachmentId)
            .appendingPathComponent(filename)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        return fileURL
    }

    /// Returns all cached files for an attachment.
    ///
    /// - Parameter attachmentId: The unique identifier for the attachment
    /// - Returns: An array of file URLs in the attachment's directory
    func getAllCachedFiles(for attachmentId: String) -> [URL] {
        let attachmentDir = cacheDirectory.appendingPathComponent(attachmentId)

        guard fileManager.fileExists(atPath: attachmentDir.path) else {
            return []
        }

        do {
            let contents = try fileManager.contentsOfDirectory(
                at: attachmentDir,
                includingPropertiesForKeys: nil
            )
            return contents
        } catch {
            return []
        }
    }

    /// Removes the cached file for an attachment.
    ///
    /// - Parameter attachmentId: The unique identifier for the attachment
    /// - Throws: `FileCacheError` on failure
    func removeCachedFile(for attachmentId: String) throws {
        let attachmentDir = cacheDirectory.appendingPathComponent(attachmentId)

        guard fileManager.fileExists(atPath: attachmentDir.path) else {
            // Already doesn't exist, nothing to do
            return
        }

        do {
            try fileManager.removeItem(at: attachmentDir)
            os_log("[AttachmentFileCache] Removed cache for \(attachmentId)")
        } catch {
            throw FileCacheError.deleteFailed(error.localizedDescription)
        }
    }

    /// Clears all cached files.
    ///
    /// - Throws: `FileCacheError` on failure
    func clearCache() throws {
        guard fileManager.fileExists(atPath: cacheDirectory.path) else {
            return
        }

        do {
            try fileManager.removeItem(at: cacheDirectory)
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            os_log("[AttachmentFileCache] Cleared all cache")
        } catch {
            throw FileCacheError.deleteFailed(error.localizedDescription)
        }
    }

    /// Calculates the total size of all cached files.
    ///
    /// - Returns: The total size in bytes
    func getCacheSize() -> Int64 {
        var totalSize: Int64 = 0

        guard let enumerator = fileManager.enumerator(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                if let size = resourceValues.fileSize {
                    totalSize += Int64(size)
                }
            } catch {
                // Skip files we can't read
                continue
            }
        }

        return totalSize
    }

    /// Returns a human-readable string of the cache size.
    func getFormattedCacheSize() -> String {
        let size = getCacheSize()
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    /// Returns the number of cached attachments.
    func getCachedAttachmentCount() -> Int {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return 0
        }

        return contents.filter { url in
            var isDirectory: ObjCBool = false
            fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
            return isDirectory.boolValue
        }.count
    }

    /// Returns the root cache directory URL.
    var rootDirectory: URL {
        cacheDirectory
    }

    /// Checks if a cached file exists for an attachment.
    func fileExists(for attachmentId: String, filename: String) -> Bool {
        getCachedFile(for: attachmentId, filename: filename) != nil
    }
}

// MARK: - Mock Implementation

/// Mock implementation for testing
actor MockAttachmentFileCache {
    var cacheFileCallCount = 0
    var cacheDataCallCount = 0
    var removeCallCount = 0
    var clearCallCount = 0
    var mockError: FileCacheError?

    private var cachedFiles: [String: [String: URL]] = [:]
    private var mockCacheSize: Int64 = 0

    func cacheFile(_ sourceURL: URL, for attachmentId: String) throws -> URL {
        cacheFileCallCount += 1

        if let error = mockError {
            throw error
        }

        let filename = sourceURL.lastPathComponent
        let mockURL = URL(fileURLWithPath: "/mock/cache/\(attachmentId)/\(filename)")

        if cachedFiles[attachmentId] == nil {
            cachedFiles[attachmentId] = [:]
        }
        cachedFiles[attachmentId]?[filename] = mockURL

        return mockURL
    }

    func cacheData(_ data: Data, filename: String, for attachmentId: String) throws -> URL {
        cacheDataCallCount += 1

        if let error = mockError {
            throw error
        }

        let mockURL = URL(fileURLWithPath: "/mock/cache/\(attachmentId)/\(filename)")

        if cachedFiles[attachmentId] == nil {
            cachedFiles[attachmentId] = [:]
        }
        cachedFiles[attachmentId]?[filename] = mockURL

        return mockURL
    }

    func getCachedFile(for attachmentId: String, filename: String) -> URL? {
        cachedFiles[attachmentId]?[filename]
    }

    func removeCachedFile(for attachmentId: String) throws {
        removeCallCount += 1

        if let error = mockError {
            throw error
        }

        cachedFiles.removeValue(forKey: attachmentId)
    }

    func clearCache() throws {
        clearCallCount += 1

        if let error = mockError {
            throw error
        }

        cachedFiles.removeAll()
    }

    func getCacheSize() -> Int64 {
        mockCacheSize
    }

    func setMockCacheSize(_ size: Int64) {
        mockCacheSize = size
    }

    func setMockError(_ error: FileCacheError?) {
        mockError = error
    }
}
