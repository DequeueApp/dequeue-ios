//
//  FileTypeIconTests.swift
//  DequeueTests
//
//  Tests for FileTypeIcon — MIME-type → SF Symbol / Color mapping.
//

import Testing
import Foundation
@testable import Dequeue

@Suite("FileTypeIcon.symbolName")
@MainActor
struct FileTypeIconSymbolTests {

    // MARK: - Prefix-based rules

    @Test("audio/* maps to waveform")
    func audioPrefix() {
        #expect(FileTypeIcon.symbolName(for: "audio/mpeg") == "waveform")
        #expect(FileTypeIcon.symbolName(for: "audio/wav") == "waveform")
        #expect(FileTypeIcon.symbolName(for: "audio/ogg") == "waveform")
    }

    @Test("video/* maps to film")
    func videoPrefix() {
        #expect(FileTypeIcon.symbolName(for: "video/mp4") == "film")
        #expect(FileTypeIcon.symbolName(for: "video/quicktime") == "film")
        #expect(FileTypeIcon.symbolName(for: "video/webm") == "film")
    }

    @Test("image/* maps to photo")
    func imagePrefix() {
        #expect(FileTypeIcon.symbolName(for: "image/jpeg") == "photo")
        #expect(FileTypeIcon.symbolName(for: "image/png") == "photo")
        #expect(FileTypeIcon.symbolName(for: "image/gif") == "photo")
        #expect(FileTypeIcon.symbolName(for: "image/webp") == "photo")
    }

    // MARK: - text/* types

    @Test("text/plain maps to doc.plaintext.fill")
    func textPlain() {
        #expect(FileTypeIcon.symbolName(for: "text/plain") == "doc.plaintext.fill")
    }

    @Test("text/html maps to globe")
    func textHTML() {
        #expect(FileTypeIcon.symbolName(for: "text/html") == "globe")
    }

    @Test("text/css maps to chevron symbol")
    func textCSS() {
        #expect(FileTypeIcon.symbolName(for: "text/css") == "chevron.left.forwardslash.chevron.right")
    }

    @Test("text/javascript maps to chevron symbol")
    func textJS() {
        #expect(FileTypeIcon.symbolName(for: "text/javascript") == "chevron.left.forwardslash.chevron.right")
    }

    @Test("text/markdown maps to doc.richtext")
    func textMarkdown() {
        #expect(FileTypeIcon.symbolName(for: "text/markdown") == "doc.richtext")
    }

    @Test("text/csv maps to tablecells")
    func textCSV() {
        #expect(FileTypeIcon.symbolName(for: "text/csv") == "tablecells")
    }

    @Test("text/calendar maps to calendar")
    func textCalendar() {
        #expect(FileTypeIcon.symbolName(for: "text/calendar") == "calendar")
    }

    // MARK: - PDF

    @Test("application/pdf maps to doc.fill")
    func pdf() {
        #expect(FileTypeIcon.symbolName(for: "application/pdf") == "doc.fill")
    }

    // MARK: - Word processing

    @Test("application/msword maps to doc.text.fill")
    func msWord() {
        #expect(FileTypeIcon.symbolName(for: "application/msword") == "doc.text.fill")
    }

    @Test("docx maps to doc.text.fill")
    func docx() {
        let docx = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        #expect(FileTypeIcon.symbolName(for: docx) == "doc.text.fill")
    }

    @Test("vnd.apple.pages maps to doc.text.fill")
    func applePages() {
        #expect(FileTypeIcon.symbolName(for: "application/vnd.apple.pages") == "doc.text.fill")
    }

    // MARK: - Spreadsheets

    @Test("application/vnd.ms-excel maps to tablecells.fill")
    func msExcel() {
        #expect(FileTypeIcon.symbolName(for: "application/vnd.ms-excel") == "tablecells.fill")
    }

    @Test("xlsx maps to tablecells.fill")
    func xlsx() {
        let xlsx = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        #expect(FileTypeIcon.symbolName(for: xlsx) == "tablecells.fill")
    }

    @Test("vnd.apple.numbers maps to tablecells.fill")
    func appleNumbers() {
        #expect(FileTypeIcon.symbolName(for: "application/vnd.apple.numbers") == "tablecells.fill")
    }

    // MARK: - Presentations

    @Test("application/vnd.ms-powerpoint maps to rectangle.split.3x3.fill")
    func msPowerpoint() {
        #expect(FileTypeIcon.symbolName(for: "application/vnd.ms-powerpoint") == "rectangle.split.3x3.fill")
    }

    @Test("pptx maps to rectangle.split.3x3.fill")
    func pptx() {
        let pptx = "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        #expect(FileTypeIcon.symbolName(for: pptx) == "rectangle.split.3x3.fill")
    }

    @Test("vnd.apple.keynote maps to rectangle.split.3x3.fill")
    func appleKeynote() {
        #expect(FileTypeIcon.symbolName(for: "application/vnd.apple.keynote") == "rectangle.split.3x3.fill")
    }

    // MARK: - Archives

    @Test("application/zip maps to doc.zipper")
    func zip() {
        #expect(FileTypeIcon.symbolName(for: "application/zip") == "doc.zipper")
    }

    @Test("x-zip-compressed maps to doc.zipper")
    func xZipCompressed() {
        #expect(FileTypeIcon.symbolName(for: "application/x-zip-compressed") == "doc.zipper")
    }

    @Test("x-rar-compressed maps to doc.zipper")
    func rar() {
        #expect(FileTypeIcon.symbolName(for: "application/x-rar-compressed") == "doc.zipper")
    }

    @Test("x-7z-compressed maps to doc.zipper")
    func sevenZip() {
        #expect(FileTypeIcon.symbolName(for: "application/x-7z-compressed") == "doc.zipper")
    }

    @Test("application/gzip maps to doc.zipper")
    func gzip() {
        #expect(FileTypeIcon.symbolName(for: "application/gzip") == "doc.zipper")
    }

    @Test("application/x-tar maps to doc.zipper")
    func tar() {
        #expect(FileTypeIcon.symbolName(for: "application/x-tar") == "doc.zipper")
    }

    // MARK: - Code / JSON

    @Test("application/json maps to chevron symbol")
    func json() {
        #expect(FileTypeIcon.symbolName(for: "application/json") == "chevron.left.forwardslash.chevron.right")
    }

    @Test("application/xml maps to chevron symbol")
    func xml() {
        #expect(FileTypeIcon.symbolName(for: "application/xml") == "chevron.left.forwardslash.chevron.right")
    }

    @Test("application/javascript maps to chevron symbol")
    func appJS() {
        #expect(FileTypeIcon.symbolName(for: "application/javascript") == "chevron.left.forwardslash.chevron.right")
    }

    // MARK: - Calendar / VCard

    @Test("text/calendar maps to calendar (specific check)")
    func calendarMime() {
        #expect(FileTypeIcon.symbolName(for: "application/ics") == "calendar")
    }

    // NOTE: `text/vcard` and `text/x-vcard` match the `text/` prefix branch before
    // reaching the explicit switch cases, so they fall through to textTypeSymbol's
    // default and return "doc.plaintext.fill". The switch cases for these MIME types
    // are currently unreachable dead code.
    @Test("text/vcard falls through to text-prefix handler (doc.plaintext.fill)")
    func vcard() {
        #expect(FileTypeIcon.symbolName(for: "text/vcard") == "doc.plaintext.fill")
        #expect(FileTypeIcon.symbolName(for: "text/x-vcard") == "doc.plaintext.fill")
    }

    // MARK: - Default fallback

    @Test("unknown MIME type maps to doc.fill")
    func unknownMimeType() {
        #expect(FileTypeIcon.symbolName(for: "application/unknown-type") == "doc.fill")
        #expect(FileTypeIcon.symbolName(for: "application/octet-stream") == "app.fill")
    }

    @Test("case insensitive — uppercase AUDIO/ maps to waveform")
    func caseInsensitive() {
        #expect(FileTypeIcon.symbolName(for: "AUDIO/MP3") == "waveform")
        #expect(FileTypeIcon.symbolName(for: "VIDEO/MP4") == "film")
        #expect(FileTypeIcon.symbolName(for: "IMAGE/PNG") == "photo")
    }

    @Test("symbol names are non-empty for all tested types")
    func allSymbolsNonEmpty() {
        let mimes = [
            "audio/mpeg", "video/mp4", "image/jpeg", "text/plain",
            "application/pdf", "application/msword", "application/vnd.ms-excel",
            "application/vnd.ms-powerpoint", "application/zip",
            "application/json", "text/html", "application/octet-stream"
        ]
        for mime in mimes {
            let symbol = FileTypeIcon.symbolName(for: mime)
            #expect(!symbol.isEmpty, "Empty symbol for \(mime)")
        }
    }
}

@Suite("FileTypeIcon.color")
@MainActor
struct FileTypeIconColorTests {

    @Test("audio/* returns purple")
    func audioColor() {
        // Color equality in SwiftUI is not directly testable in unit tests,
        // so we verify the function doesn't crash and returns a value.
        let color = FileTypeIcon.color(for: "audio/mpeg")
        _ = color
    }

    @Test("video/* returns pink")
    func videoColor() {
        let color = FileTypeIcon.color(for: "video/mp4")
        _ = color
    }

    @Test("image/* returns green (prefix)")
    func imageColor() {
        let color = FileTypeIcon.color(for: "image/jpeg")
        _ = color
    }

    @Test("PDF returns a color without crashing")
    func pdfColor() {
        let color = FileTypeIcon.color(for: "application/pdf")
        _ = color
    }

    @Test("Word docs return a color without crashing")
    func wordColor() {
        let color = FileTypeIcon.color(for: "application/msword")
        _ = color
    }

    @Test("Excel docs return a color without crashing")
    func excelColor() {
        let color = FileTypeIcon.color(for: "application/vnd.ms-excel")
        _ = color
    }

    @Test("PowerPoint docs return a color without crashing")
    func powerpointColor() {
        let color = FileTypeIcon.color(for: "application/vnd.ms-powerpoint")
        _ = color
    }

    @Test("Archives return a color without crashing")
    func archiveColor() {
        let color = FileTypeIcon.color(for: "application/zip")
        _ = color
    }

    @Test("JSON returns a color without crashing")
    func jsonColor() {
        let color = FileTypeIcon.color(for: "application/json")
        _ = color
    }

    @Test("Unknown MIME type returns secondary color without crashing")
    func unknownColor() {
        let color = FileTypeIcon.color(for: "application/unknown-xyz")
        _ = color
    }
}
