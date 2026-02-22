//
//  DequeueFocusFilter.swift
//  Dequeue
//
//  Focus Filter integration for iOS Focus modes.
//  When a Focus mode is active (Work, Personal, etc.), users can configure
//  which stacks are visible in Dequeue.
//

import AppIntents
import SwiftData
import os.log

// MARK: - Focus Filter

/// Configures Dequeue's behavior when a Focus mode is active.
///
/// Users can set this up in Settings > Focus > [Focus Name] > Focus Filters > Dequeue.
/// When active, only the selected stacks (or active stack only) will be shown.
@available(iOS 16.0, macOS 13.0, *)
struct DequeueFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Set Dequeue Filter"
    // swiftlint:disable:next redundant_type_annotation
    static let description: IntentDescription = IntentDescription(
        "Filter which stacks are visible when this Focus is active.",
        categoryName: "Focus"
    )

    /// When enabled, only the currently active stack is shown
    @Parameter(
        title: "Show Active Stack Only",
        description: "Only show the currently active stack when this Focus is on"
    )
    var showActiveStackOnly: Bool?

    /// Optional: specific stacks to show (if showActiveStackOnly is false)
    @Parameter(
        title: "Visible Stacks",
        description: "Choose specific stacks to show during this Focus"
    )
    var visibleStacks: [StackEntity]?

    /// Whether to suppress notifications for non-visible stacks
    @Parameter(
        title: "Mute Other Stacks",
        description: "Suppress reminder notifications for hidden stacks"
    )
    var muteOtherStacks: Bool?

    /// Display representation shown in Focus settings
    var displayRepresentation: DisplayRepresentation {
        if showActiveStackOnly == true {
            return DisplayRepresentation(
                title: "Active Stack Only",
                subtitle: "Only the active stack is visible"
            )
        } else if let stacks = visibleStacks, !stacks.isEmpty {
            let names = stacks.prefix(3).map(\.title).joined(separator: ", ")
            let suffix = stacks.count > 3 ? " +\(stacks.count - 3) more" : ""
            return DisplayRepresentation(
                title: "Selected Stacks",
                subtitle: "\(names)\(suffix)"
            )
        } else {
            return DisplayRepresentation(
                title: "All Stacks",
                subtitle: "No filter applied"
            )
        }
    }

    /// Called by the system when this Focus mode becomes active.
    /// Stores the filter configuration for the app to read.
    @MainActor
    func perform() async throws -> some IntentResult {
        let config = FocusFilterConfig(
            isActive: true,
            showActiveStackOnly: showActiveStackOnly ?? false,
            visibleStackIds: visibleStacks?.map(\.id) ?? [],
            muteOtherStacks: muteOtherStacks ?? false
        )

        FocusFilterConfig.save(config)
        // swiftlint:disable:next line_length
        os_log("[FocusFilter] Activated: activeOnly=\(config.showActiveStackOnly), stacks=\(config.visibleStackIds.count), muted=\(config.muteOtherStacks)")

        return .result()
    }
}

// MARK: - Focus Filter Configuration

/// Persisted configuration for the active Focus filter.
/// Stored in UserDefaults (App Group) so widgets and extensions can also read it.
struct FocusFilterConfig: Codable, Equatable, Sendable {
    /// Whether a focus filter is currently active
    var isActive: Bool

    /// Only show the active stack
    var showActiveStackOnly: Bool

    /// Specific stack IDs to show (empty = all stacks)
    var visibleStackIds: [String]

    /// Suppress notifications for non-visible stacks
    var muteOtherStacks: Bool

    // MARK: - Persistence

    private static let key = "com.dequeue.focusFilter"

    /// Save the current focus filter config
    static func save(_ config: FocusFilterConfig) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: key)

        // Also save to App Group for widgets
        if let groupDefaults = UserDefaults(suiteName: "group.com.ardonos.Dequeue") {
            groupDefaults.set(data, forKey: key)
        }
    }

    /// Load the current focus filter config (nil if no filter active)
    static func load() -> FocusFilterConfig? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(FocusFilterConfig.self, from: data)
    }

    /// Clear the focus filter (called when Focus mode deactivates)
    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        if let groupDefaults = UserDefaults(suiteName: "group.com.ardonos.Dequeue") {
            groupDefaults.removeObject(forKey: key)
        }
    }

    /// Returns an inactive (pass-through) config
    static var inactive: FocusFilterConfig {
        FocusFilterConfig(
            isActive: false,
            showActiveStackOnly: false,
            visibleStackIds: [],
            muteOtherStacks: false
        )
    }

    // MARK: - Filtering

    /// Check if a stack should be visible under the current filter
    func shouldShowStack(stackId: String, isActive: Bool) -> Bool {
        guard self.isActive else { return true }

        if showActiveStackOnly {
            return isActive
        }

        if !visibleStackIds.isEmpty {
            return visibleStackIds.contains(stackId)
        }

        // No specific filter — show all
        return true
    }

    /// Check if notifications should be suppressed for a stack
    func shouldMuteStack(stackId: String, isActive: Bool) -> Bool {
        guard self.isActive, muteOtherStacks else { return false }
        return !shouldShowStack(stackId: stackId, isActive: isActive)
    }
}
