//
//  DequeueTests.swift
//  DequeueTests
//
//  Created by Victor Quinn on 12/21/25.
//

import Testing
import SwiftData
import Foundation
@testable import Dequeue

@Suite("Dequeue Core Tests")
struct DequeueTests {
    @Test("Models can be inserted into container")
    func modelsCanBeInserted() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Stack.self, QueueTask.self, Reminder.self, configurations: config)
        let context = ModelContext(container)

        let stack = Stack(title: "Test Stack")
        context.insert(stack)

        let task = QueueTask(title: "Test Task", stack: stack)
        context.insert(task)

        let reminder = Reminder(parentId: stack.id, parentType: .stack, remindAt: Date())
        context.insert(reminder)

        try context.save()

        let fetchDescriptor = FetchDescriptor<Stack>()
        let stacks = try context.fetch(fetchDescriptor)

        #expect(stacks.count == 1)
        #expect(stacks.first?.title == "Test Stack")
    }
}
