//
//  IntentEventHelper.swift
//  Dequeue
//
//  Lightweight event creation for App Intents (runs outside @MainActor).
//  Uses stored user context from App Group UserDefaults.
//

import Foundation
import SwiftData
import os.log

/// Creates sync events from App Intents without requiring AuthService.
///
/// This is a simplified version of EventService for intent execution.
/// Events created here will be picked up by the sync system on next app launch.
/// Methods are `@MainActor` because SwiftData ModelContext requires it.
@MainActor
enum IntentEventHelper {
    private static let logger = Logger(subsystem: "com.dequeue", category: "IntentEvents")
    nonisolated static let appId = Bundle.main.bundleIdentifier ?? "com.dequeue.app"

    /// Returns stored user context, or nil if not authenticated.
    static func userContext() -> (userId: String, deviceId: String)? {
        AppGroupConfig.storedUserContext()
    }

    /// Creates and inserts a task.created event into the model context.
    static func recordTaskCreated(_ task: QueueTask, context: ModelContext) {
        guard let ctx = userContext() else {
            logger.warning("No user context for task.created event")
            return
        }

        let state = TaskState.from(task)
        let payload = TaskCreatedPayload(
            taskId: task.id,
            stackId: task.stack?.id ?? "",
            state: state
        )

        insertEvent(
            type: .taskCreated,
            payload: payload,
            entityId: task.id,
            userId: ctx.userId,
            deviceId: ctx.deviceId,
            context: context
        )
    }

    /// Creates and inserts a task.completed event into the model context.
    static func recordTaskCompleted(_ task: QueueTask, context: ModelContext) {
        guard let ctx = userContext() else {
            logger.warning("No user context for task.completed event")
            return
        }

        let state = TaskState.from(task)
        let payload = TaskStatusPayload(
            taskId: task.id,
            stackId: task.stack?.id ?? "",
            status: TaskStatus.completed.rawValue,
            fullState: state
        )

        insertEvent(
            type: .taskCompleted,
            payload: payload,
            entityId: task.id,
            userId: ctx.userId,
            deviceId: ctx.deviceId,
            context: context
        )
    }

    /// Creates and inserts a stack.completed event into the model context.
    static func recordStackCompleted(_ stack: Stack, context: ModelContext) {
        guard let ctx = userContext() else {
            logger.warning("No user context for stack.completed event")
            return
        }

        let state = StackState.from(stack)
        let payload = StackStatusPayload(
            stackId: stack.id,
            status: StackStatus.completed.rawValue,
            fullState: state
        )

        insertEvent(
            type: .stackCompleted,
            payload: payload,
            entityId: stack.id,
            userId: ctx.userId,
            deviceId: ctx.deviceId,
            context: context
        )
    }

    /// Creates and inserts a stack.activated event into the model context.
    static func recordStackActivated(_ stack: Stack, context: ModelContext) {
        guard let ctx = userContext() else {
            logger.warning("No user context for stack.activated event")
            return
        }

        let state = StackState.from(stack)
        let payload = StackStatusPayload(
            stackId: stack.id,
            status: StackStatus.active.rawValue,
            fullState: state
        )

        insertEvent(
            type: .stackActivated,
            payload: payload,
            entityId: stack.id,
            userId: ctx.userId,
            deviceId: ctx.deviceId,
            context: context
        )
    }

    /// Creates and inserts a stack.deactivated event into the model context.
    static func recordStackDeactivated(_ stack: Stack, context: ModelContext) {
        guard let ctx = userContext() else {
            logger.warning("No user context for stack.deactivated event")
            return
        }

        let state = StackState.from(stack)
        let payload = StackStatusPayload(
            stackId: stack.id,
            status: "deactivated",
            fullState: state
        )

        insertEvent(
            type: .stackDeactivated,
            payload: payload,
            entityId: stack.id,
            userId: ctx.userId,
            deviceId: ctx.deviceId,
            context: context
        )
    }

    // MARK: - Private

    private static func insertEvent<T: Encodable>(
        type: EventType,
        payload: T,
        entityId: String?,
        userId: String,
        deviceId: String,
        context: ModelContext
    ) {
        do {
            let payloadData = try JSONEncoder().encode(payload)
            let metadataData = try JSONEncoder().encode(EventMetadata.human())

            let event = Event(
                eventType: type,
                payload: payloadData,
                metadata: metadataData,
                entityId: entityId,
                userId: userId,
                deviceId: deviceId,
                appId: appId
            )
            context.insert(event)
        } catch {
            logger.error("Failed to create event \(type.rawValue): \(error.localizedDescription)")
        }
    }
}
