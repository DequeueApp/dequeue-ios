//
//  StorageQuotaHandler.swift
//  Dequeue
//
//  Handles storage quota exceeded scenarios with user-friendly dialogs
//

import SwiftUI
import os.log

// MARK: - Quota Check Result

/// Result of checking storage quota before an upload
enum QuotaCheckResult {
    case allowed
    case wouldExceed(currentUsed: Int64, quota: Int64, fileSize: Int64)
    case quotaExceeded(used: Int64, quota: Int64)
}

// MARK: - Quota Error

/// Error representing quota exceeded from backend
struct QuotaExceededError: Error, LocalizedError {
    let used: Int64
    let quota: Int64

    var errorDescription: String? {
        "Storage quota exceeded"
    }

    var recoverySuggestion: String? {
        "Free up space by removing attachments or increase your quota in Settings."
    }
}

// MARK: - User Decision

/// User's decision when quota is exceeded
enum QuotaExceededDecision {
    case manageStorage
    case increaseQuota
    case cancel
}

// MARK: - Storage Quota Handler

/// Handles storage quota checking and exceeded scenarios
@MainActor
@Observable
final class StorageQuotaHandler {
    // MARK: - Properties

    private let logger = Logger(subsystem: "com.dequeue", category: "StorageQuotaHandler")

    /// Whether the quota exceeded dialog is shown
    var showQuotaExceededDialog = false

    /// Current storage used (for display in dialog)
    var currentUsed: Int64 = 0

    /// Current quota limit (for display in dialog)
    var currentQuota: Int64 = 0

    /// Navigation flag for settings
    var shouldNavigateToSettings = false

    /// Navigation flag for quota picker
    var shouldShowQuotaPicker = false

    /// Continuation for async decision flow
    private var decisionContinuation: CheckedContinuation<QuotaExceededDecision, Never>?

    // MARK: - Public Methods

    /// Check if an upload would exceed the local storage quota.
    ///
    /// - Parameters:
    ///   - currentUsed: Current storage used in bytes
    ///   - quota: Storage quota limit in bytes (0 = unlimited)
    ///   - fileSize: Size of file to upload
    /// - Returns: QuotaCheckResult indicating if upload is allowed
    func checkQuota(currentUsed: Int64, quota: Int64, fileSize: Int64) -> QuotaCheckResult {
        // Unlimited quota
        guard quota > 0 else {
            return .allowed
        }

        // Already at or over quota
        if currentUsed >= quota {
            return .quotaExceeded(used: currentUsed, quota: quota)
        }

        // Would exceed with this file
        if currentUsed + fileSize > quota {
            return .wouldExceed(currentUsed: currentUsed, quota: quota, fileSize: fileSize)
        }

        return .allowed
    }

    /// Handle a quota exceeded error and get user's decision.
    ///
    /// Shows a dialog with options to manage storage, increase quota, or cancel.
    func handleQuotaExceeded(used: Int64, quota: Int64) async -> QuotaExceededDecision {
        logger.warning("Storage quota exceeded: \(used)/\(quota) bytes")

        currentUsed = used
        currentQuota = quota
        showQuotaExceededDialog = true

        return await withCheckedContinuation { continuation in
            self.decisionContinuation = continuation
        }
    }

    /// Handle user's decision from the dialog.
    func handleDecision(_ decision: QuotaExceededDecision) {
        showQuotaExceededDialog = false

        switch decision {
        case .manageStorage:
            shouldNavigateToSettings = true
        case .increaseQuota:
            shouldShowQuotaPicker = true
        case .cancel:
            break
        }

        decisionContinuation?.resume(returning: decision)
        decisionContinuation = nil
    }

    /// Reset navigation flags after handling.
    func resetNavigationFlags() {
        shouldNavigateToSettings = false
        shouldShowQuotaPicker = false
    }
}

// MARK: - Quota Exceeded Dialog

/// Alert dialog for quota exceeded scenario
struct StorageQuotaExceededDialog: ViewModifier {
    @Bindable var handler: StorageQuotaHandler

    private var usageText: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file

        let usedStr = formatter.string(fromByteCount: handler.currentUsed)
        let quotaStr = formatter.string(fromByteCount: handler.currentQuota)
        return "\(usedStr) of \(quotaStr)"
    }

    func body(content: Content) -> some View {
        content
            .alert("Storage Full", isPresented: $handler.showQuotaExceededDialog) {
                Button("Manage Storage") {
                    handler.handleDecision(.manageStorage)
                }

                Button("Increase Quota") {
                    handler.handleDecision(.increaseQuota)
                }

                Button("Cancel", role: .cancel) {
                    handler.handleDecision(.cancel)
                }
            } message: {
                // swiftlint:disable:next line_length
                Text("You've used all your attachment storage (\(usageText)). Free up space by removing attachments or increase your quota in Settings.")
            }
    }
}

extension View {
    /// Adds storage quota exceeded dialog capability.
    func storageQuotaExceededDialog(handler: StorageQuotaHandler) -> some View {
        modifier(StorageQuotaExceededDialog(handler: handler))
    }
}

// MARK: - Quota Warning Banner

/// Banner shown when approaching storage quota
struct StorageQuotaWarningBanner: View {
    let usedPercentage: Double
    var onManageStorage: (() -> Void)?

    private var isWarning: Bool {
        usedPercentage >= 0.8 && usedPercentage < 1.0
    }

    private var isFull: Bool {
        usedPercentage >= 1.0
    }

    var body: some View {
        if isWarning || isFull {
            HStack(spacing: 12) {
                Image(systemName: isFull ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(isFull ? .red : .orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text(isFull ? "Storage Full" : "Storage Almost Full")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(isFull
                         ? "Remove attachments to add more"
                         : "\(Int(usedPercentage * 100))% of storage used")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let onManageStorage {
                    Button("Manage") {
                        onManageStorage()
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
            }
            .padding()
            .background(
                (isFull ? Color.red : Color.orange).opacity(0.1),
                in: RoundedRectangle(cornerRadius: 12)
            )
        }
    }
}

// MARK: - Previews

#Preview("Warning Banner - 85%") {
    VStack {
        StorageQuotaWarningBanner(usedPercentage: 0.85) { }
    }
    .padding()
}

#Preview("Warning Banner - Full") {
    VStack {
        StorageQuotaWarningBanner(usedPercentage: 1.0) { }
    }
    .padding()
}
