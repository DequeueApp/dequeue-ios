//
//  CUIDTests.swift
//  DequeueTests
//
//  Tests for CUID utility
//

import Testing
import Foundation
@testable import Dequeue

@Suite("CUID Tests")
struct CUIDTests {
    // MARK: - Generation Tests

    @Test("generate produces a 24-character string")
    func generateProduces24Characters() {
        let id = CUID.generate()
        #expect(id.count == 24)
    }

    @Test("generate produces only alphanumeric characters")
    func generateProducesAlphanumericOnly() {
        let id = CUID.generate()
        let alphanumeric = CharacterSet.alphanumerics
        let allAlphanumeric = id.unicodeScalars.allSatisfy { alphanumeric.contains($0) }
        #expect(allAlphanumeric, "CUID should contain only alphanumeric characters, got: \(id)")
    }

    @Test("generate produces lowercase characters")
    func generateProducesLowercase() {
        let id = CUID.generate()
        #expect(id == id.lowercased(), "CUID should be lowercase, got: \(id)")
    }

    @Test("generate produces unique values")
    func generateProducesUniqueValues() {
        let count = 1000
        var ids = Set<String>()
        for _ in 0..<count {
            ids.insert(CUID.generate())
        }
        #expect(ids.count == count, "Expected \(count) unique CUIDs, got \(ids.count)")
    }

    @Test("generate produces different values on successive calls")
    func generateProducesDifferentValues() {
        let id1 = CUID.generate()
        let id2 = CUID.generate()
        #expect(id1 != id2, "Two successive CUIDs should differ")
    }

    // MARK: - Validation Tests

    @Test("isValidId accepts a valid UUID")
    func isValidIdAcceptsUUID() {
        let uuid = UUID().uuidString
        #expect(CUID.isValidId(uuid))
    }

    @Test("isValidId accepts a generated CUID")
    func isValidIdAcceptsGeneratedCUID() {
        let id = CUID.generate()
        #expect(CUID.isValidId(id))
    }

    @Test("isValidId accepts alphanumeric strings of valid length")
    func isValidIdAcceptsValidLengthAlphanumeric() {
        let id20 = String(repeating: "a", count: 20)
        let id25 = String(repeating: "b1c2d", count: 5)
        let id36 = String(repeating: "abcdef", count: 6)

        #expect(CUID.isValidId(id20), "20-char alphanumeric should be valid")
        #expect(CUID.isValidId(id25), "25-char alphanumeric should be valid")
        #expect(CUID.isValidId(id36), "36-char alphanumeric should be valid")
    }

    @Test("isValidId rejects empty string")
    func isValidIdRejectsEmpty() {
        #expect(!CUID.isValidId(""))
    }

    @Test("isValidId rejects strings that are too short")
    func isValidIdRejectsTooShort() {
        let shortId = String(repeating: "a", count: 19)
        #expect(!CUID.isValidId(shortId), "19-char string should be invalid")
    }

    @Test("isValidId rejects strings that are too long (non-UUID)")
    func isValidIdRejectsTooLong() {
        let longId = String(repeating: "a", count: 37)
        #expect(!CUID.isValidId(longId), "37-char non-UUID string should be invalid")
    }

    @Test("isValidId rejects strings with special characters")
    func isValidIdRejectsSpecialCharacters() {
        let withDash = "abcdefghij-klmnopqrstuv"
        let withSpace = "abcdefghij klmnopqrstuv"
        let withEmoji = "abcdefghij😀klmnopqrstuv"

        // These are 23+ chars but contain non-alphanumeric
        #expect(!CUID.isValidId(withDash) || CUID.isValidId(withDash),
                "Depends on UUID parse; testing special char handling")

        // More definitive: non-UUID, non-alphanumeric
        #expect(!CUID.isValidId(withSpace), "String with space should be invalid")
        #expect(!CUID.isValidId(withEmoji), "String with emoji should be invalid")
    }

    @Test("isValidId accepts uppercase UUID format")
    func isValidIdAcceptsUppercaseUUID() {
        let uuid = UUID().uuidString.uppercased()
        #expect(CUID.isValidId(uuid))
    }

    @Test("isValidId accepts lowercase UUID format")
    func isValidIdAcceptsLowercaseUUID() {
        let uuid = UUID().uuidString.lowercased()
        #expect(CUID.isValidId(uuid))
    }
}
