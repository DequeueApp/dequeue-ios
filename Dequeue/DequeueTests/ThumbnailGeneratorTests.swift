//
//  ThumbnailGeneratorTests.swift
//  DequeueTests
//
//  Tests for image thumbnail generation
//

import Testing
import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@testable import Dequeue

struct ThumbnailGeneratorTests {
    let generator = ThumbnailGenerator()

    // MARK: - MIME Type Support

    @Test("Supported MIME types are recognized")
    func supportedMimeTypes() async throws {
        #expect(ThumbnailGenerator.isSupported(mimeType: "image/jpeg"))
        #expect(ThumbnailGenerator.isSupported(mimeType: "image/png"))
        #expect(ThumbnailGenerator.isSupported(mimeType: "image/gif"))
        #expect(ThumbnailGenerator.isSupported(mimeType: "image/heic"))
        #expect(ThumbnailGenerator.isSupported(mimeType: "image/heif"))
        #expect(ThumbnailGenerator.isSupported(mimeType: "image/webp"))
    }

    @Test("Unsupported MIME types are rejected")
    func unsupportedMimeTypes() async throws {
        #expect(!ThumbnailGenerator.isSupported(mimeType: "application/pdf"))
        #expect(!ThumbnailGenerator.isSupported(mimeType: "text/plain"))
        #expect(!ThumbnailGenerator.isSupported(mimeType: "video/mp4"))
    }

    // MARK: - Thumbnail Generation from Data

    @Test("Generate thumbnail from JPEG data")
    func generateFromJPEGData() async throws {
        // Create a simple test image
        let testImage = createTestImage(size: CGSize(width: 500, height: 500))
        #if canImport(UIKit)
        let imageData = testImage.jpegData(compressionQuality: 1.0)!
        #elseif canImport(AppKit)
        let tiffData = testImage.tiffRepresentation!
        let bitmapRep = NSBitmapImageRep(data: tiffData)!
        let imageData = bitmapRep.representation(
            using: .jpeg,
            properties: [.compressionFactor: 1.0]
        )!
        #endif

        let thumbnailData = try await generator.generateThumbnail(
            from: imageData,
            mimeType: "image/jpeg"
        )

        // Verify thumbnail was generated
        #expect(thumbnailData.count > 0)

        // Verify it's valid image data
        #if canImport(UIKit)
        let thumbnail = UIImage(data: thumbnailData)
        #expect(thumbnail != nil)
        #elseif canImport(AppKit)
        let thumbnail = NSImage(data: thumbnailData)
        #expect(thumbnail != nil)
        #endif
    }

    @Test("Generate thumbnail from PNG data")
    func generateFromPNGData() async throws {
        let testImage = createTestImage(size: CGSize(width: 500, height: 500))
        #if canImport(UIKit)
        let imageData = testImage.pngData()!
        #elseif canImport(AppKit)
        let tiffData = testImage.tiffRepresentation!
        let bitmapRep = NSBitmapImageRep(data: tiffData)!
        let imageData = bitmapRep.representation(using: .png)!
        #endif

        let thumbnailData = try await generator.generateThumbnail(
            from: imageData,
            mimeType: "image/png"
        )

        #expect(thumbnailData.count > 0)
    }

    // MARK: - Size & Quality

    @Test("Thumbnail respects max dimension")
    func thumbnailSizeLimit() async throws {
        // Create a large test image (1000x1000)
        let testImage = createTestImage(size: CGSize(width: 1000, height: 1000))
        #if canImport(UIKit)
        let imageData = testImage.jpegData(compressionQuality: 1.0)!
        #elseif canImport(AppKit)
        let tiffData = testImage.tiffRepresentation!
        let bitmapRep = NSBitmapImageRep(data: tiffData)!
        let imageData = bitmapRep.representation(
            using: .jpeg,
            properties: [.compressionFactor: 1.0]
        )!
        #endif

        let thumbnailData = try await generator.generateThumbnail(
            from: imageData,
            mimeType: "image/jpeg"
        )

        // Load thumbnail and verify size
        #if canImport(UIKit)
        let thumbnail = UIImage(data: thumbnailData)!
        let size = thumbnail.size
        #elseif canImport(AppKit)
        let thumbnail = NSImage(data: thumbnailData)!
        let size = thumbnail.size
        #endif

        // Should be scaled down to fit 200x200
        #expect(size.width <= 200)
        #expect(size.height <= 200)
    }

    @Test("Small images are not upscaled")
    func smallImageNotUpscaled() async throws {
        // Create a small image (100x100)
        let testImage = createTestImage(size: CGSize(width: 100, height: 100))
        #if canImport(UIKit)
        let imageData = testImage.jpegData(compressionQuality: 1.0)!
        #elseif canImport(AppKit)
        let tiffData = testImage.tiffRepresentation!
        let bitmapRep = NSBitmapImageRep(data: tiffData)!
        let imageData = bitmapRep.representation(
            using: .jpeg,
            properties: [.compressionFactor: 1.0]
        )!
        #endif

        let thumbnailData = try await generator.generateThumbnail(
            from: imageData,
            mimeType: "image/jpeg"
        )

        #if canImport(UIKit)
        let thumbnail = UIImage(data: thumbnailData)!
        let size = thumbnail.size
        #elseif canImport(AppKit)
        let thumbnail = NSImage(data: thumbnailData)!
        let size = thumbnail.size
        #endif

        // Should remain ~100x100 (not upscaled to 200x200)
        #expect(size.width <= 100)
        #expect(size.height <= 100)
    }

    @Test("Aspect ratio is maintained")
    func aspectRatioMaintained() async throws {
        // Create a rectangular image (800x400 - 2:1 aspect ratio)
        let testImage = createTestImage(size: CGSize(width: 800, height: 400))
        #if canImport(UIKit)
        let imageData = testImage.jpegData(compressionQuality: 1.0)!
        #elseif canImport(AppKit)
        let tiffData = testImage.tiffRepresentation!
        let bitmapRep = NSBitmapImageRep(data: tiffData)!
        let imageData = bitmapRep.representation(
            using: .jpeg,
            properties: [.compressionFactor: 1.0]
        )!
        #endif

        let thumbnailData = try await generator.generateThumbnail(
            from: imageData,
            mimeType: "image/jpeg"
        )

        #if canImport(UIKit)
        let thumbnail = UIImage(data: thumbnailData)!
        let size = thumbnail.size
        #elseif canImport(AppKit)
        let thumbnail = NSImage(data: thumbnailData)!
        let size = thumbnail.size
        #endif

        // Should be ~200x100 maintaining 2:1 aspect ratio
        let aspectRatio = size.width / size.height
        #expect(abs(aspectRatio - 2.0) < 0.1)  // Allow small floating point variance
    }

    // MARK: - Error Handling

    @Test("Reject unsupported MIME type")
    func rejectUnsupportedMimeType() async throws {
        let testData = Data("test".utf8)

        await #expect(throws: ThumbnailGeneratorError.self) {
            try await generator.generateThumbnail(from: testData, mimeType: "application/pdf")
        }
    }

    @Test("Handle corrupted image data gracefully")
    func handleCorruptedImage() async throws {
        let corruptData = Data("not an image".utf8)

        await #expect(throws: ThumbnailGeneratorError.self) {
            try await generator.generateThumbnail(from: corruptData, mimeType: "image/jpeg")
        }
    }

    // MARK: - Helper Methods

    private func createTestImage(size: CGSize) -> PlatformImage {
        #if canImport(UIKit)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        #elseif canImport(AppKit)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.blue.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return image
        #endif
    }
}

// MARK: - Platform Image Typealias

#if canImport(UIKit)
private typealias PlatformImage = UIImage
#elseif canImport(AppKit)
private typealias PlatformImage = NSImage
#endif
