//
//  OnboardingService.swift
//  Dequeue
//
//  Manages the first-run onboarding experience. Tracks completion state
//  via UserDefaults and provides the onboarding page model.
//

import Foundation
import SwiftUI

/// Represents a single page in the onboarding flow.
struct OnboardingPage: Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let accentColor: Color

    static let pages: [OnboardingPage] = [
        OnboardingPage(
            id: "welcome",
            title: "Welcome to Dequeue",
            subtitle: "The task manager that works the way you think. Organize your work into focused stacks and knock them out one at a time.",
            systemImage: "tray.full",
            accentColor: .blue
        ),
        OnboardingPage(
            id: "stacks",
            title: "Stacks Keep You Focused",
            subtitle: "Group related tasks into stacks. Activate one stack at a time to stay focused on what matters most right now.",
            systemImage: "square.stack.3d.up",
            accentColor: .purple
        ),
        OnboardingPage(
            id: "dequeue",
            title: "Dequeue, Don't Multitask",
            subtitle: "Complete the top task in your active stack, then move to the next. Like a queue — first in, first out. Simple and powerful.",
            systemImage: "arrow.down.circle",
            accentColor: .green
        ),
        OnboardingPage(
            id: "sync",
            title: "Synced Everywhere",
            subtitle: "Your tasks sync across all your devices in real time. Start on iPhone, continue on Mac. Never miss a beat.",
            systemImage: "arrow.triangle.2.circlepath",
            accentColor: .orange
        ),
        OnboardingPage(
            id: "ready",
            title: "Ready to Go",
            subtitle: "Create your first stack and start crushing your to-do list. You've got this.",
            systemImage: "checkmark.seal",
            accentColor: .mint
        )
    ]
}

/// Manages onboarding state persistence and page navigation.
@Observable
@MainActor
final class OnboardingService {
    private static let completedKey = "onboarding_completed_v1"
    private static let lastPageKey = "onboarding_last_page"

    var isOnboardingComplete: Bool {
        didSet {
            UserDefaults.standard.set(isOnboardingComplete, forKey: Self.completedKey)
        }
    }

    var currentPageIndex: Int = 0

    let pages: [OnboardingPage] = OnboardingPage.pages

    var currentPage: OnboardingPage {
        pages[currentPageIndex]
    }

    var isFirstPage: Bool {
        currentPageIndex == 0
    }

    var isLastPage: Bool {
        currentPageIndex == pages.count - 1
    }

    var progress: Double {
        guard pages.count > 1 else { return 1.0 }
        return Double(currentPageIndex) / Double(pages.count - 1)
    }

    init() {
        self.isOnboardingComplete = UserDefaults.standard.bool(forKey: Self.completedKey)
    }

    /// For testing: inject completion state
    init(isComplete: Bool) {
        self.isOnboardingComplete = isComplete
    }

    func nextPage() {
        guard currentPageIndex < pages.count - 1 else { return }
        currentPageIndex += 1
    }

    func previousPage() {
        guard currentPageIndex > 0 else { return }
        currentPageIndex -= 1
    }

    func goToPage(_ index: Int) {
        guard index >= 0, index < pages.count else { return }
        currentPageIndex = index
    }

    func completeOnboarding() {
        isOnboardingComplete = true
        currentPageIndex = 0
    }

    func resetOnboarding() {
        isOnboardingComplete = false
        currentPageIndex = 0
    }

    /// Check if should show onboarding (not complete and not authenticated yet)
    var shouldShowOnboarding: Bool {
        !isOnboardingComplete
    }
}
