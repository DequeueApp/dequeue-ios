//
//  CUID.swift
//  Dequeue
//
//  Collision-resistant unique identifier generator (CUID2-like)
//  Compatible with backend CUID format
//

import Foundation

enum CUID {
    /// Generates a new CUID string
    /// Format similar to CUID2: random alphanumeric, 24 characters
    static func generate() -> String {
        let timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
        let randomPart = randomAlphanumeric(count: 16)
        let timestampHex = String(timestamp, radix: 36)

        // Combine and ensure consistent length
        let combined = timestampHex + randomPart
        return String(combined.prefix(24))
    }

    /// Generates a random alphanumeric string
    private static func randomAlphanumeric(count: Int) -> String {
        let characters = "0123456789abcdefghijklmnopqrstuvwxyz"
        return String((0..<count).map { _ in characters.randomElement()! })
    }

    /// Validates if a string could be a valid entity ID (UUID or CUID)
    static func isValidId(_ id: String) -> Bool {
        // Accept UUIDs (36 chars with dashes) or CUIDs (typically 24-25 chars alphanumeric)
        if UUID(uuidString: id) != nil {
            return true
        }
        // CUID: alphanumeric, reasonable length
        let alphanumeric = CharacterSet.alphanumerics
        return id.count >= 20 && id.count <= 36 && id.unicodeScalars.allSatisfy { alphanumeric.contains($0) }
    }
}
