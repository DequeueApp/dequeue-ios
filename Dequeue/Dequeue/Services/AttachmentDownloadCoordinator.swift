//
//  AttachmentDownloadCoordinator.swift
//  Dequeue
//
//  Coordinates attachment downloads based on user settings and network state
//

import Foundation
import os.log
import Observation
import Combine

// MARK: - Download Coordinator

/// Coordinates attachment downloads based on user settings and network conditions.
///
/// This coordinator monitors:
/// - User download mode settings (on-demand, WiFi-only, always)
/// - Network connectivity (WiFi vs cellular)
/// - Pending attachments that need downloading
///
/// When conditions align (e.g., user enables WiFi-only mode and WiFi connects),
/// it triggers auto-downloads for pending attachments.
@MainActor
@Observable
final class AttachmentDownloadCoordinator {
    // MARK: - Properties

    private let settings: AttachmentSettings
    private let networkMonitor: NetworkMonitor
    private let logger = Logger(subsystem: "com.dequeue", category: "AttachmentDownloadCoordinator")

    /// Pending attachments that need to be downloaded when conditions allow
    private(set) var pendingDownloads: [Attachment] = []

    /// Whether auto-downloads are currently active
    private(set) var isAutoDownloading = false

    /// Current download progress (0.0 to 1.0 for overall progress)
    private(set) var overallProgress: Double = 0

    /// Number of attachments downloaded in current batch
    private(set) var completedCount = 0

    /// Handler for actually performing the download
    var downloadHandler: ((Attachment) async throws -> URL)?

    /// Handler for getting attachments that need downloading
    var pendingAttachmentsProvider: (() async -> [Attachment])?

    // MARK: - Initialization

    init(settings: AttachmentSettings, networkMonitor: NetworkMonitor = .shared) {
        self.settings = settings
        self.networkMonitor = networkMonitor
    }

    // MARK: - Public Methods

    /// Determine if an attachment should be auto-downloaded based on current settings and network.
    func shouldAutoDownload() -> Bool {
        settings.shouldAutoDownload(isOnWiFi: networkMonitor.isWiFi)
    }

    /// Check conditions and trigger auto-downloads if appropriate.
    ///
    /// Call this:
    /// - When network status changes
    /// - When settings change
    /// - When new attachments are added
    func evaluateAutoDownloads() async {
        guard shouldAutoDownload() else {
            logger.debug("Auto-download conditions not met")
            return
        }

        guard !isAutoDownloading else {
            logger.debug("Auto-download already in progress")
            return
        }

        guard let provider = pendingAttachmentsProvider else {
            logger.warning("No pending attachments provider configured")
            return
        }

        // Get attachments that need downloading
        let pending = await provider()
        guard !pending.isEmpty else {
            logger.debug("No attachments pending download")
            return
        }

        pendingDownloads = pending
        logger.info("Starting auto-download of \(pending.count) attachments")

        await performAutoDownloads()
    }

    /// Add an attachment to the pending queue and trigger download if conditions allow.
    func queueForDownload(_ attachment: Attachment) async {
        if !pendingDownloads.contains(where: { $0.id == attachment.id }) {
            pendingDownloads.append(attachment)
        }

        if shouldAutoDownload() && !isAutoDownloading {
            await performAutoDownloads()
        }
    }

    /// Cancel any ongoing auto-downloads.
    func cancelAutoDownloads() {
        isAutoDownloading = false
        logger.info("Auto-downloads cancelled")
    }

    /// Clear all pending downloads.
    func clearPendingDownloads() {
        pendingDownloads.removeAll()
        completedCount = 0
        overallProgress = 0
    }

    // MARK: - Private Methods

    private func performAutoDownloads() async {
        guard let downloadHandler else {
            logger.warning("No download handler configured")
            return
        }

        isAutoDownloading = true
        completedCount = 0
        overallProgress = 0

        let total = pendingDownloads.count

        for (index, attachment) in pendingDownloads.enumerated() {
            // Check if we should continue downloading
            guard isAutoDownloading else {
                logger.info("Auto-downloads stopped")
                break
            }

            // Re-check network conditions before each download
            guard shouldAutoDownload() else {
                logger.info("Network conditions changed, pausing auto-downloads")
                break
            }

            do {
                logger.debug("Auto-downloading: \(attachment.filename)")
                _ = try await downloadHandler(attachment)
                completedCount += 1
                overallProgress = Double(completedCount) / Double(total)
                logger.debug("Downloaded \(self.completedCount)/\(total): \(attachment.filename)")
            } catch {
                logger.error("Failed to download \(attachment.filename): \(error.localizedDescription)")
                // Continue with next file on error
            }
        }

        // Remove successfully downloaded items from pending
        pendingDownloads.removeFirst(min(completedCount, pendingDownloads.count))

        isAutoDownloading = false
        logger.info("Auto-download batch complete: \(self.completedCount)/\(total)")
    }
}

// MARK: - Network Change Observation

extension AttachmentDownloadCoordinator {
    /// Start observing network changes to trigger auto-downloads.
    ///
    /// Call this when the app becomes active or when settings change.
    func startObservingNetworkChanges() async {
        // Initial evaluation
        await evaluateAutoDownloads()

        // Note: For continuous observation, the view layer should
        // call evaluateAutoDownloads() when networkMonitor.isConnected
        // or networkMonitor.isWiFi changes using .onChange modifier
    }
}

// MARK: - Settings Change Handling

extension AttachmentDownloadCoordinator {
    /// Handle when download mode setting changes.
    ///
    /// If user changes to a more permissive mode (e.g., from on-demand to always),
    /// evaluate if we should start downloading.
    func handleSettingsChange(from oldBehavior: AttachmentDownloadBehavior,
                              to newBehavior: AttachmentDownloadBehavior) async {
        logger.info("Download behavior changed: \(oldBehavior.rawValue) -> \(newBehavior.rawValue)")

        // If new setting allows auto-download, evaluate pending downloads
        if newBehavior != .onDemand {
            await evaluateAutoDownloads()
        }
    }
}
