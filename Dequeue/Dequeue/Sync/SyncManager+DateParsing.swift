//
//  SyncManager+DateParsing.swift
//  Dequeue
//
//  ISO8601 date parsing utilities and sync event helpers.
//  Extracted from SyncManager.swift for file-length compliance.
//

import Foundation

// MARK: - Date Parsing & Event Utilities

extension SyncManager {
    // ISO8601 formatter that supports fractional seconds (Go's RFC3339Nano format)
    // Note: ISO8601DateFormatter is thread-safe but not marked Sendable in current SDK
    nonisolated(unsafe) static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    // Standard ISO8601 formatter without fractional seconds
    // Note: ISO8601DateFormatter is thread-safe but not marked Sendable in current SDK
    nonisolated(unsafe) static let iso8601Standard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    // Pre-compiled regex patterns for timestamp parsing (compiled once, reused for performance)
    // SAFETY: Force unwrap is safe because:
    // 1. Patterns are compile-time constants (hardcoded string literals)
    // 2. Patterns are valid regex syntax (verified by tests and manual inspection)
    // 3. Compilation only happens once at static initialization, not at runtime
    // swiftlint:disable force_try
    static let nanosecondsRegex: NSRegularExpression = {
        // Matches ISO8601 timestamps with nanosecond precision, captures first 3 decimal places
        try! NSRegularExpression(pattern: #"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})\.(\d{3})\d*(Z|[+-]\d{2}:\d{2})"#)
    }()

    static let fractionalSecondsRegex: NSRegularExpression = {
        // Matches ISO8601 timestamps with any fractional seconds (for removal)
        try! NSRegularExpression(pattern: #"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})\.\d+(Z|[+-]\d{2}:\d{2})"#)
    }()
    // swiftlint:enable force_try

    /// Adds actor metadata fields (actor_type, actor_id) to an event dictionary (DEQ-55).
    /// Extracts from the encoded EventMetadata Data, mapping camelCase to snake_case for the server.
    static func addActorMetadata(from metadata: Data?, to eventDict: inout [String: Any]) {
        guard let metadata,
              let metadataDict = try? JSONSerialization.jsonObject(with: metadata) as? [String: Any],
              let actorType = metadataDict["actorType"] as? String else { return }
        eventDict["actor_type"] = actorType
        if let actorId = metadataDict["actorId"] as? String {
            eventDict["actor_id"] = actorId
        }
    }

    /// Generates a short sync ID for tracking sync operations in logs.
    /// Uses first 8 characters of a UUID for brevity while maintaining uniqueness.
    static func generateSyncId() -> String {
        String(UUID().uuidString.prefix(8))
    }

    /// Parses ISO8601 timestamp, handling Go's RFC3339Nano format with nanosecond precision.
    /// Go sends timestamps like "2024-01-15T10:30:45.123456789Z" but Swift's ISO8601DateFormatter
    /// only handles milliseconds (3 decimal places). We truncate to milliseconds for parsing.
    static func parseISO8601(_ string: String) -> Date? {
        // First, try parsing as-is with fractional seconds
        if let date = iso8601WithFractionalSeconds.date(from: string) {
            return date
        }

        // If that fails, try truncating nanoseconds to milliseconds
        // Go sends: "2024-01-15T10:30:45.123456789Z"
        // Swift needs: "2024-01-15T10:30:45.123Z"
        let truncated = truncateNanosecondsToMilliseconds(string)
        if let date = iso8601WithFractionalSeconds.date(from: truncated) {
            return date
        }

        // Fall back to standard format without fractional seconds
        if let date = iso8601Standard.date(from: string) {
            return date
        }

        // Last resort: try removing fractional seconds entirely
        let withoutFractional = removeFractionalSeconds(string)
        return iso8601Standard.date(from: withoutFractional)
    }

    /// Truncates nanosecond precision to millisecond precision for ISO8601 parsing
    /// Input:  "2024-01-15T10:30:45.123456789Z"
    /// Output: "2024-01-15T10:30:45.123Z"
    static func truncateNanosecondsToMilliseconds(_ string: String) -> String {
        let range = NSRange(string.startIndex..., in: string)
        return nanosecondsRegex.stringByReplacingMatches(in: string, range: range, withTemplate: "$1.$2$3")
    }

    /// Removes fractional seconds entirely from ISO8601 timestamp
    /// Input:  "2024-01-15T10:30:45.123456789Z"
    /// Output: "2024-01-15T10:30:45Z"
    static func removeFractionalSeconds(_ string: String) -> String {
        let range = NSRange(string.startIndex..., in: string)
        return fractionalSecondsRegex.stringByReplacingMatches(in: string, range: range, withTemplate: "$1$2")
    }

    /// Extracts the entity ID from an event payload for history queries.
    /// Returns the ID of the entity (stack, task, reminder, device) that this event relates to.
    static func extractEntityId(from payload: [String: Any], eventType: String) -> String? {
        // Check for direct ID fields first (used in most payloads)
        if eventType.hasPrefix("stack.") {
            if let stackId = payload["stackId"] as? String {
                return stackId
            }
        } else if eventType.hasPrefix("task.") {
            if let taskId = payload["taskId"] as? String {
                return taskId
            }
        } else if eventType.hasPrefix("reminder.") {
            if let reminderId = payload["reminderId"] as? String {
                return reminderId
            }
        } else if eventType.hasPrefix("device.") {
            // Device events use state.id for entity ID (not deviceId which is the hardware ID)
            if let state = payload["state"] as? [String: Any],
               let entityId = state["id"] as? String {
                return entityId
            }
        }

        // Fallback: check for state.id (used in created/updated events)
        if let state = payload["state"] as? [String: Any],
           let entityId = state["id"] as? String {
            return entityId
        }

        // Fallback: check for fullState.id (used in updated events)
        if let fullState = payload["fullState"] as? [String: Any],
           let entityId = fullState["id"] as? String {
            return entityId
        }

        return nil
    }
}
