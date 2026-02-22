//
//  StorageQuotaHandlerTests.swift
//  DequeueTests
//
//  Tests for StorageQuotaHandler, QuotaCheckResult, and related types.
//

import Testing
import Foundation
@testable import Dequeue

// MARK: - QuotaCheckResult Tests

@Suite("QuotaCheckResult Tests")
@MainActor
struct QuotaCheckResultTests {
    @Test("allowed case")
    func allowedCase() {
        let result = QuotaCheckResult.allowed

        if case .allowed = result {
            // pass
        } else {
            Issue.record("Expected .allowed")
        }
    }

    @Test("wouldExceed case contains correct values")
    func wouldExceedCase() {
        let result = QuotaCheckResult.wouldExceed(
            currentUsed: 500,
            quota: 1000,
            fileSize: 600
        )

        if case .wouldExceed(let used, let quota, let size) = result {
            #expect(used == 500)
            #expect(quota == 1000)
            #expect(size == 600)
        } else {
            Issue.record("Expected .wouldExceed")
        }
    }

    @Test("quotaExceeded case contains correct values")
    func quotaExceededCase() {
        let result = QuotaCheckResult.quotaExceeded(
            used: 1000,
            quota: 1000
        )

        if case .quotaExceeded(let used, let quota) = result {
            #expect(used == 1000)
            #expect(quota == 1000)
        } else {
            Issue.record("Expected .quotaExceeded")
        }
    }
}

// MARK: - QuotaExceededError Tests

@Suite("QuotaExceededError Tests")
@MainActor
struct QuotaExceededErrorTests {
    @Test("errorDescription is correct")
    func errorDescription() {
        let error = QuotaExceededError(used: 500, quota: 1000)
        #expect(error.errorDescription == "Storage quota exceeded")
    }

    @Test("recoverySuggestion is correct")
    func recoverySuggestion() {
        let error = QuotaExceededError(used: 500, quota: 1000)
        #expect(
            error.recoverySuggestion ==
            "Free up space by removing attachments or increase your quota in Settings."
        )
    }

    @Test("stores used and quota values")
    func storesValues() {
        let error = QuotaExceededError(used: 750, quota: 1000)
        #expect(error.used == 750)
        #expect(error.quota == 1000)
    }

    @Test("conforms to LocalizedError")
    func conformsToLocalizedError() {
        let error: LocalizedError = QuotaExceededError(used: 0, quota: 0)
        #expect(error.errorDescription != nil)
        #expect(error.recoverySuggestion != nil)
    }
}

// MARK: - StorageQuotaHandler Tests

@Suite("StorageQuotaHandler Tests")
@MainActor
struct StorageQuotaHandlerTests {

    // MARK: - checkQuota Tests

    @Test("checkQuota with unlimited quota (quota=0) returns allowed")
    func checkQuotaUnlimited() {
        let handler = StorageQuotaHandler()
        let result = handler.checkQuota(
            currentUsed: 999_999,
            quota: 0,
            fileSize: 100_000
        )

        if case .allowed = result {
            // pass
        } else {
            Issue.record("Expected .allowed for unlimited quota")
        }
    }

    @Test("checkQuota when under quota returns allowed")
    func checkQuotaUnderQuota() {
        let handler = StorageQuotaHandler()
        let result = handler.checkQuota(
            currentUsed: 400,
            quota: 1000,
            fileSize: 100
        )

        if case .allowed = result {
            // pass
        } else {
            Issue.record("Expected .allowed when under quota")
        }
    }

    @Test("checkQuota when exactly at quota returns quotaExceeded")
    func checkQuotaExactlyAtQuota() {
        let handler = StorageQuotaHandler()
        let result = handler.checkQuota(
            currentUsed: 1000,
            quota: 1000,
            fileSize: 1
        )

        if case .quotaExceeded(let used, let quota) = result {
            #expect(used == 1000)
            #expect(quota == 1000)
        } else {
            Issue.record("Expected .quotaExceeded when at quota")
        }
    }

    @Test("checkQuota when over quota returns quotaExceeded")
    func checkQuotaOverQuota() {
        let handler = StorageQuotaHandler()
        let result = handler.checkQuota(
            currentUsed: 1500,
            quota: 1000,
            fileSize: 1
        )

        if case .quotaExceeded(let used, let quota) = result {
            #expect(used == 1500)
            #expect(quota == 1000)
        } else {
            Issue.record("Expected .quotaExceeded when over quota")
        }
    }

    @Test("checkQuota when file would exceed returns wouldExceed")
    func checkQuotaWouldExceed() {
        let handler = StorageQuotaHandler()
        let result = handler.checkQuota(
            currentUsed: 800,
            quota: 1000,
            fileSize: 300
        )

        if case .wouldExceed(let used, let quota, let size) = result {
            #expect(used == 800)
            #expect(quota == 1000)
            #expect(size == 300)
        } else {
            Issue.record("Expected .wouldExceed")
        }
    }

    @Test("checkQuota exact fit (currentUsed + fileSize == quota) is allowed")
    func checkQuotaExactFit() {
        let handler = StorageQuotaHandler()
        let result = handler.checkQuota(
            currentUsed: 700,
            quota: 1000,
            fileSize: 300
        )

        // currentUsed + fileSize = 1000 which equals quota
        // The condition is currentUsed + fileSize > quota → wouldExceed
        // So 700 + 300 = 1000, NOT > 1000, so it should be .allowed
        if case .allowed = result {
            // pass
        } else {
            Issue.record("Expected .allowed for exact fit")
        }
    }

    @Test("checkQuota one byte over triggers wouldExceed")
    func checkQuotaOneByteOver() {
        let handler = StorageQuotaHandler()
        let result = handler.checkQuota(
            currentUsed: 700,
            quota: 1000,
            fileSize: 301
        )

        if case .wouldExceed = result {
            // pass
        } else {
            Issue.record("Expected .wouldExceed for one byte over")
        }
    }

    // MARK: - handleDecision Tests

    @Test("handleDecision(.cancel) resets dialog")
    func handleDecisionCancel() {
        let handler = StorageQuotaHandler()
        handler.showQuotaExceededDialog = true

        handler.handleDecision(.cancel)

        #expect(handler.showQuotaExceededDialog == false)
        #expect(handler.shouldNavigateToSettings == false)
        #expect(handler.shouldShowQuotaPicker == false)
    }

    @Test("handleDecision(.manageStorage) sets navigation flag")
    func handleDecisionManageStorage() {
        let handler = StorageQuotaHandler()
        handler.showQuotaExceededDialog = true

        handler.handleDecision(.manageStorage)

        #expect(handler.showQuotaExceededDialog == false)
        #expect(handler.shouldNavigateToSettings == true)
        #expect(handler.shouldShowQuotaPicker == false)
    }

    @Test("handleDecision(.increaseQuota) sets quota picker flag")
    func handleDecisionIncreaseQuota() {
        let handler = StorageQuotaHandler()
        handler.showQuotaExceededDialog = true

        handler.handleDecision(.increaseQuota)

        #expect(handler.showQuotaExceededDialog == false)
        #expect(handler.shouldNavigateToSettings == false)
        #expect(handler.shouldShowQuotaPicker == true)
    }

    // MARK: - resetNavigationFlags Tests

    @Test("resetNavigationFlags clears all flags")
    func resetNavigationFlagsClearsAll() {
        let handler = StorageQuotaHandler()
        handler.shouldNavigateToSettings = true
        handler.shouldShowQuotaPicker = true

        handler.resetNavigationFlags()

        #expect(handler.shouldNavigateToSettings == false)
        #expect(handler.shouldShowQuotaPicker == false)
    }

    // MARK: - Initial State Tests

    @Test("Handler initializes with correct defaults")
    func handlerDefaults() {
        let handler = StorageQuotaHandler()

        #expect(handler.showQuotaExceededDialog == false)
        #expect(handler.currentUsed == 0)
        #expect(handler.currentQuota == 0)
        #expect(handler.shouldNavigateToSettings == false)
        #expect(handler.shouldShowQuotaPicker == false)
    }
}

// MARK: - QuotaExceededDecision Tests

@Suite("QuotaExceededDecision Tests")
@MainActor
struct QuotaExceededDecisionTests {
    @Test("All decision cases exist")
    func allCases() {
        let manage = QuotaExceededDecision.manageStorage
        let increase = QuotaExceededDecision.increaseQuota
        let cancel = QuotaExceededDecision.cancel

        switch manage {
        case .manageStorage: break
        case .increaseQuota, .cancel:
            Issue.record("Expected .manageStorage")
        }

        switch increase {
        case .increaseQuota: break
        case .manageStorage, .cancel:
            Issue.record("Expected .increaseQuota")
        }

        switch cancel {
        case .cancel: break
        case .manageStorage, .increaseQuota:
            Issue.record("Expected .cancel")
        }
    }
}
