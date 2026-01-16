//
//  CellularUploadCoordinatorTests.swift
//  DequeueTests
//
//  Tests for CellularUploadCoordinator
//

import Testing
import Foundation
import Network
@testable import Dequeue

@Suite("CellularUploadCoordinator Tests")
@MainActor
struct CellularUploadCoordinatorTests {

    // MARK: - checkUpload Tests

    @Test("Small files proceed without warning")
    func smallFilesProceed() async {
        let mockMonitor = MockNetworkMonitor(isWiFi: false, isCellular: true)
        let coordinator = CellularUploadCoordinator(networkMonitor: mockMonitor)

        // File under 10 MB threshold
        let decision = await coordinator.checkUpload(
            fileSize: 5 * 1_024 * 1_024,  // 5 MB
            filename: "small.jpg"
        )

        #expect(decision == .proceed)
        #expect(!coordinator.showWarning)
    }

    @Test("Large files on WiFi proceed without warning")
    func wifiLargeFilesProceed() async {
        let mockMonitor = MockNetworkMonitor(isWiFi: true, isCellular: false)
        let coordinator = CellularUploadCoordinator(networkMonitor: mockMonitor)

        // Large file but on WiFi
        let decision = await coordinator.checkUpload(
            fileSize: 50 * 1_024 * 1_024,  // 50 MB
            filename: "large.jpg"
        )

        #expect(decision == .proceed)
        #expect(!coordinator.showWarning)
    }

    @Test("Skip warnings flag bypasses check")
    func skipWarningsBypassesCheck() async {
        let mockMonitor = MockNetworkMonitor(isWiFi: false, isCellular: true)
        let coordinator = CellularUploadCoordinator(networkMonitor: mockMonitor)
        coordinator.skipWarningsThisSession = true

        // Large file on cellular but warnings skipped
        let decision = await coordinator.checkUpload(
            fileSize: 50 * 1_024 * 1_024,  // 50 MB
            filename: "large.jpg"
        )

        #expect(decision == .proceed)
        #expect(!coordinator.showWarning)
    }

    @Test("Large file on cellular triggers warning state")
    func largeFileOnCellularTriggersWarning() async {
        let mockMonitor = MockNetworkMonitor(isWiFi: false, isCellular: true)
        let coordinator = CellularUploadCoordinator(networkMonitor: mockMonitor)

        // Start the check in a task
        let checkTask = Task {
            await coordinator.checkUpload(
                fileSize: 50 * 1_024 * 1_024,  // 50 MB
                filename: "large.jpg"
            )
        }

        // Give it a moment to set up the warning
        try? await Task.sleep(for: .milliseconds(50))

        // Verify warning is shown
        #expect(coordinator.showWarning)
        #expect(coordinator.pendingFileSize == 50 * 1_024 * 1_024)
        #expect(coordinator.pendingFilename == "large.jpg")

        // Clean up by handling the decision
        coordinator.handleDecision(.cancel)
        _ = await checkTask.value
    }

    // MARK: - Decision Handling Tests

    @Test("Handle decision proceed completes successfully")
    func handleProceedDecision() async {
        let mockMonitor = MockNetworkMonitor(isWiFi: false, isCellular: true)
        let coordinator = CellularUploadCoordinator(networkMonitor: mockMonitor)

        let checkTask = Task {
            await coordinator.checkUpload(
                fileSize: 50 * 1_024 * 1_024,
                filename: "test.jpg"
            )
        }

        try? await Task.sleep(for: .milliseconds(50))

        coordinator.handleDecision(.proceed)
        let decision = await checkTask.value

        #expect(decision == .proceed)
        #expect(!coordinator.showWarning)
    }

    @Test("Handle decision cancel completes successfully")
    func handleCancelDecision() async {
        let mockMonitor = MockNetworkMonitor(isWiFi: false, isCellular: true)
        let coordinator = CellularUploadCoordinator(networkMonitor: mockMonitor)

        let checkTask = Task {
            await coordinator.checkUpload(
                fileSize: 50 * 1_024 * 1_024,
                filename: "test.jpg"
            )
        }

        try? await Task.sleep(for: .milliseconds(50))

        coordinator.handleDecision(.cancel)
        let decision = await checkTask.value

        #expect(decision == .cancel)
        #expect(!coordinator.showWarning)
    }

    @Test("Handle decision waitForWiFi completes successfully")
    func handleWaitForWiFiDecision() async {
        let mockMonitor = MockNetworkMonitor(isWiFi: false, isCellular: true)
        let coordinator = CellularUploadCoordinator(networkMonitor: mockMonitor)

        let checkTask = Task {
            await coordinator.checkUpload(
                fileSize: 50 * 1_024 * 1_024,
                filename: "test.jpg"
            )
        }

        try? await Task.sleep(for: .milliseconds(50))

        coordinator.handleDecision(.waitForWiFi)
        let decision = await checkTask.value

        #expect(decision == .waitForWiFi)
        #expect(!coordinator.showWarning)
    }

    // MARK: - WiFi Queue Tests

    @Test("Queue for WiFi adds pending upload")
    func queueForWiFiAddsUpload() {
        let mockMonitor = MockNetworkMonitor(isWiFi: false, isCellular: true)
        let coordinator = CellularUploadCoordinator(networkMonitor: mockMonitor)

        // swiftlint:disable:next force_unwrapping
        let testURL = URL(string: "file:///test/file.jpg")!

        coordinator.queueForWiFi(
            id: "test-id",
            filename: "test.jpg",
            fileSize: 10_000_000,
            fileURL: testURL
        )

        #expect(coordinator.waitingForWiFi.count == 1)
        #expect(coordinator.waitingForWiFi.first?.id == "test-id")
        #expect(coordinator.waitingForWiFi.first?.filename == "test.jpg")
    }

    @Test("Get pending uploads returns empty on cellular")
    func getPendingReturnsEmptyOnCellular() {
        let mockMonitor = MockNetworkMonitor(isWiFi: false, isCellular: true)
        let coordinator = CellularUploadCoordinator(networkMonitor: mockMonitor)

        // swiftlint:disable:next force_unwrapping
        let testURL = URL(string: "file:///test/file.jpg")!

        coordinator.queueForWiFi(
            id: "test-id",
            filename: "test.jpg",
            fileSize: 10_000_000,
            fileURL: testURL
        )

        let pending = coordinator.getPendingUploadsForWiFi()

        #expect(pending.isEmpty)
        #expect(coordinator.waitingForWiFi.count == 1)  // Queue not cleared
    }

    @Test("Get pending uploads returns and clears queue on WiFi")
    func getPendingReturnsAndClearsOnWiFi() {
        let mockMonitor = MockNetworkMonitor(isWiFi: true, isCellular: false)
        let coordinator = CellularUploadCoordinator(networkMonitor: mockMonitor)

        // swiftlint:disable:next force_unwrapping
        let testURL = URL(string: "file:///test/file.jpg")!

        coordinator.queueForWiFi(
            id: "test-id",
            filename: "test.jpg",
            fileSize: 10_000_000,
            fileURL: testURL
        )

        let pending = coordinator.getPendingUploadsForWiFi()

        #expect(pending.count == 1)
        #expect(pending.first?.id == "test-id")
        #expect(coordinator.waitingForWiFi.isEmpty)  // Queue cleared
    }

    @Test("Remove from WiFi queue by ID")
    func removeFromQueueById() {
        let mockMonitor = MockNetworkMonitor(isWiFi: false, isCellular: true)
        let coordinator = CellularUploadCoordinator(networkMonitor: mockMonitor)

        // swiftlint:disable:next force_unwrapping
        let testURL = URL(string: "file:///test/file.jpg")!

        coordinator.queueForWiFi(id: "id-1", filename: "test1.jpg", fileSize: 1000, fileURL: testURL)
        coordinator.queueForWiFi(id: "id-2", filename: "test2.jpg", fileSize: 2000, fileURL: testURL)
        coordinator.queueForWiFi(id: "id-3", filename: "test3.jpg", fileSize: 3000, fileURL: testURL)

        coordinator.removeFromWiFiQueue(id: "id-2")

        #expect(coordinator.waitingForWiFi.count == 2)
        #expect(!coordinator.waitingForWiFi.contains { $0.id == "id-2" })
        #expect(coordinator.waitingForWiFi.contains { $0.id == "id-1" })
        #expect(coordinator.waitingForWiFi.contains { $0.id == "id-3" })
    }

    @Test("Clear WiFi queue removes all items")
    func clearQueueRemovesAll() {
        let mockMonitor = MockNetworkMonitor(isWiFi: false, isCellular: true)
        let coordinator = CellularUploadCoordinator(networkMonitor: mockMonitor)

        // swiftlint:disable:next force_unwrapping
        let testURL = URL(string: "file:///test/file.jpg")!

        coordinator.queueForWiFi(id: "id-1", filename: "test1.jpg", fileSize: 1000, fileURL: testURL)
        coordinator.queueForWiFi(id: "id-2", filename: "test2.jpg", fileSize: 2000, fileURL: testURL)

        coordinator.clearWiFiQueue()

        #expect(coordinator.waitingForWiFi.isEmpty)
    }

    // MARK: - Threshold Tests

    @Test("Warning threshold is 10 MB")
    func warningThresholdIs10MB() {
        #expect(CellularUploadCoordinator.warningThreshold == 10 * 1_024 * 1_024)
    }

    @Test("File at exactly threshold triggers warning")
    func fileAtThresholdTriggersWarning() async {
        let mockMonitor = MockNetworkMonitor(isWiFi: false, isCellular: true)
        let coordinator = CellularUploadCoordinator(networkMonitor: mockMonitor)

        let checkTask = Task {
            await coordinator.checkUpload(
                fileSize: CellularUploadCoordinator.warningThreshold + 1,
                filename: "threshold.jpg"
            )
        }

        try? await Task.sleep(for: .milliseconds(50))

        #expect(coordinator.showWarning)

        coordinator.handleDecision(.cancel)
        _ = await checkTask.value
    }

    @Test("File just under threshold proceeds")
    func fileJustUnderThresholdProceeds() async {
        let mockMonitor = MockNetworkMonitor(isWiFi: false, isCellular: true)
        let coordinator = CellularUploadCoordinator(networkMonitor: mockMonitor)

        let decision = await coordinator.checkUpload(
            fileSize: CellularUploadCoordinator.warningThreshold - 1,
            filename: "under.jpg"
        )

        #expect(decision == .proceed)
        #expect(!coordinator.showWarning)
    }
}

// MARK: - Mock NetworkMonitor

/// Test-only mock for testing cellular upload scenarios without real network monitoring
@MainActor
@Observable
private final class MockNetworkMonitor: NetworkMonitoring {
    var isConnected: Bool
    var connectionType: Network.NWInterface.InterfaceType?

    init(isWiFi: Bool, isCellular: Bool) {
        self.isConnected = isWiFi || isCellular

        if isWiFi {
            self.connectionType = .wifi
        } else if isCellular {
            self.connectionType = .cellular
        } else {
            self.connectionType = nil
        }
    }

    var isWiFi: Bool {
        connectionType == .wifi
    }

    var isCellular: Bool {
        connectionType == .cellular
    }
}
