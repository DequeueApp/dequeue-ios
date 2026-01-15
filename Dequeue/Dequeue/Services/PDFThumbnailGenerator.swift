//
//  PDFThumbnailGenerator.swift
//  Dequeue
//
//  Generates thumbnails for PDF attachments using PDFKit
//

import Foundation
import PDFKit
import os.log

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - PDF Thumbnail Errors

enum PDFThumbnailError: LocalizedError {
    case failedToLoadPDF(url: URL)
    case emptyPDF
    case passwordProtected
    case failedToRenderPage
    case failedToCompressImage
    case fileTooLarge(size: Int64, maxSize: Int64)

    var errorDescription: String? {
        switch self {
        case let .failedToLoadPDF(url):
            return "Failed to load PDF: \(url.lastPathComponent)"
        case .emptyPDF:
            return "PDF has no pages"
        case .passwordProtected:
            return "PDF is password protected"
        case .failedToRenderPage:
            return "Failed to render PDF page"
        case .failedToCompressImage:
            return "Failed to compress thumbnail image"
        case let .fileTooLarge(size, maxSize):
            let formatter = ByteCountFormatter()
            // swiftlint:disable:next line_length
            return "PDF too large (\(formatter.string(fromByteCount: size))) - max \(formatter.string(fromByteCount: maxSize))"
        }
    }
}

// MARK: - PDF Thumbnail Configuration

struct PDFThumbnailConfiguration: Sendable {
    /// Maximum dimension (width or height) for the thumbnail
    let maxDimension: CGFloat

    /// JPEG compression quality (0.0 to 1.0)
    let compressionQuality: CGFloat

    /// Maximum PDF file size to process (in bytes)
    let maxFileSize: Int64

    nonisolated static let `default` = PDFThumbnailConfiguration(
        maxDimension: 200,
        compressionQuality: 0.7,
        maxFileSize: 100 * 1_024 * 1_024  // 100 MB
    )
}

// MARK: - PDF Thumbnail Generator

/// Generates thumbnails for PDF attachments
actor PDFThumbnailGenerator {
    private let configuration: PDFThumbnailConfiguration
    private let logger = Logger(subsystem: "com.dequeue", category: "PDFThumbnailGenerator")

    init(configuration: PDFThumbnailConfiguration = .default) {
        self.configuration = configuration
    }

    /// Generate a thumbnail from the first page of a PDF file
    /// - Parameter pdfURL: URL to the local PDF file
    /// - Returns: JPEG data for the thumbnail
    func generateThumbnail(from pdfURL: URL) async throws -> Data {
        logger.debug("Generating PDF thumbnail for: \(pdfURL.lastPathComponent)")

        // Validate file exists and check size
        let attributes = try FileManager.default.attributesOfItem(atPath: pdfURL.path)
        guard let fileSize = attributes[.size] as? Int64 else {
            throw PDFThumbnailError.failedToLoadPDF(url: pdfURL)
        }

        if fileSize > configuration.maxFileSize {
            throw PDFThumbnailError.fileTooLarge(
                size: fileSize,
                maxSize: configuration.maxFileSize
            )
        }

        // Load PDF document
        guard let document = PDFDocument(url: pdfURL) else {
            throw PDFThumbnailError.failedToLoadPDF(url: pdfURL)
        }

        // Check for password protection
        if document.isLocked {
            throw PDFThumbnailError.passwordProtected
        }

        // Get first page
        guard document.pageCount > 0, let page = document.page(at: 0) else {
            throw PDFThumbnailError.emptyPDF
        }

        // Generate thumbnail from first page
        let thumbnailData = try renderPageThumbnail(page: page)

        logger.debug("Generated PDF thumbnail: \(thumbnailData.count) bytes")
        return thumbnailData
    }

    /// Generate a thumbnail from PDF data
    /// - Parameter data: Raw PDF data
    /// - Returns: JPEG data for the thumbnail
    func generateThumbnail(from data: Data) async throws -> Data {
        if Int64(data.count) > configuration.maxFileSize {
            throw PDFThumbnailError.fileTooLarge(
                size: Int64(data.count),
                maxSize: configuration.maxFileSize
            )
        }

        guard let document = PDFDocument(data: data) else {
            throw PDFThumbnailError.failedToRenderPage
        }

        if document.isLocked {
            throw PDFThumbnailError.passwordProtected
        }

        guard document.pageCount > 0, let page = document.page(at: 0) else {
            throw PDFThumbnailError.emptyPDF
        }

        return try renderPageThumbnail(page: page)
    }

    // MARK: - Private Methods

    private func renderPageThumbnail(page: PDFPage) throws -> Data {
        let pageRect = page.bounds(for: .mediaBox)
        let thumbnailSize = calculateThumbnailSize(for: pageRect.size)

        #if canImport(UIKit)
        // Use PDFPage's built-in thumbnail method on iOS
        let thumbnailImage = page.thumbnail(of: thumbnailSize, for: .mediaBox)

        guard let jpegData = thumbnailImage.jpegData(compressionQuality: configuration.compressionQuality) else {
            throw PDFThumbnailError.failedToCompressImage
        }

        return jpegData

        #elseif canImport(AppKit)
        // Manual rendering on macOS
        let image = NSImage(size: thumbnailSize)
        image.lockFocus()

        guard let context = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            throw PDFThumbnailError.failedToRenderPage
        }

        // White background
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: thumbnailSize))

        // Scale to fit
        let scaleX = thumbnailSize.width / pageRect.width
        let scaleY = thumbnailSize.height / pageRect.height
        context.scaleBy(x: scaleX, y: scaleY)

        // Draw PDF page
        if let pageRef = page.pageRef {
            context.drawPDFPage(pageRef)
        }

        image.unlockFocus()

        // Convert to JPEG
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapRep.representation(
                  using: .jpeg,
                  properties: [.compressionFactor: configuration.compressionQuality]
              ) else {
            throw PDFThumbnailError.failedToCompressImage
        }

        return jpegData
        #endif
    }

    /// Calculate the target thumbnail size maintaining aspect ratio
    private func calculateThumbnailSize(for pageSize: CGSize) -> CGSize {
        let maxDim = configuration.maxDimension

        let widthRatio = maxDim / pageSize.width
        let heightRatio = maxDim / pageSize.height
        let scaleFactor = min(widthRatio, heightRatio)

        return CGSize(
            width: floor(pageSize.width * scaleFactor),
            height: floor(pageSize.height * scaleFactor)
        )
    }
}

// MARK: - Attachment Extension

extension Attachment {
    /// Returns true if this attachment supports PDF thumbnail generation
    var supportsPDFThumbnail: Bool {
        isPDF
    }
}
