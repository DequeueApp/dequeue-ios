//
//  ThumbnailGeneratorTests.swift
//  DequeueTests
//
//  Tests for ThumbnailGenerator service
//

import Testing
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
@testable import Dequeue

@Suite("ThumbnailGenerator Tests")
struct ThumbnailGeneratorTests {

    // MARK: - MIME Type Support Tests

    @Test("Supported MIME types are recognized")
    func supportedMimeTypesRecognized() {
        let supportedTypes = [
            "image/jpeg",
            "image/png",
            "image/gif",
            "image/heic",
            "image/heif",
            "image/webp"
        ]

        for mimeType in supportedTypes {
            #expect(ThumbnailGenerator.isSupported(mimeType: mimeType),
                    "Expected \(mimeType) to be supported")
        }
    }

    @Test("Unsupported MIME types are rejected")
    func unsupportedMimeTypesRejected() {
        let unsupportedTypes = [
            "application/pdf",
            "video/mp4",
            "audio/mpeg",
            "text/plain",
            "image/svg+xml",
            "application/octet-stream"
        ]

        for mimeType in unsupportedTypes {
            #expect(!ThumbnailGenerator.isSupported(mimeType: mimeType),
                    "Expected \(mimeType) to not be supported")
        }
    }

    @Test("MIME type check is case-insensitive")
    func mimeTypeCaseInsensitive() {
        #expect(ThumbnailGenerator.isSupported(mimeType: "IMAGE/JPEG"))
        #expect(ThumbnailGenerator.isSupported(mimeType: "Image/Png"))
        #expect(ThumbnailGenerator.isSupported(mimeType: "IMAGE/GIF"))
    }

    // MARK: - Attachment Extension Tests

    @Test("Attachment supportsThumbnail returns true for images")
    func attachmentSupportsThumbnailForImages() {
        let imageAttachment = Attachment(
            parentId: "test",
            parentType: .stack,
            filename: "photo.jpg",
            mimeType: "image/jpeg",
            sizeBytes: 1024
        )

        #expect(imageAttachment.supportsThumbnail)
    }

    @Test("Attachment supportsThumbnail returns false for non-images")
    func attachmentDoesNotSupportThumbnailForNonImages() {
        let pdfAttachment = Attachment(
            parentId: "test",
            parentType: .stack,
            filename: "document.pdf",
            mimeType: "application/pdf",
            sizeBytes: 1024
        )

        #expect(!pdfAttachment.supportsThumbnail)
    }

    // MARK: - Thumbnail Generation Tests

    @Test("Generate thumbnail from valid image data")
    func generateThumbnailFromValidData() async throws {
        let generator = ThumbnailGenerator()

        // Create a simple test image
        let testImage = createTestImage(width: 400, height: 300)
        guard let imageData = imageToJPEGData(testImage) else {
            throw TestError("Failed to create test image data")
        }

        let thumbnailData = try await generator.generateThumbnail(
            from: imageData,
            mimeType: "image/jpeg"
        )

        // Verify thumbnail was generated
        #expect(!thumbnailData.isEmpty)

        // Verify thumbnail is smaller than original
        #expect(thumbnailData.count < imageData.count)

        // Verify thumbnail is valid JPEG (starts with JPEG magic bytes)
        #expect(thumbnailData[0] == 0xFF)
        #expect(thumbnailData[1] == 0xD8)
    }

    @Test("Generate thumbnail respects max dimension")
    func thumbnailRespectsMaxDimension() async throws {
        let config = ThumbnailConfiguration(
            maxDimension: 100,
            compressionQuality: 0.7,
            maxSourceFileSize: 50 * 1024 * 1024
        )
        let generator = ThumbnailGenerator(configuration: config)

        // Create large test image
        let testImage = createTestImage(width: 1000, height: 800)
        guard let imageData = imageToJPEGData(testImage) else {
            throw TestError("Failed to create test image data")
        }

        let thumbnailData = try await generator.generateThumbnail(
            from: imageData,
            mimeType: "image/jpeg"
        )

        // Load the thumbnail and verify dimensions
        guard let thumbnail = dataToImage(thumbnailData) else {
            throw TestError("Failed to load thumbnail image")
        }

        let thumbnailSize = imageSize(thumbnail)
        #expect(thumbnailSize.width <= 100)
        #expect(thumbnailSize.height <= 100)
    }

    @Test("Generate thumbnail maintains aspect ratio")
    func thumbnailMaintainsAspectRatio() async throws {
        let config = ThumbnailConfiguration(
            maxDimension: 200,
            compressionQuality: 0.7,
            maxSourceFileSize: 50 * 1024 * 1024
        )
        let generator = ThumbnailGenerator(configuration: config)

        // Create wide test image (4:3 ratio)
        let testImage = createTestImage(width: 800, height: 600)
        guard let imageData = imageToJPEGData(testImage) else {
            throw TestError("Failed to create test image data")
        }

        let thumbnailData = try await generator.generateThumbnail(
            from: imageData,
            mimeType: "image/jpeg"
        )

        guard let thumbnail = dataToImage(thumbnailData) else {
            throw TestError("Failed to load thumbnail image")
        }

        let thumbnailSize = imageSize(thumbnail)

        // Verify aspect ratio is maintained (with small tolerance for rounding)
        let originalRatio = 800.0 / 600.0
        let thumbnailRatio = thumbnailSize.width / thumbnailSize.height
        let ratioDifference = abs(originalRatio - thumbnailRatio)

        #expect(ratioDifference < 0.05, "Aspect ratio should be maintained")
    }

    @Test("Small images are not upscaled")
    func smallImagesNotUpscaled() async throws {
        let config = ThumbnailConfiguration(
            maxDimension: 200,
            compressionQuality: 0.7,
            maxSourceFileSize: 50 * 1024 * 1024
        )
        let generator = ThumbnailGenerator(configuration: config)

        // Create small test image (smaller than max dimension)
        let testImage = createTestImage(width: 100, height: 80)
        guard let imageData = imageToJPEGData(testImage) else {
            throw TestError("Failed to create test image data")
        }

        let thumbnailData = try await generator.generateThumbnail(
            from: imageData,
            mimeType: "image/jpeg"
        )

        guard let thumbnail = dataToImage(thumbnailData) else {
            throw TestError("Failed to load thumbnail image")
        }

        let thumbnailSize = imageSize(thumbnail)

        // Verify image was not upscaled
        #expect(thumbnailSize.width <= 100)
        #expect(thumbnailSize.height <= 80)
    }

    @Test("Rejects unsupported MIME types")
    func rejectsUnsupportedMimeTypes() async throws {
        let generator = ThumbnailGenerator()

        // Create some data (doesn't matter what it is)
        let data = Data([0x00, 0x01, 0x02, 0x03])

        await #expect(throws: ThumbnailGeneratorError.self) {
            try await generator.generateThumbnail(
                from: data,
                mimeType: "application/pdf"
            )
        }
    }

    @Test("Rejects files exceeding size limit")
    func rejectsOversizedFiles() async throws {
        let config = ThumbnailConfiguration(
            maxDimension: 200,
            compressionQuality: 0.7,
            maxSourceFileSize: 1024  // Very small limit for testing
        )
        let generator = ThumbnailGenerator(configuration: config)

        // Create data larger than limit
        let largeData = Data(count: 2048)

        await #expect(throws: ThumbnailGeneratorError.self) {
            try await generator.generateThumbnail(
                from: largeData,
                mimeType: "image/jpeg"
            )
        }
    }

    @Test("Handles invalid image data gracefully")
    func handlesInvalidImageData() async throws {
        let generator = ThumbnailGenerator()

        // Create invalid image data
        let invalidData = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05])

        await #expect(throws: ThumbnailGeneratorError.self) {
            try await generator.generateThumbnail(
                from: invalidData,
                mimeType: "image/jpeg"
            )
        }
    }

    // MARK: - PNG Support Tests

    @Test("Generate thumbnail from PNG data")
    func generateThumbnailFromPNG() async throws {
        let generator = ThumbnailGenerator()

        let testImage = createTestImage(width: 400, height: 300)
        guard let imageData = imageToPNGData(testImage) else {
            throw TestError("Failed to create test PNG data")
        }

        let thumbnailData = try await generator.generateThumbnail(
            from: imageData,
            mimeType: "image/png"
        )

        // Verify thumbnail was generated as JPEG
        #expect(!thumbnailData.isEmpty)
        #expect(thumbnailData[0] == 0xFF)  // JPEG magic byte
        #expect(thumbnailData[1] == 0xD8)
    }

    // MARK: - File-based Tests

    @Test("Generate thumbnail from temporary file")
    func generateThumbnailFromFile() async throws {
        let generator = ThumbnailGenerator()

        // Create test image and save to temp file
        let testImage = createTestImage(width: 500, height: 400)
        guard let imageData = imageToJPEGData(testImage) else {
            throw TestError("Failed to create test image data")
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_image_\(UUID().uuidString).jpg")

        try imageData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let thumbnailData = try await generator.generateThumbnail(from: tempURL)

        #expect(!thumbnailData.isEmpty)
        #expect(thumbnailData.count < imageData.count)
    }

    @Test("Rejects non-existent file")
    func rejectsNonExistentFile() async throws {
        let generator = ThumbnailGenerator()

        let fakeURL = URL(fileURLWithPath: "/nonexistent/path/image.jpg")

        await #expect(throws: Error.self) {
            try await generator.generateThumbnail(from: fakeURL)
        }
    }

    // MARK: - Helper Methods

    private func createTestImage(width: Int, height: Int) -> PlatformImage {
        #if canImport(UIKit)
        let size = CGSize(width: width, height: height)
        // Use scale=1.0 for consistent test behavior across devices
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill()
            context.fill(CGRect(x: 10, y: 10, width: width - 20, height: height - 20))
        }
        #elseif canImport(AppKit)
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.blue.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSColor.white.setFill()
        NSRect(x: 10, y: 10, width: width - 20, height: height - 20).fill()
        image.unlockFocus()
        return image
        #endif
    }

    private func imageToJPEGData(_ image: PlatformImage) -> Data? {
        #if canImport(UIKit)
        return image.jpegData(compressionQuality: 0.9)
        #elseif canImport(AppKit)
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
        #endif
    }

    private func imageToPNGData(_ image: PlatformImage) -> Data? {
        #if canImport(UIKit)
        return image.pngData()
        #elseif canImport(AppKit)
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        return bitmapRep.representation(using: .png, properties: [:])
        #endif
    }

    private func dataToImage(_ data: Data) -> PlatformImage? {
        #if canImport(UIKit)
        return UIImage(data: data)
        #elseif canImport(AppKit)
        return NSImage(data: data)
        #endif
    }

    private func imageSize(_ image: PlatformImage) -> CGSize {
        // Use image.size (point dimensions) to match how ThumbnailGenerator
        // calculates dimensions. This ensures tests work consistently regardless
        // of device scale (1x, 2x, 3x).
        return image.size
    }
}

// MARK: - Platform Type Alias

#if canImport(UIKit)
private typealias PlatformImage = UIImage
#elseif canImport(AppKit)
private typealias PlatformImage = NSImage
#endif

// MARK: - Test Error

private struct TestError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
