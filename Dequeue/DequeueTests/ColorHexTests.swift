//
//  ColorHexTests.swift
//  DequeueTests
//
//  Tests for Color+Hex extension
//

import Testing
import SwiftUI
@testable import Dequeue

@Suite("Color+Hex Tests")
struct ColorHexTests {
    // MARK: - Successful Parsing

    @Test("init with hex string including hash prefix")
    func initWithHashPrefix() {
        let color = Color(hex: "#FF5733")
        #expect(color != nil, "Should parse hex with # prefix")
    }

    @Test("init with hex string without hash prefix")
    func initWithoutHashPrefix() {
        let color = Color(hex: "FF5733")
        #expect(color != nil, "Should parse hex without # prefix")
    }

    @Test("init with lowercase hex string")
    func initWithLowercaseHex() {
        let color = Color(hex: "ff5733")
        #expect(color != nil, "Should parse lowercase hex")
    }

    @Test("init with mixed case hex string")
    func initWithMixedCaseHex() {
        let color = Color(hex: "Ff5733")
        #expect(color != nil, "Should parse mixed case hex")
    }

    @Test("init with black hex")
    func initWithBlack() {
        let color = Color(hex: "#000000")
        #expect(color != nil, "Should parse black")
    }

    @Test("init with white hex")
    func initWithWhite() {
        let color = Color(hex: "#FFFFFF")
        #expect(color != nil, "Should parse white")
    }

    @Test("init with pure red hex")
    func initWithPureRed() {
        let color = Color(hex: "#FF0000")
        #expect(color != nil, "Should parse pure red")
    }

    @Test("init with pure green hex")
    func initWithPureGreen() {
        let color = Color(hex: "#00FF00")
        #expect(color != nil, "Should parse pure green")
    }

    @Test("init with pure blue hex")
    func initWithPureBlue() {
        let color = Color(hex: "#0000FF")
        #expect(color != nil, "Should parse pure blue")
    }

    // MARK: - Whitespace Handling

    @Test("init trims leading and trailing whitespace")
    func initTrimsWhitespace() {
        let color = Color(hex: "  #FF5733  ")
        #expect(color != nil, "Should trim whitespace and parse")
    }

    @Test("init trims newlines")
    func initTrimsNewlines() {
        let color = Color(hex: "\n#FF5733\n")
        #expect(color != nil, "Should trim newlines and parse")
    }

    // MARK: - Failure Cases

    @Test("init returns nil for empty string")
    func initReturnsNilForEmpty() {
        let color = Color(hex: "")
        #expect(color == nil, "Empty string should return nil")
    }

    @Test("init returns nil for too short hex")
    func initReturnsNilForTooShort() {
        let color = Color(hex: "#FFF")
        #expect(color == nil, "3-char hex should return nil (only 6-char supported)")
    }

    @Test("init returns nil for too long hex")
    func initReturnsNilForTooLong() {
        let color = Color(hex: "#FF5733FF")
        #expect(color == nil, "8-char hex (with alpha) should return nil")
    }

    @Test("init returns nil for invalid hex characters")
    func initReturnsNilForInvalidChars() {
        let color = Color(hex: "#GGGGGG")
        #expect(color == nil, "Non-hex characters should return nil")
    }

    @Test("init returns nil for hash only")
    func initReturnsNilForHashOnly() {
        let color = Color(hex: "#")
        #expect(color == nil, "Just # should return nil")
    }

    @Test("init returns nil for random text")
    func initReturnsNilForRandomText() {
        let color = Color(hex: "hello!")
        #expect(color == nil, "Non-hex text should return nil")
    }

    @Test("init returns nil for 5-character hex")
    func initReturnsNilFor5Chars() {
        let color = Color(hex: "#FF573")
        #expect(color == nil, "5-char hex should return nil")
    }

    @Test("init returns nil for 7-character hex without hash")
    func initReturnsNilFor7CharsNoHash() {
        let color = Color(hex: "FF57330")
        #expect(color == nil, "7-char hex without hash should return nil")
    }

    // MARK: - Multiple Hash Handling

    @Test("init handles multiple hash symbols")
    func initHandlesMultipleHashes() {
        // replaceOccurrences removes all # — "##FF5733" becomes "FF5733" (6 chars)
        let color = Color(hex: "##FF5733")
        #expect(color != nil, "Double hash should still parse since all # are removed")
    }
}
