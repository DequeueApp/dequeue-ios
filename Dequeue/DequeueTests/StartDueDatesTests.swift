//
//  StartDueDatesTests.swift
//  DequeueTests
//
//  Tests for start and due date functionality on Arc, Stack, and Task models
//

import Testing
import SwiftData
import Foundation
@testable import Dequeue

// MARK: - Test Helpers

private func makeTestContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(
        for: Arc.self,
        Stack.self,
        QueueTask.self,
        Reminder.self,
        Event.self,
        Attachment.self,
        Device.self,
        Tag.self,
        SyncConflict.self,
        configurations: config
    )
}

@Suite("Start and Due Dates Tests", .serialized)
struct StartDueDatesTests {

    // MARK: - Arc Model Tests

    @Test("Arc initializes with startTime and dueTime")
    func arcInitializesWithDates() {
        let startDate = Date()
        let dueDate = Date().addingTimeInterval(86_400 * 7)

        let arc = Arc(
            title: "Test Arc",
            startTime: startDate,
            dueTime: dueDate
        )

        #expect(arc.startTime == startDate)
        #expect(arc.dueTime == dueDate)
    }

    @Test("Arc initializes without dates by default")
    func arcInitializesWithoutDates() {
        let arc = Arc(title: "Test Arc")

        #expect(arc.startTime == nil)
        #expect(arc.dueTime == nil)
    }

    // MARK: - Stack Model Tests

    @Test("Stack already has startTime and dueTime fields")
    func stackHasDateFields() {
        let startDate = Date()
        let dueDate = Date().addingTimeInterval(86_400 * 7)

        let stack = Stack(
            title: "Test Stack",
            startTime: startDate,
            dueTime: dueDate
        )

        #expect(stack.startTime == startDate)
        #expect(stack.dueTime == dueDate)
    }

    // MARK: - QueueTask Model Tests

    @Test("QueueTask initializes with startTime and dueTime")
    func taskInitializesWithDates() {
        let startDate = Date()
        let dueDate = Date().addingTimeInterval(86_400)

        let task = QueueTask(
            title: "Test Task",
            startTime: startDate,
            dueTime: dueDate
        )

        #expect(task.startTime == startDate)
        #expect(task.dueTime == dueDate)
    }

    @Test("QueueTask initializes without startTime by default")
    func taskInitializesWithoutStartTime() {
        let task = QueueTask(title: "Test Task")

        #expect(task.startTime == nil)
    }

    // MARK: - Event State Tests

    @Test("StackState captures startTime and dueTime")
    func stackStateCapturesDates() {
        let startDate = Date()
        let dueDate = Date().addingTimeInterval(86_400 * 7)

        let stack = Stack(
            title: "Test Stack",
            startTime: startDate,
            dueTime: dueDate
        )

        let state = StackState.from(stack)

        #expect(state.startTime == Int64(startDate.timeIntervalSince1970 * 1_000))
        #expect(state.dueTime == Int64(dueDate.timeIntervalSince1970 * 1_000))
    }

    @Test("StackState handles nil dates")
    func stackStateHandlesNilDates() {
        let stack = Stack(title: "Test Stack")

        let state = StackState.from(stack)

        #expect(state.startTime == nil)
        #expect(state.dueTime == nil)
    }

    @Test("TaskState captures startTime and dueTime")
    func taskStateCapturesDates() {
        let startDate = Date()
        let dueDate = Date().addingTimeInterval(86_400)

        let task = QueueTask(
            title: "Test Task",
            startTime: startDate,
            dueTime: dueDate
        )

        let state = TaskState.from(task)

        #expect(state.startTime == Int64(startDate.timeIntervalSince1970 * 1_000))
        #expect(state.dueTime == Int64(dueDate.timeIntervalSince1970 * 1_000))
    }

    @Test("ArcState captures startTime and dueTime")
    func arcStateCapturesDates() {
        let startDate = Date()
        let dueDate = Date().addingTimeInterval(86_400 * 7)

        let arc = Arc(
            title: "Test Arc",
            startTime: startDate,
            dueTime: dueDate
        )

        let state = ArcState.from(arc)

        #expect(state.startTime == Int64(startDate.timeIntervalSince1970 * 1_000))
        #expect(state.dueTime == Int64(dueDate.timeIntervalSince1970 * 1_000))
    }

    // MARK: - Reminder Creation at 8 AM Tests

    @Test("Reminder creation at 8 AM on due date")
    @MainActor
    func reminderAt8AMOnDueDate() async throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        // Create an arc with a due date
        let dueDate = Calendar.current.date(
            byAdding: .day,
            value: 7,
            to: Date()
        )!

        let arc = Arc(title: "Test Arc", dueTime: dueDate)
        context.insert(arc)
        try context.save()

        // Calculate expected reminder time (8 AM on due date)
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        let expectedReminderDate = calendar.date(
            bySettingHour: 8,
            minute: 0,
            second: 0,
            of: dueDate
        )!

        // Create reminder service and create the reminder
        let reminderService = ReminderService(
            modelContext: context,
            userId: "test-user",
            deviceId: "test-device"
        )

        let reminder = try await reminderService.createReminder(for: arc, at: expectedReminderDate)

        // Verify reminder is set to 8 AM
        let reminderComponents = calendar.dateComponents([.hour, .minute], from: reminder.remindAt)
        #expect(reminderComponents.hour == 8)
        #expect(reminderComponents.minute == 0)

        // Verify it's on the same day as the due date
        #expect(calendar.isDate(reminder.remindAt, inSameDayAs: dueDate))
    }

    // MARK: - Date Filtering Tests

    @Test("DateScheduledItem captures correct properties")
    func dateScheduledItemProperties() {
        let item = DateScheduledItem(
            id: "test-id",
            title: "Test Item",
            date: Date(),
            parentType: .stack,
            isStartDate: true
        )

        #expect(item.id == "test-id")
        #expect(item.title == "Test Item")
        #expect(item.parentType == .stack)
        #expect(item.isStartDate == true)
    }

    @Test("DateScheduledItem distinguishes start and due dates")
    func dateScheduledItemDistinguishesDates() {
        let startItem = DateScheduledItem(
            id: "start-id",
            title: "Start Item",
            date: Date(),
            parentType: .task,
            isStartDate: true
        )

        let dueItem = DateScheduledItem(
            id: "due-id",
            title: "Due Item",
            date: Date(),
            parentType: .task,
            isStartDate: false
        )

        #expect(startItem.isStartDate == true)
        #expect(dueItem.isStartDate == false)
    }
}
