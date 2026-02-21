//
//  AttachmentDownloadCoordinatorTests.swift
//  DequeueTests
//
//  Tests for AttachmentDownloadCoordinator download orchestration
//

import Testing
import Foundation
@testable import Dequeue

private typealias Attachment = Dequeue.Attachment

// MARK: - Tests

@Suite("AttachmentDownloadCoordinator Tests")
@MainActor
struct AttachmentDownloadCoordinatorTests {

    // MARK: - Helpers

    private func makeCoordinator(
        downloadBehavior: AttachmentDownloadBehavior = .always
    ) -> (AttachmentDownloadCoordinator, AttachmentSettings) {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let settings = AttachmentSettings(defaults: defaults)
        settings.downloadBehavior = downloadBehavior

        let coordinator = AttachmentDownloadCoordinator(settings: settings)
        return (coordinator, settings)
    }

    private func makeAttachment(id: String = CUID.generate(), filename: String = "test.pdf") -> Attachment {
        Attachment(
            id: id,
            parentId: "stack-1",
            parentType: .stack,
            filename: filename,
            mimeType: "application/pdf",
            sizeBytes: 1024
        )
    }

    // MARK: - shouldAutoDownload Tests

    @Test("shouldAutoDownload returns false for onDemand mode")
    func shouldAutoDownloadOnDemand() {
        let (coordinator, _) = makeCoordinator(downloadBehavior: .onDemand)
        // On-demand should never auto-download regardless of network
        #expect(coordinator.shouldAutoDownload() == false)
    }

    @Test("shouldAutoDownload returns true for always mode")
    func shouldAutoDownloadAlways() {
        let (coordinator, _) = makeCoordinator(downloadBehavior: .always)
        #expect(coordinator.shouldAutoDownload() == true)
    }

    // MARK: - Initial State Tests

    @Test("Coordinator starts with empty state")
    func initialState() {
        let (coordinator, _) = makeCoordinator()

        #expect(coordinator.pendingDownloads.isEmpty)
        #expect(coordinator.isAutoDownloading == false)
        #expect(coordinator.overallProgress == 0)
        #expect(coordinator.completedCount == 0)
    }

    // MARK: - queueForDownload Tests

    @Test("queueForDownload adds attachment to pending list")
    func queueAddsAttachment() async {
        let (coordinator, _) = makeCoordinator(downloadBehavior: .onDemand)
        let attachment = makeAttachment()

        await coordinator.queueForDownload(attachment)

        #expect(coordinator.pendingDownloads.count == 1)
        #expect(coordinator.pendingDownloads.first?.id == attachment.id)
    }

    @Test("queueForDownload does not add duplicate attachments")
    func queueNoDuplicates() async {
        let (coordinator, _) = makeCoordinator(downloadBehavior: .onDemand)
        let attachment = makeAttachment(id: "unique-id")

        await coordinator.queueForDownload(attachment)
        await coordinator.queueForDownload(attachment)

        #expect(coordinator.pendingDownloads.count == 1)
    }

    @Test("queueForDownload triggers auto-download when conditions allow")
    func queueTriggersAutoDownload() async {
        let (coordinator, _) = makeCoordinator(downloadBehavior: .always)
        var downloadedIds: [String] = []

        coordinator.downloadHandler = { attachment in
            downloadedIds.append(attachment.id)
            return URL(fileURLWithPath: "/tmp/\(attachment.filename)")
        }

        let attachment = makeAttachment()
        await coordinator.queueForDownload(attachment)

        // With always mode, queueing should trigger download
        #expect(downloadedIds.contains(attachment.id))
    }

    // MARK: - evaluateAutoDownloads Tests

    @Test("evaluateAutoDownloads does nothing without provider")
    func evaluateWithoutProvider() async {
        let (coordinator, _) = makeCoordinator(downloadBehavior: .always)

        // Should not crash when no provider is set
        await coordinator.evaluateAutoDownloads()

        #expect(coordinator.isAutoDownloading == false)
    }

    @Test("evaluateAutoDownloads does nothing with empty pending list")
    func evaluateWithEmptyPending() async {
        let (coordinator, _) = makeCoordinator(downloadBehavior: .always)
        coordinator.pendingAttachmentsProvider = { [] }

        await coordinator.evaluateAutoDownloads()

        #expect(coordinator.isAutoDownloading == false)
        #expect(coordinator.completedCount == 0)
    }

    @Test("evaluateAutoDownloads downloads pending attachments")
    func evaluateDownloadsPending() async {
        let (coordinator, _) = makeCoordinator(downloadBehavior: .always)
        let attachment1 = makeAttachment(id: "a1", filename: "file1.pdf")
        let attachment2 = makeAttachment(id: "a2", filename: "file2.pdf")
        var downloadedIds: [String] = []

        coordinator.pendingAttachmentsProvider = { [attachment1, attachment2] }
        coordinator.downloadHandler = { attachment in
            downloadedIds.append(attachment.id)
            return URL(fileURLWithPath: "/tmp/\(attachment.filename)")
        }

        await coordinator.evaluateAutoDownloads()

        #expect(downloadedIds.count == 2)
        #expect(downloadedIds.contains("a1"))
        #expect(downloadedIds.contains("a2"))
        #expect(coordinator.completedCount == 2)
        #expect(coordinator.overallProgress == 1.0)
    }

    @Test("evaluateAutoDownloads continues past individual download errors")
    func evaluateContinuesOnError() async {
        let (coordinator, _) = makeCoordinator(downloadBehavior: .always)
        let attachment1 = makeAttachment(id: "a1", filename: "file1.pdf")
        let attachment2 = makeAttachment(id: "a2", filename: "file2.pdf")
        var downloadedIds: [String] = []

        coordinator.pendingAttachmentsProvider = { [attachment1, attachment2] }
        coordinator.downloadHandler = { attachment in
            if attachment.id == "a1" {
                throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Download failed"])
            }
            downloadedIds.append(attachment.id)
            return URL(fileURLWithPath: "/tmp/\(attachment.filename)")
        }

        await coordinator.evaluateAutoDownloads()

        // First failed, second should still succeed
        #expect(downloadedIds == ["a2"])
        #expect(coordinator.completedCount == 1)
    }

    @Test("evaluateAutoDownloads skipped when onDemand mode")
    func evaluateSkipsOnDemand() async {
        let (coordinator, _) = makeCoordinator(downloadBehavior: .onDemand)
        var downloadCalled = false

        coordinator.pendingAttachmentsProvider = { [self.makeAttachment()] }
        coordinator.downloadHandler = { _ in
            downloadCalled = true
            return URL(fileURLWithPath: "/tmp/test")
        }

        await coordinator.evaluateAutoDownloads()

        #expect(downloadCalled == false)
    }

    // MARK: - cancelAutoDownloads Tests

    @Test("cancelAutoDownloads sets isAutoDownloading to false")
    func cancelStopsDownloading() {
        let (coordinator, _) = makeCoordinator()

        coordinator.cancelAutoDownloads()

        #expect(coordinator.isAutoDownloading == false)
    }

    // MARK: - clearPendingDownloads Tests

    @Test("clearPendingDownloads resets all state")
    func clearResetsState() async {
        let (coordinator, _) = makeCoordinator(downloadBehavior: .onDemand)

        // Queue some attachments first
        await coordinator.queueForDownload(makeAttachment(id: "a1"))
        await coordinator.queueForDownload(makeAttachment(id: "a2"))
        #expect(coordinator.pendingDownloads.count == 2)

        coordinator.clearPendingDownloads()

        #expect(coordinator.pendingDownloads.isEmpty)
        #expect(coordinator.completedCount == 0)
        #expect(coordinator.overallProgress == 0)
    }

    // MARK: - handleSettingsChange Tests

    @Test("handleSettingsChange triggers evaluation when changing to auto mode")
    func settingsChangeTriggerEvaluation() async {
        let (coordinator, _) = makeCoordinator(downloadBehavior: .always)
        var providerCalled = false

        coordinator.pendingAttachmentsProvider = {
            providerCalled = true
            return []
        }

        await coordinator.handleSettingsChange(from: .onDemand, to: .always)

        #expect(providerCalled == true)
    }

    @Test("handleSettingsChange does NOT trigger evaluation when changing to onDemand")
    func settingsChangeToOnDemandNoEvaluation() async {
        let (coordinator, _) = makeCoordinator(downloadBehavior: .onDemand)
        var providerCalled = false

        coordinator.pendingAttachmentsProvider = {
            providerCalled = true
            return []
        }

        await coordinator.handleSettingsChange(from: .always, to: .onDemand)

        #expect(providerCalled == false)
    }

    @Test("handleSettingsChange triggers evaluation for wifiOnly")
    func settingsChangeToWifiOnly() async {
        let (coordinator, _) = makeCoordinator(downloadBehavior: .wifiOnly)
        var providerCalled = false

        coordinator.pendingAttachmentsProvider = {
            providerCalled = true
            return []
        }

        await coordinator.handleSettingsChange(from: .onDemand, to: .wifiOnly)

        #expect(providerCalled == true)
    }

    // MARK: - Progress Tracking Tests

    @Test("Progress tracks correctly through batch download")
    func progressTracking() async {
        let (coordinator, _) = makeCoordinator(downloadBehavior: .always)
        let attachments = (1...4).map { makeAttachment(id: "a\($0)", filename: "file\($0).pdf") }
        var progressValues: [Double] = []

        coordinator.pendingAttachmentsProvider = { attachments }
        coordinator.downloadHandler = { [coordinator] attachment in
            progressValues.append(coordinator.overallProgress)
            return URL(fileURLWithPath: "/tmp/\(attachment.filename)")
        }

        await coordinator.evaluateAutoDownloads()

        #expect(coordinator.completedCount == 4)
        #expect(coordinator.overallProgress == 1.0)
        // Progress should have been incremented for each download
        #expect(progressValues.count == 4)
    }

    // MARK: - No Download Handler Tests

    @Test("evaluateAutoDownloads does nothing without download handler")
    func evaluateWithoutHandler() async {
        let (coordinator, _) = makeCoordinator(downloadBehavior: .always)
        coordinator.pendingAttachmentsProvider = { [self.makeAttachment()] }
        // downloadHandler is nil

        await coordinator.evaluateAutoDownloads()

        // Should complete without crash, no downloads made
        #expect(coordinator.isAutoDownloading == false)
    }
}
