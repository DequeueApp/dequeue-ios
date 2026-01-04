//
//  StackFilteringTests.swift
//  DequeueTests
//
//  Tests for stack filtering logic used by HomeView and CompletedStacksView
//  These tests verify that stacks appear in the correct views based on their status
//

import Testing
import SwiftData
import Foundation
@testable import Dequeue

@Suite("Stack Filtering Tests", .serialized)
struct StackFilteringTests {
    // MARK: - HomeView Filter Logic Tests
    // These tests verify the filtering logic that HomeView uses

    @Test("Active stacks pass HomeView filter")
    func activeStacksPassHomeViewFilter() {
        let stack = Stack(title: "Active Stack", status: .active)

        // HomeView filter: not deleted, not draft, status == active
        let passesFilter = !stack.isDeleted && !stack.isDraft && stack.status == .active

        #expect(passesFilter == true)
    }

    @Test("Completed stacks fail HomeView filter - DEQ-5 regression")
    func completedStacksFailHomeViewFilter() {
        let stack = Stack(title: "Completed Stack", status: .completed)

        // HomeView filter: not deleted, not draft, status == active
        let passesFilter = !stack.isDeleted && !stack.isDraft && stack.status == .active

        #expect(passesFilter == false, "Completed stacks should NOT appear in HomeView")
    }

    @Test("Closed stacks fail HomeView filter")
    func closedStacksFailHomeViewFilter() {
        let stack = Stack(title: "Closed Stack", status: .closed)

        // HomeView filter: not deleted, not draft, status == active
        let passesFilter = !stack.isDeleted && !stack.isDraft && stack.status == .active

        #expect(passesFilter == false, "Closed stacks should NOT appear in HomeView")
    }

    @Test("Archived stacks fail HomeView filter")
    func archivedStacksFailHomeViewFilter() {
        let stack = Stack(title: "Archived Stack", status: .archived)

        // HomeView filter: not deleted, not draft, status == active
        let passesFilter = !stack.isDeleted && !stack.isDraft && stack.status == .active

        #expect(passesFilter == false, "Archived stacks should NOT appear in HomeView")
    }

    @Test("Deleted active stacks fail HomeView filter")
    func deletedActiveStacksFailHomeViewFilter() {
        let stack = Stack(title: "Deleted Stack", status: .active, isDeleted: true)

        // HomeView filter: not deleted, not draft, status == active
        let passesFilter = !stack.isDeleted && !stack.isDraft && stack.status == .active

        #expect(passesFilter == false, "Deleted stacks should NOT appear in HomeView")
    }

    @Test("Draft active stacks fail HomeView filter")
    func draftActiveStacksFailHomeViewFilter() {
        let stack = Stack(title: "Draft Stack", status: .active, isDraft: true)

        // HomeView filter: not deleted, not draft, status == active
        let passesFilter = !stack.isDeleted && !stack.isDraft && stack.status == .active

        #expect(passesFilter == false, "Draft stacks should NOT appear in HomeView")
    }

    // MARK: - CompletedStacksView Filter Logic Tests
    // These tests verify the filtering logic that CompletedStacksView uses

    @Test("Completed stacks pass CompletedStacksView filter")
    func completedStacksPassCompletedViewFilter() {
        let stack = Stack(title: "Completed Stack", status: .completed)

        // CompletedStacksView filter: not deleted, status == completed OR status == closed
        let passesFilter = !stack.isDeleted && (stack.status == .completed || stack.status == .closed)

        #expect(passesFilter == true)
    }

    @Test("Closed stacks pass CompletedStacksView filter")
    func closedStacksPassCompletedViewFilter() {
        let stack = Stack(title: "Closed Stack", status: .closed)

        // CompletedStacksView filter: not deleted, status == completed OR status == closed
        let passesFilter = !stack.isDeleted && (stack.status == .completed || stack.status == .closed)

        #expect(passesFilter == true)
    }

    @Test("Active stacks fail CompletedStacksView filter")
    func activeStacksFailCompletedViewFilter() {
        let stack = Stack(title: "Active Stack", status: .active)

        // CompletedStacksView filter: not deleted, status == completed OR status == closed
        let passesFilter = !stack.isDeleted && (stack.status == .completed || stack.status == .closed)

        #expect(passesFilter == false, "Active stacks should NOT appear in CompletedStacksView")
    }

    @Test("Archived stacks fail CompletedStacksView filter")
    func archivedStacksFailCompletedViewFilter() {
        let stack = Stack(title: "Archived Stack", status: .archived)

        // CompletedStacksView filter: not deleted, status == completed OR status == closed
        let passesFilter = !stack.isDeleted && (stack.status == .completed || stack.status == .closed)

        #expect(passesFilter == false, "Archived stacks should NOT appear in CompletedStacksView")
    }

    @Test("Deleted completed stacks fail CompletedStacksView filter")
    func deletedCompletedStacksFailCompletedViewFilter() {
        let stack = Stack(title: "Deleted Completed Stack", status: .completed, isDeleted: true)

        // CompletedStacksView filter: not deleted, status == completed OR status == closed
        let passesFilter = !stack.isDeleted && (stack.status == .completed || stack.status == .closed)

        #expect(passesFilter == false, "Deleted stacks should NOT appear in CompletedStacksView")
    }

    // MARK: - Stack Lifecycle Tests (DEQ-5 scenario)

    @Test("Stack transitions from HomeView to CompletedView when completed - DEQ-5")
    func stackTransitionsOnCompletion() {
        // Create an active stack
        let stack = Stack(title: "My Stack", status: .active)

        // Initially should be in HomeView, not CompletedView
        let initiallyInHome = !stack.isDeleted && !stack.isDraft && stack.status == .active
        let initiallyInCompleted = !stack.isDeleted && (stack.status == .completed || stack.status == .closed)

        #expect(initiallyInHome == true, "Active stack should be in HomeView")
        #expect(initiallyInCompleted == false, "Active stack should NOT be in CompletedView")

        // Mark as completed (simulating StackService.markAsCompleted)
        stack.status = .completed

        // Now should be in CompletedView, not HomeView
        let afterCompletionInHome = !stack.isDeleted && !stack.isDraft && stack.status == .active
        let afterCompletionInCompleted = !stack.isDeleted && (stack.status == .completed || stack.status == .closed)

        #expect(afterCompletionInHome == false, "Completed stack should NOT be in HomeView")
        #expect(afterCompletionInCompleted == true, "Completed stack should be in CompletedView")
    }

    @Test("Stack transitions from HomeView to CompletedView when closed")
    func stackTransitionsOnClose() {
        // Create an active stack
        let stack = Stack(title: "My Stack", status: .active)

        // Initially should be in HomeView, not CompletedView
        let initiallyInHome = !stack.isDeleted && !stack.isDraft && stack.status == .active
        let initiallyInCompleted = !stack.isDeleted && (stack.status == .completed || stack.status == .closed)

        #expect(initiallyInHome == true, "Active stack should be in HomeView")
        #expect(initiallyInCompleted == false, "Active stack should NOT be in CompletedView")

        // Close the stack (simulating StackService.closeStack)
        stack.status = .closed

        // Now should be in CompletedView, not HomeView
        let afterCloseInHome = !stack.isDeleted && !stack.isDraft && stack.status == .active
        let afterCloseInCompleted = !stack.isDeleted && (stack.status == .completed || stack.status == .closed)

        #expect(afterCloseInHome == false, "Closed stack should NOT be in HomeView")
        #expect(afterCloseInCompleted == true, "Closed stack should be in CompletedView")
    }
}
