//
//  PDFThumbnailGeneratorTests.swift
//  DequeueTests
//
//  Tests for PDFThumbnailGenerator service
//

import Testing
import Foundation
import PDFKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
@testable import Dequeue

@Suite("PDFThumbnailGenerator Tests")
struct PDFThumbnailGeneratorTests {

    // MARK: - Attachment Extension Tests

    @Test("Attachment supportsPDFThumbnail returns true for PDFs")
    func attachmentSupportsPDFThumbnailForPDFs() {
        let pdfAttachment = Attachment(
            parentId: "test",
            parentType: .stack,
            filename: "document.pdf",
            mimeType: "application/pdf",
            sizeBytes: 1024
        )

        #expect(pdfAttachment.supportsPDFThumbnail)
    }

    @Test("Attachment supportsPDFThumbnail returns false for non-PDFs")
    func attachmentDoesNotSupportPDFThumbnailForNonPDFs() {
        let imageAttachment = Attachment(
            parentId: "test",
            parentType: .stack,
            filename: "photo.jpg",
            mimeType: "image/jpeg",
            sizeBytes: 1024
        )

        #expect(!imageAttachment.supportsPDFThumbnail)
    }

    // MARK: - Thumbnail Generation Tests

    @Test("Generate thumbnail from valid PDF file")
    func generateThumbnailFromValidPDF() async throws {
        let generator = PDFThumbnailGenerator()

        // Create a simple test PDF
        let pdfURL = try createTestPDF()
        defer { try? FileManager.default.removeItem(at: pdfURL) }

        let thumbnailData = try await generator.generateThumbnail(from: pdfURL)

        // Verify thumbnail was generated
        #expect(!thumbnailData.isEmpty)

        // Verify thumbnail is valid JPEG (starts with JPEG magic bytes)
        #expect(thumbnailData[0] == 0xFF)
        #expect(thumbnailData[1] == 0xD8)
    }

    @Test("Generate thumbnail from PDF data")
    func generateThumbnailFromPDFData() async throws {
        let generator = PDFThumbnailGenerator()

        let pdfData = try createTestPDFData()

        let thumbnailData = try await generator.generateThumbnail(from: pdfData)

        #expect(!thumbnailData.isEmpty)
        #expect(thumbnailData[0] == 0xFF)
        #expect(thumbnailData[1] == 0xD8)
    }

    @Test("Generate thumbnail respects max dimension")
    func thumbnailRespectsMaxDimension() async throws {
        let config = PDFThumbnailConfiguration(
            maxDimension: 100,
            compressionQuality: 0.7,
            maxFileSize: 50 * 1024 * 1024
        )
        let generator = PDFThumbnailGenerator(configuration: config)

        let pdfURL = try createTestPDF(pageWidth: 612, pageHeight: 792) // Letter size
        defer { try? FileManager.default.removeItem(at: pdfURL) }

        let thumbnailData = try await generator.generateThumbnail(from: pdfURL)

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
        let config = PDFThumbnailConfiguration(
            maxDimension: 200,
            compressionQuality: 0.7,
            maxFileSize: 50 * 1024 * 1024
        )
        let generator = PDFThumbnailGenerator(configuration: config)

        // Create letter size PDF (8.5 x 11 inches = 612 x 792 points)
        let pdfURL = try createTestPDF(pageWidth: 612, pageHeight: 792)
        defer { try? FileManager.default.removeItem(at: pdfURL) }

        let thumbnailData = try await generator.generateThumbnail(from: pdfURL)

        guard let thumbnail = dataToImage(thumbnailData) else {
            throw TestError("Failed to load thumbnail image")
        }

        let thumbnailSize = imageSize(thumbnail)

        // Verify aspect ratio is maintained (with small tolerance for rounding)
        let originalRatio = 612.0 / 792.0
        let thumbnailRatio = thumbnailSize.width / thumbnailSize.height
        let ratioDifference = abs(originalRatio - thumbnailRatio)

        #expect(ratioDifference < 0.05, "Aspect ratio should be maintained")
    }

    @Test("Handles multi-page PDFs by using first page")
    func handlesMultiPagePDFs() async throws {
        let generator = PDFThumbnailGenerator()

        let pdfURL = try createTestPDF(pageCount: 5)
        defer { try? FileManager.default.removeItem(at: pdfURL) }

        let thumbnailData = try await generator.generateThumbnail(from: pdfURL)

        // Should succeed and generate thumbnail from first page
        #expect(!thumbnailData.isEmpty)
    }

    @Test("Rejects non-existent file")
    func rejectsNonExistentFile() async throws {
        let generator = PDFThumbnailGenerator()

        let fakeURL = URL(fileURLWithPath: "/nonexistent/path/document.pdf")

        await #expect(throws: Error.self) {
            try await generator.generateThumbnail(from: fakeURL)
        }
    }

    @Test("Rejects files exceeding size limit")
    func rejectsOversizedFiles() async throws {
        let config = PDFThumbnailConfiguration(
            maxDimension: 200,
            compressionQuality: 0.7,
            maxFileSize: 100  // Very small limit for testing
        )
        let generator = PDFThumbnailGenerator(configuration: config)

        let pdfURL = try createTestPDF()
        defer { try? FileManager.default.removeItem(at: pdfURL) }

        await #expect(throws: PDFThumbnailError.self) {
            try await generator.generateThumbnail(from: pdfURL)
        }
    }

    @Test("Rejects invalid PDF data")
    func rejectsInvalidPDFData() async throws {
        let generator = PDFThumbnailGenerator()

        // Create invalid PDF data
        let invalidData = Data([0x00, 0x01, 0x02, 0x03, 0x04, 0x05])

        await #expect(throws: PDFThumbnailError.self) {
            try await generator.generateThumbnail(from: invalidData)
        }
    }

    @Test("Rejects oversized PDF data")
    func rejectsOversizedPDFData() async throws {
        let config = PDFThumbnailConfiguration(
            maxDimension: 200,
            compressionQuality: 0.7,
            maxFileSize: 100
        )
        let generator = PDFThumbnailGenerator(configuration: config)

        let largeData = Data(count: 200)

        await #expect(throws: PDFThumbnailError.self) {
            try await generator.generateThumbnail(from: largeData)
        }
    }

    // MARK: - Helper Methods

    private func createTestPDF(
        pageWidth: CGFloat = 612,
        pageHeight: CGFloat = 792,
        pageCount: Int = 1
    ) throws -> URL {
        let pdfData = try createTestPDFData(
            pageWidth: pageWidth,
            pageHeight: pageHeight,
            pageCount: pageCount
        )

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_pdf_\(UUID().uuidString).pdf")

        try pdfData.write(to: tempURL)
        return tempURL
    }

    private func createTestPDFData(
        pageWidth: CGFloat = 612,
        pageHeight: CGFloat = 792,
        pageCount: Int = 1
    ) throws -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        let data = NSMutableData()

        #if canImport(UIKit)
        UIGraphicsBeginPDFContextToData(data, pageRect, nil)
        for pageIndex in 0..<pageCount {
            UIGraphicsBeginPDFPage()
            // Safety: UIGraphicsGetCurrentContext() is guaranteed to return a valid context
            // immediately after UIGraphicsBeginPDFPage() within the same PDF context block.
            // This is documented Apple API behavior - the context exists until EndPDFContext.
            guard let context = UIGraphicsGetCurrentContext() else {
                fatalError("No graphics context available after UIGraphicsBeginPDFPage()")
            }

            // Draw background
            context.setFillColor(UIColor.white.cgColor)
            context.fill(pageRect)

            // Draw some content on each page
            context.setFillColor(UIColor.blue.cgColor)
            context.fill(CGRect(x: 50, y: 50, width: 100, height: 100))

            // Draw page number
            let text = "Page \(pageIndex + 1)" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 24),
                .foregroundColor: UIColor.black
            ]
            text.draw(at: CGPoint(x: 200, y: 400), withAttributes: attributes)
        }
        UIGraphicsEndPDFContext()
        #elseif canImport(AppKit)
        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
            throw TestError("Failed to create PDF context")
        }

        for pageIndex in 0..<pageCount {
            var mediaBox = pageRect
            context.beginPage(mediaBox: &mediaBox)

            // Draw background
            context.setFillColor(NSColor.white.cgColor)
            context.fill(pageRect)

            // Draw some content
            context.setFillColor(NSColor.blue.cgColor)
            context.fill(CGRect(x: 50, y: pageHeight - 150, width: 100, height: 100))

            // Draw page number text
            let text = "Page \(pageIndex + 1)"
            let font = NSFont.systemFont(ofSize: 24)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.black
            ]
            let attrString = NSAttributedString(string: text, attributes: attributes)
            let line = CTLineCreateWithAttributedString(attrString)

            context.textPosition = CGPoint(x: 200, y: pageHeight - 400)
            CTLineDraw(line, context)

            context.endPage()
        }
        context.closePDF()
        #endif

        return data as Data
    }

    private func dataToImage(_ data: Data) -> PlatformImage? {
        #if canImport(UIKit)
        return UIImage(data: data)
        #elseif canImport(AppKit)
        return NSImage(data: data)
        #endif
    }

    private func imageSize(_ image: PlatformImage) -> CGSize {
        #if canImport(UIKit)
        return image.size
        #elseif canImport(AppKit)
        return image.size
        #endif
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
