//
//  CellularUploadWarning.swift
//  Dequeue
//
//  Warning dialog and coordinator for large file uploads on cellular
//

import SwiftUI
import os.log

// MARK: - Upload Decision

/// User's decision when prompted about cellular upload
enum CellularUploadDecision {
    case proceed
    case waitForWiFi
    case cancel
}

// MARK: - Cellular Upload Coordinator

/// Coordinates cellular upload warnings and WiFi waiting queue
@MainActor
@Observable
final class CellularUploadCoordinator {
    // MARK: - Configuration

    /// Minimum file size (in bytes) to trigger cellular warning
    static let warningThreshold: Int64 = 10 * 1_024 * 1_024  // 10 MB

    // MARK: - Properties

    private let networkMonitor: any NetworkMonitoring
    private let logger = Logger(subsystem: "com.dequeue", category: "CellularUploadCoordinator")

    /// Whether the warning dialog is currently shown
    var showWarning = false

    /// The file size for the current warning
    var pendingFileSize: Int64 = 0

    /// The filename for the current warning
    var pendingFilename: String = ""

    /// Files waiting for WiFi before upload
    private(set) var waitingForWiFi: [PendingUpload] = []

    /// Whether to skip warnings for this session
    var skipWarningsThisSession = false

    /// Continuation for async decision flow
    private var decisionContinuation: CheckedContinuation<CellularUploadDecision, Never>?

    // MARK: - Initialization

    init(networkMonitor: any NetworkMonitoring = NetworkMonitor.shared) {
        self.networkMonitor = networkMonitor
    }

    // MARK: - Public Methods

    /// Check if a file upload should show a cellular warning.
    ///
    /// Returns the user's decision after showing the warning dialog if needed.
    func checkUpload(fileSize: Int64, filename: String) async -> CellularUploadDecision {
        // No warning needed if:
        // - File is small enough
        // - Currently on WiFi
        // - User chose to skip warnings this session
        guard fileSize > Self.warningThreshold,
              !networkMonitor.isWiFi,
              !skipWarningsThisSession else {
            return .proceed
        }

        logger.info("Showing cellular warning for \(filename) (\(fileSize) bytes)")

        // Show warning and wait for user decision
        pendingFileSize = fileSize
        pendingFilename = filename
        showWarning = true

        return await withCheckedContinuation { continuation in
            self.decisionContinuation = continuation
        }
    }

    /// Handle user's decision from the warning dialog.
    func handleDecision(_ decision: CellularUploadDecision) {
        showWarning = false
        decisionContinuation?.resume(returning: decision)
        decisionContinuation = nil

        if decision == .waitForWiFi {
            logger.info("Queueing upload to wait for WiFi: \(self.pendingFilename)")
        }
    }

    /// Queue a file to upload when WiFi becomes available.
    func queueForWiFi(id: String, filename: String, fileSize: Int64, fileURL: URL) {
        let pending = PendingUpload(
            id: id,
            filename: filename,
            fileSize: fileSize,
            fileURL: fileURL,
            queuedAt: Date()
        )
        waitingForWiFi.append(pending)
        logger.info("Added to WiFi queue: \(filename)")
    }

    /// Get and clear pending uploads when WiFi connects.
    func getPendingUploadsForWiFi() -> [PendingUpload] {
        guard networkMonitor.isWiFi else { return [] }

        let pending = waitingForWiFi
        waitingForWiFi.removeAll()
        logger.info("Released \(pending.count) uploads from WiFi queue")
        return pending
    }

    /// Remove a specific upload from the waiting queue.
    func removeFromWiFiQueue(id: String) {
        waitingForWiFi.removeAll { $0.id == id }
    }

    /// Clear all waiting uploads.
    func clearWiFiQueue() {
        waitingForWiFi.removeAll()
    }
}

// MARK: - Pending Upload

/// Represents a file waiting for WiFi before upload
struct PendingUpload: Identifiable {
    let id: String
    let filename: String
    let fileSize: Int64
    let fileURL: URL
    let queuedAt: Date

    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
}

// MARK: - Cellular Warning Dialog

/// Alert dialog for cellular upload warning
struct CellularUploadWarningDialog: ViewModifier {
    @Bindable var coordinator: CellularUploadCoordinator
    @State private var dontAskAgain = false

    private var fileSizeText: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: coordinator.pendingFileSize)
    }

    func body(content: Content) -> some View {
        content
            .alert("Large File Upload", isPresented: $coordinator.showWarning) {
                Button("Upload Anyway") {
                    if dontAskAgain {
                        coordinator.skipWarningsThisSession = true
                    }
                    coordinator.handleDecision(.proceed)
                }

                Button("Wait for WiFi") {
                    coordinator.handleDecision(.waitForWiFi)
                }

                Button("Cancel", role: .cancel) {
                    coordinator.handleDecision(.cancel)
                }
            } message: {
                VStack {
                    Text("This file is \(fileSizeText). Uploading on cellular may use significant data.")
                }
            }
    }
}

extension View {
    /// Adds cellular upload warning dialog capability.
    func cellularUploadWarning(coordinator: CellularUploadCoordinator) -> some View {
        modifier(CellularUploadWarningDialog(coordinator: coordinator))
    }
}

// MARK: - WiFi Waiting Status View

/// Shows status when files are waiting for WiFi
struct WiFiWaitingStatusView: View {
    let pendingCount: Int
    var onCancel: (() -> Void)?

    var body: some View {
        if pendingCount > 0 {
            HStack(spacing: 12) {
                Image(systemName: "wifi")
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Waiting for WiFi")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text("\(pendingCount) \(pendingCount == 1 ? "file" : "files") queued")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let onCancel {
                    Button("Cancel", role: .destructive) {
                        onCancel()
                    }
                    .font(.caption)
                }
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Previews

#Preview("WiFi Waiting Status") {
    VStack(spacing: 16) {
        WiFiWaitingStatusView(pendingCount: 1) { }
        WiFiWaitingStatusView(pendingCount: 3) { }
    }
    .padding()
}
