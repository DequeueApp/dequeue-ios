//
//  OnboardingTests.swift
//  DequeueTests
//
//  Tests for the onboarding service and page model.
//

import Testing
import Foundation
@testable import Dequeue

// MARK: - OnboardingPage Tests

@Suite("OnboardingPage Model")
@MainActor
struct OnboardingPageTests {

    @Test("Pages are defined")
    func pagesExist() {
        #expect(!OnboardingPage.pages.isEmpty)
    }

    @Test("All pages have required content")
    func pagesHaveContent() {
        for page in OnboardingPage.pages {
            #expect(!page.id.isEmpty, "Page should have an ID")
            #expect(!page.title.isEmpty, "Page should have a title")
            #expect(!page.subtitle.isEmpty, "Page should have a subtitle")
            #expect(!page.systemImage.isEmpty, "Page should have a system image")
        }
    }

    @Test("Page IDs are unique")
    func pageIdsUnique() {
        let ids = OnboardingPage.pages.map(\.id)
        #expect(Set(ids).count == ids.count, "All page IDs should be unique")
    }

    @Test("Has 5 pages")
    func pageCount() {
        #expect(OnboardingPage.pages.count == 5)
    }

    @Test("First page is welcome")
    func firstPageIsWelcome() {
        #expect(OnboardingPage.pages.first?.id == "welcome")
    }

    @Test("Last page is ready")
    func lastPageIsReady() {
        #expect(OnboardingPage.pages.last?.id == "ready")
    }
}

// MARK: - OnboardingService Tests

@Suite("OnboardingService")
@MainActor
struct OnboardingServiceTests {

    @Test("Initial state for incomplete onboarding")
    func initialStateIncomplete() {
        let service = OnboardingService(isComplete: false)
        #expect(!service.isOnboardingComplete)
        #expect(service.currentPageIndex == 0)
        #expect(service.shouldShowOnboarding)
    }

    @Test("Initial state for completed onboarding")
    func initialStateComplete() {
        let service = OnboardingService(isComplete: true)
        #expect(service.isOnboardingComplete)
        #expect(!service.shouldShowOnboarding)
    }

    @Test("Next page advances index")
    func nextPage() {
        let service = OnboardingService(isComplete: false)
        #expect(service.currentPageIndex == 0)
        service.nextPage()
        #expect(service.currentPageIndex == 1)
        service.nextPage()
        #expect(service.currentPageIndex == 2)
    }

    @Test("Next page does not exceed bounds")
    func nextPageBounds() {
        let service = OnboardingService(isComplete: false)
        // Go to last page
        for _ in 0..<service.pages.count {
            service.nextPage()
        }
        let lastIndex = service.pages.count - 1
        #expect(service.currentPageIndex == lastIndex)
        // Try going past last page
        service.nextPage()
        #expect(service.currentPageIndex == lastIndex)
    }

    @Test("Previous page decrements index")
    func previousPage() {
        let service = OnboardingService(isComplete: false)
        service.currentPageIndex = 3
        service.previousPage()
        #expect(service.currentPageIndex == 2)
    }

    @Test("Previous page does not go below 0")
    func previousPageBounds() {
        let service = OnboardingService(isComplete: false)
        #expect(service.currentPageIndex == 0)
        service.previousPage()
        #expect(service.currentPageIndex == 0)
    }

    @Test("Go to specific page")
    func goToPage() {
        let service = OnboardingService(isComplete: false)
        service.goToPage(3)
        #expect(service.currentPageIndex == 3)
    }

    @Test("Go to page bounds check — negative")
    func goToPageNegative() {
        let service = OnboardingService(isComplete: false)
        service.goToPage(-1)
        #expect(service.currentPageIndex == 0)
    }

    @Test("Go to page bounds check — too high")
    func goToPageTooHigh() {
        let service = OnboardingService(isComplete: false)
        service.goToPage(100)
        #expect(service.currentPageIndex == 0)
    }

    @Test("isFirstPage is true at index 0")
    func isFirstPage() {
        let service = OnboardingService(isComplete: false)
        #expect(service.isFirstPage)
        service.nextPage()
        #expect(!service.isFirstPage)
    }

    @Test("isLastPage is true at last index")
    func isLastPage() {
        let service = OnboardingService(isComplete: false)
        #expect(!service.isLastPage)
        service.goToPage(service.pages.count - 1)
        #expect(service.isLastPage)
    }

    @Test("Progress calculation")
    func progressCalculation() {
        let service = OnboardingService(isComplete: false)
        let pageCount = Double(service.pages.count - 1)

        #expect(service.progress == 0.0)

        service.goToPage(1)
        #expect(service.progress == 1.0 / pageCount)

        service.goToPage(service.pages.count - 1)
        #expect(service.progress == 1.0)
    }

    @Test("Complete onboarding sets flag and resets page")
    func completeOnboarding() {
        let service = OnboardingService(isComplete: false)
        service.goToPage(3)
        service.completeOnboarding()
        #expect(service.isOnboardingComplete)
        #expect(service.currentPageIndex == 0)
        #expect(!service.shouldShowOnboarding)
    }

    @Test("Reset onboarding clears flag and resets page")
    func resetOnboarding() {
        let service = OnboardingService(isComplete: true)
        service.resetOnboarding()
        #expect(!service.isOnboardingComplete)
        #expect(service.currentPageIndex == 0)
        #expect(service.shouldShowOnboarding)
    }

    @Test("currentPage returns correct page")
    func currentPageReturnsCorrect() {
        let service = OnboardingService(isComplete: false)
        #expect(service.currentPage.id == "welcome")
        service.goToPage(2)
        #expect(service.currentPage.id == OnboardingPage.pages[2].id)
    }

    @Test("Full walkthrough")
    func fullWalkthrough() {
        let service = OnboardingService(isComplete: false)
        #expect(service.shouldShowOnboarding)

        // Walk through all pages
        for pageIdx in 0..<service.pages.count - 1 {
            #expect(service.currentPageIndex == pageIdx)
            #expect(!service.isLastPage)
            service.nextPage()
        }

        #expect(service.isLastPage)
        service.completeOnboarding()
        #expect(!service.shouldShowOnboarding)
    }
}
