//
//  ThumbnailGenerator.swift
//  Dequeue
//
//  Generates thumbnails for image attachments
//

import Foundation
import os.log

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Thumbnail Generator Errors

enum ThumbnailGeneratorError: LocalizedError {
    case unsupportedFormat(mimeType: String)
    case failedToLoadImage(url: URL)
    case failedToCreateThumbnail
    case failedToCompressImage
    case fileTooLarge(size: Int64, maxSize: Int64)

    var errorDescription: String? {
        switch self {
        case let .unsupportedFormat(mimeType):
            return "Unsupported image format: \(mimeType)"
        case let .failedToLoadImage(url):
            return "Failed to load image from: \(url.lastPathComponent)"
        case .failedToCreateThumbnail:
            return "Failed to create thumbnail"
        case .failedToCompressImage:
            return "Failed to compress thumbnail image"
        case let .fileTooLarge(size, maxSize):
            let formatter = ByteCountFormatter()
            // swiftlint:disable:next line_length
            return "File too large (\(formatter.string(fromByteCount: size))) - max \(formatter.string(fromByteCount: maxSize))"
        }
    }
}

// MARK: - Thumbnail Configuration

struct ThumbnailConfiguration {
    /// Maximum dimension (width or height) for the thumbnail
    let maxDimension: CGFloat

    /// JPEG compression quality (0.0 to 1.0)
    let compressionQuality: CGFloat

    /// Maximum source file size to process (in bytes)
    let maxSourceFileSize: Int64

    static let `default` = ThumbnailConfiguration(
        maxDimension: 200,
        compressionQuality: 0.7,
        maxSourceFileSize: 100 * 1_024 * 1_024  // 100 MB
    )
}

// MARK: - Thumbnail Generator

/// Generates thumbnails for image attachments on a background thread
actor ThumbnailGenerator {
    private let configuration: ThumbnailConfiguration
    private let logger = Logger(subsystem: "com.dequeue", category: "ThumbnailGenerator")

    /// Supported image MIME types
    static let supportedMimeTypes: Set<String> = [
        "image/jpeg",
        "image/png",
        "image/gif",
        "image/heic",
        "image/heif",
        "image/webp"
    ]

    init(configuration: ThumbnailConfiguration = .default) {
        self.configuration = configuration
    }

    /// Check if a MIME type is supported for thumbnail generation
    static func isSupported(mimeType: String) -> Bool {
        supportedMimeTypes.contains(mimeType.lowercased())
    }

    /// Generate a thumbnail from a local image file
    /// - Parameter imageURL: URL to the local image file
    /// - Returns: JPEG data for the thumbnail
    func generateThumbnail(from imageURL: URL) async throws -> Data {
        logger.debug("Generating thumbnail for: \(imageURL.lastPathComponent)")

        // Validate file exists and check size
        let attributes = try FileManager.default.attributesOfItem(atPath: imageURL.path)
        guard let fileSize = attributes[.size] as? Int64 else {
            throw ThumbnailGeneratorError.failedToLoadImage(url: imageURL)
        }

        if fileSize > configuration.maxSourceFileSize {
            throw ThumbnailGeneratorError.fileTooLarge(
                size: fileSize,
                maxSize: configuration.maxSourceFileSize
            )
        }

        // Load and process image
        let thumbnailData = try await loadAndResizeImage(from: imageURL)

        logger.debug("Generated thumbnail: \(thumbnailData.count) bytes")
        return thumbnailData
    }

    /// Generate thumbnail from raw image data (for images not yet saved to disk)
    /// - Parameters:
    ///   - data: Raw image data
    ///   - mimeType: MIME type of the image
    /// - Returns: JPEG data for the thumbnail
    func generateThumbnail(from data: Data, mimeType: String) async throws -> Data {
        guard Self.isSupported(mimeType: mimeType) else {
            throw ThumbnailGeneratorError.unsupportedFormat(mimeType: mimeType)
        }

        if Int64(data.count) > configuration.maxSourceFileSize {
            throw ThumbnailGeneratorError.fileTooLarge(
                size: Int64(data.count),
                maxSize: configuration.maxSourceFileSize
            )
        }

        #if canImport(UIKit)
        guard let image = UIImage(data: data) else {
            throw ThumbnailGeneratorError.failedToCreateThumbnail
        }
        return try resizeAndCompress(image: image)
        #elseif canImport(AppKit)
        guard let image = NSImage(data: data) else {
            throw ThumbnailGeneratorError.failedToCreateThumbnail
        }
        return try resizeAndCompress(image: image)
        #endif
    }

    // MARK: - Private Methods

    private func loadAndResizeImage(from url: URL) async throws -> Data {
        #if canImport(UIKit)
        guard let image = UIImage(contentsOfFile: url.path) else {
            throw ThumbnailGeneratorError.failedToLoadImage(url: url)
        }
        return try resizeAndCompress(image: image)
        #elseif canImport(AppKit)
        guard let image = NSImage(contentsOf: url) else {
            throw ThumbnailGeneratorError.failedToLoadImage(url: url)
        }
        return try resizeAndCompress(image: image)
        #endif
    }

    #if canImport(UIKit)
    private func resizeAndCompress(image: UIImage) throws -> Data {
        let originalSize = image.size
        let targetSize = calculateTargetSize(for: originalSize)

        // Create resized image using UIGraphicsImageRenderer for efficiency
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        // Compress as JPEG
        guard let jpegData = resizedImage.jpegData(compressionQuality: configuration.compressionQuality) else {
            throw ThumbnailGeneratorError.failedToCompressImage
        }

        return jpegData
    }
    #elseif canImport(AppKit)
    private func resizeAndCompress(image: NSImage) throws -> Data {
        let originalSize = image.size
        let targetSize = calculateTargetSize(for: originalSize)

        // Create new image with target size
        let resizedImage = NSImage(size: targetSize)
        resizedImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: CGRect(origin: .zero, size: targetSize),
            from: CGRect(origin: .zero, size: originalSize),
            operation: .copy,
            fraction: 1.0
        )
        resizedImage.unlockFocus()

        // Convert to JPEG
        guard let tiffData = resizedImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapRep.representation(
                  using: .jpeg,
                  properties: [.compressionFactor: configuration.compressionQuality]
              ) else {
            throw ThumbnailGeneratorError.failedToCompressImage
        }

        return jpegData
    }
    #endif

    /// Calculate the target size maintaining aspect ratio
    private func calculateTargetSize(for originalSize: CGSize) -> CGSize {
        let maxDim = configuration.maxDimension

        // If image is already smaller than max, keep original size
        if originalSize.width <= maxDim && originalSize.height <= maxDim {
            return originalSize
        }

        let widthRatio = maxDim / originalSize.width
        let heightRatio = maxDim / originalSize.height
        let scaleFactor = min(widthRatio, heightRatio)

        return CGSize(
            width: floor(originalSize.width * scaleFactor),
            height: floor(originalSize.height * scaleFactor)
        )
    }
}

// MARK: - Attachment Extension

extension Attachment {
    /// Returns true if this attachment supports thumbnail generation
    var supportsThumbnail: Bool {
        ThumbnailGenerator.isSupported(mimeType: mimeType)
    }
}
