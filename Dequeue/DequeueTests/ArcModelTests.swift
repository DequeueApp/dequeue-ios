//
//  ArcModelTests.swift
//  DequeueTests
//
//  Unit tests for Arc model computed properties:
//  isActive, activeStackCount, completedStackCount, totalStackCount,
//  progress, sortedStacks, pendingStacks, activeReminders.
//

import Testing
import SwiftData
import Foundation
@testable import Dequeue

// MARK: - Container helpers

private func makeArcTestContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: Arc.self, Stack.self, QueueTask.self, Reminder.self, Tag.self,
        configurations: config
    )
}

// MARK: - isActive

@Suite("Arc.isActive", .serialized)
@MainActor
struct ArcIsActiveTests {
    @Test("active + not deleted → isActive true")
    func activeNotDeletedIsTrue() throws {
        let arc = Arc(title: "T", status: .active)
        #expect(arc.isActive == true)
    }

    @Test("active + deleted → isActive false")
    func activeDeletedIsFalse() throws {
        let arc = Arc(title: "T", status: .active, isDeleted: true)
        #expect(arc.isActive == false)
    }

    @Test("paused + not deleted → isActive false")
    func pausedNotDeletedIsFalse() throws {
        let arc = Arc(title: "T", status: .paused)
        #expect(arc.isActive == false)
    }

    @Test("completed + not deleted → isActive false")
    func completedIsActiveFalse() throws {
        let arc = Arc(title: "T", status: .completed)
        #expect(arc.isActive == false)
    }

    @Test("archived + not deleted → isActive false")
    func archivedIsActiveFalse() throws {
        let arc = Arc(title: "T", status: .archived)
        #expect(arc.isActive == false)
    }
}

// MARK: - Stack counts

@Suite("Arc stack counts", .serialized)
@MainActor
struct ArcStackCountTests {
    @Test("empty arc has all counts zero")
    func emptyArcZeroCounts() throws {
        let arc = Arc(title: "T")
        #expect(arc.activeStackCount == 0)
        #expect(arc.completedStackCount == 0)
        #expect(arc.totalStackCount == 0)
    }

    @Test("activeStackCount counts only non-deleted active stacks")
    func activeStackCountIgnoresDeletedAndCompleted() async throws {
        let container = try makeArcTestContainer()
        let context = container.mainContext

        let arc = Arc(title: "T")
        context.insert(arc)

        let active1 = Stack(title: "A1", status: .active)
        context.insert(active1)
        arc.stacks.append(active1)

        let active2 = Stack(title: "A2", status: .active)
        context.insert(active2)
        arc.stacks.append(active2)

        let completed = Stack(title: "C", status: .completed)
        context.insert(completed)
        arc.stacks.append(completed)

        let deleted = Stack(title: "D", status: .active, isDeleted: true)
        context.insert(deleted)
        arc.stacks.append(deleted)

        try context.save()

        #expect(arc.activeStackCount == 2)
    }

    @Test("completedStackCount counts only non-deleted completed stacks")
    func completedStackCountIgnoresDeletedAndActive() async throws {
        let container = try makeArcTestContainer()
        let context = container.mainContext

        let arc = Arc(title: "T")
        context.insert(arc)

        let comp1 = Stack(title: "C1", status: .completed)
        context.insert(comp1)
        arc.stacks.append(comp1)

        let comp2 = Stack(title: "C2", status: .completed)
        context.insert(comp2)
        arc.stacks.append(comp2)

        let active = Stack(title: "A", status: .active)
        context.insert(active)
        arc.stacks.append(active)

        let deletedComp = Stack(title: "DC", status: .completed, isDeleted: true)
        context.insert(deletedComp)
        arc.stacks.append(deletedComp)

        try context.save()

        #expect(arc.completedStackCount == 2)
    }

    @Test("totalStackCount excludes deleted stacks")
    func totalStackCountExcludesDeleted() async throws {
        let container = try makeArcTestContainer()
        let context = container.mainContext

        let arc = Arc(title: "T")
        context.insert(arc)

        let s1 = Stack(title: "S1", status: .active)
        context.insert(s1)
        arc.stacks.append(s1)

        let s2 = Stack(title: "S2", status: .completed)
        context.insert(s2)
        arc.stacks.append(s2)

        let deleted = Stack(title: "Del", status: .active, isDeleted: true)
        context.insert(deleted)
        arc.stacks.append(deleted)

        try context.save()

        #expect(arc.totalStackCount == 2)
    }
}

// MARK: - progress

@Suite("Arc.progress", .serialized)
@MainActor
struct ArcProgressTests {
    @Test("progress is 0.0 when arc has no stacks")
    func progressZeroWhenNoStacks() throws {
        let arc = Arc(title: "T")
        #expect(arc.progress == 0.0)
    }

    @Test("progress is 0.0 when no stacks are completed")
    func progressZeroWhenNoneCompleted() async throws {
        let container = try makeArcTestContainer()
        let context = container.mainContext

        let arc = Arc(title: "T")
        context.insert(arc)

        let s = Stack(title: "Active", status: .active)
        context.insert(s)
        arc.stacks.append(s)

        try context.save()

        #expect(arc.progress == 0.0)
    }

    @Test("progress is 1.0 when all stacks are completed")
    func progressOneWhenAllCompleted() async throws {
        let container = try makeArcTestContainer()
        let context = container.mainContext

        let arc = Arc(title: "T")
        context.insert(arc)

        let s1 = Stack(title: "C1", status: .completed)
        context.insert(s1)
        arc.stacks.append(s1)

        let s2 = Stack(title: "C2", status: .completed)
        context.insert(s2)
        arc.stacks.append(s2)

        try context.save()

        #expect(arc.progress == 1.0)
    }

    @Test("progress is 0.5 when half completed")
    func progressHalfWhenHalfDone() async throws {
        let container = try makeArcTestContainer()
        let context = container.mainContext

        let arc = Arc(title: "T")
        context.insert(arc)

        let done = Stack(title: "Done", status: .completed)
        context.insert(done)
        arc.stacks.append(done)

        let active = Stack(title: "Active", status: .active)
        context.insert(active)
        arc.stacks.append(active)

        try context.save()

        #expect(arc.progress == 0.5)
    }

    @Test("progress ignores deleted stacks")
    func progressIgnoresDeletedStacks() async throws {
        let container = try makeArcTestContainer()
        let context = container.mainContext

        let arc = Arc(title: "T")
        context.insert(arc)

        // 1 completed non-deleted, 1 active non-deleted → 0.5
        let done = Stack(title: "Done", status: .completed)
        context.insert(done)
        arc.stacks.append(done)

        let active = Stack(title: "Active", status: .active)
        context.insert(active)
        arc.stacks.append(active)

        // Deleted stacks should NOT count toward total or completed
        let deletedDone = Stack(title: "DelDone", status: .completed, isDeleted: true)
        context.insert(deletedDone)
        arc.stacks.append(deletedDone)

        try context.save()

        #expect(arc.progress == 0.5)
    }
}

// MARK: - sortedStacks

@Suite("Arc.sortedStacks", .serialized)
@MainActor
struct ArcSortedStacksTests {
    @Test("sortedStacks returns stacks ordered by sortOrder ascending")
    func sortedStacksOrderedBySortOrder() async throws {
        let container = try makeArcTestContainer()
        let context = container.mainContext

        let arc = Arc(title: "T")
        context.insert(arc)

        let s3 = Stack(title: "Third", sortOrder: 3)
        context.insert(s3)
        arc.stacks.append(s3)

        let s1 = Stack(title: "First", sortOrder: 1)
        context.insert(s1)
        arc.stacks.append(s1)

        let s2 = Stack(title: "Second", sortOrder: 2)
        context.insert(s2)
        arc.stacks.append(s2)

        try context.save()

        let sorted = arc.sortedStacks
        #expect(sorted.count == 3)
        #expect(sorted[0].title == "First")
        #expect(sorted[1].title == "Second")
        #expect(sorted[2].title == "Third")
    }

    @Test("sortedStacks excludes deleted stacks")
    func sortedStacksExcludesDeleted() async throws {
        let container = try makeArcTestContainer()
        let context = container.mainContext

        let arc = Arc(title: "T")
        context.insert(arc)

        let visible = Stack(title: "Visible", sortOrder: 1)
        context.insert(visible)
        arc.stacks.append(visible)

        let deleted = Stack(title: "Gone", sortOrder: 0, isDeleted: true)
        context.insert(deleted)
        arc.stacks.append(deleted)

        try context.save()

        let sorted = arc.sortedStacks
        #expect(sorted.count == 1)
        #expect(sorted[0].title == "Visible")
    }

    @Test("sortedStacks includes completed stacks")
    func sortedStacksIncludesCompletedStacks() async throws {
        let container = try makeArcTestContainer()
        let context = container.mainContext

        let arc = Arc(title: "T")
        context.insert(arc)

        let comp = Stack(title: "Completed", status: .completed, sortOrder: 0)
        context.insert(comp)
        arc.stacks.append(comp)

        let active = Stack(title: "Active", status: .active, sortOrder: 1)
        context.insert(active)
        arc.stacks.append(active)

        try context.save()

        #expect(arc.sortedStacks.count == 2)
    }
}

// MARK: - pendingStacks

@Suite("Arc.pendingStacks", .serialized)
@MainActor
struct ArcPendingStacksTests {
    @Test("pendingStacks returns only active non-deleted stacks ordered by sortOrder")
    func pendingStacksOnlyActiveNonDeleted() async throws {
        let container = try makeArcTestContainer()
        let context = container.mainContext

        let arc = Arc(title: "T")
        context.insert(arc)

        let active1 = Stack(title: "Active1", status: .active, sortOrder: 2)
        context.insert(active1)
        arc.stacks.append(active1)

        let active2 = Stack(title: "Active2", status: .active, sortOrder: 1)
        context.insert(active2)
        arc.stacks.append(active2)

        let completed = Stack(title: "Done", status: .completed, sortOrder: 0)
        context.insert(completed)
        arc.stacks.append(completed)

        let deletedActive = Stack(title: "DeletedActive", status: .active, sortOrder: 3, isDeleted: true)
        context.insert(deletedActive)
        arc.stacks.append(deletedActive)

        try context.save()

        let pending = arc.pendingStacks
        #expect(pending.count == 2)
        #expect(pending[0].title == "Active2")
        #expect(pending[1].title == "Active1")
    }

    @Test("pendingStacks is empty when no active stacks")
    func pendingStacksEmptyWhenNoneActive() async throws {
        let container = try makeArcTestContainer()
        let context = container.mainContext

        let arc = Arc(title: "T")
        context.insert(arc)

        let comp = Stack(title: "Completed", status: .completed, sortOrder: 0)
        context.insert(comp)
        arc.stacks.append(comp)

        try context.save()

        #expect(arc.pendingStacks.isEmpty)
    }
}

// MARK: - activeReminders

@Suite("Arc.activeReminders", .serialized)
@MainActor
struct ArcActiveRemindersTests {
    @Test("activeReminders returns only non-deleted active reminders sorted by remindAt")
    func activeRemindersSortedAndFiltered() async throws {
        let container = try makeArcTestContainer()
        let context = container.mainContext

        let arc = Arc(title: "T")
        context.insert(arc)

        let now = Date()
        let r1 = Reminder(
            parentId: arc.id,
            parentType: .arc,
            status: .active,
            remindAt: now.addingTimeInterval(200)
        )
        r1.arc = arc
        context.insert(r1)

        let r2 = Reminder(
            parentId: arc.id,
            parentType: .arc,
            status: .active,
            remindAt: now.addingTimeInterval(100)
        )
        r2.arc = arc
        context.insert(r2)

        let firedReminder = Reminder(
            parentId: arc.id,
            parentType: .arc,
            status: .fired,
            remindAt: now.addingTimeInterval(50)
        )
        firedReminder.arc = arc
        context.insert(firedReminder)

        let deletedReminder = Reminder(
            parentId: arc.id,
            parentType: .arc,
            status: .active,
            remindAt: now.addingTimeInterval(10),
            isDeleted: true
        )
        deletedReminder.arc = arc
        context.insert(deletedReminder)

        try context.save()

        let active = arc.activeReminders
        #expect(active.count == 2)
        // Should be sorted ascending by remindAt
        #expect(active[0].remindAt < active[1].remindAt)
    }

    @Test("activeReminders is empty when arc has no reminders")
    func activeRemindersEmptyForFreshArc() throws {
        let arc = Arc(title: "T")
        #expect(arc.activeReminders.isEmpty)
    }

    @Test("snoozed reminder is excluded from activeReminders")
    func snoozedReminderExcluded() async throws {
        let container = try makeArcTestContainer()
        let context = container.mainContext

        let arc = Arc(title: "T")
        context.insert(arc)

        let snoozed = Reminder(
            parentId: arc.id,
            parentType: .arc,
            status: .snoozed,
            remindAt: Date().addingTimeInterval(100)
        )
        snoozed.arc = arc
        context.insert(snoozed)

        try context.save()

        #expect(arc.activeReminders.isEmpty)
    }
}
