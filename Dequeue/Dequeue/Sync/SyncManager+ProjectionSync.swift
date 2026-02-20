//
//  SyncManager+ProjectionSync.swift
//  Dequeue
//
//  Projection-based initial sync: fetches current state from REST API
//  instead of replaying all events. Extracted from SyncManager.swift.
//

import Foundation
import SwiftData
import os.log

// MARK: - Projection Sync (DEQ-230)

extension SyncManager {
    /// Performs initial sync using REST API projections instead of event replay.
    /// This is significantly faster for new devices with no local state.
    ///
    /// Flow:
    /// 1. Fetch current state from /v1/stacks, /v1/arcs, /v1/tags endpoints
    /// 2. Populate local SwiftData models directly
    /// 3. Set checkpoint to current time
    /// 4. Continue with real-time WebSocket sync
    ///
    /// Falls back to event replay if projection fetch fails.
    func syncViaProjections() async throws {
        let startTime = Date()
        let syncId = Self.generateSyncId()
        os_log("[Sync] Projection sync started: syncId=\(syncId)")

        isInitialSyncActive = true
        defer { isInitialSyncActive = false }

        guard let token = try await refreshToken() else {
            os_log("[Sync] Projection sync failed: Not authenticated")
            throw SyncError.notAuthenticated
        }

        let baseURL = await MainActor.run { Configuration.syncAPIBaseURL }

        // Fetch all resource types in parallel
        // Note: Explicit type annotations help the type-checker avoid timeout on complex expressions
        async let stacksTask: [StackProjection] = fetchProjectionPage(
            StackProjection.self, url: "\(baseURL)/v1/stacks", token: token
        )
        async let tasksTask: [TaskProjection] = fetchProjectionPage(
            TaskProjection.self, url: "\(baseURL)/v1/tasks", token: token
        )
        async let arcsTask: [ArcProjection] = fetchProjectionPage(
            ArcProjection.self, url: "\(baseURL)/v1/arcs", token: token
        )
        async let tagsTask: [TagProjection] = fetchProjectionPage(
            TagProjection.self, url: "\(baseURL)/v1/tags", token: token
        )
        async let remindersTask: [ReminderProjection] = fetchProjectionPage(
            ReminderProjection.self, url: "\(baseURL)/v1/reminders", token: token
        )

        do {
            // Await each task individually to help the type-checker
            let stacks = try await stacksTask
            let tasks = try await tasksTask
            let arcs = try await arcsTask
            let tags = try await tagsTask
            let reminders = try await remindersTask

            let sc = stacks.count, tc = tasks.count, ac = arcs.count
            let tgc = tags.count, rc = reminders.count
            os_log("[Sync] Fetched projections: \(sc) stacks, \(tc) tasks, \(ac) arcs, \(tgc) tags, \(rc) reminders")

            // Populate local models
            try await populateFromProjections(
                stacks: stacks, tasks: tasks, arcs: arcs, tags: tags, reminders: reminders
            )

            // Set checkpoint to now (all future events will be synced incrementally)
            let checkpoint = Self.iso8601Standard.string(from: Date())
            saveLastSyncCheckpoint(checkpoint)

            let duration = Date().timeIntervalSince(startTime)
            let durationFormatted = String(format: "%.2f", duration)
            os_log("[Sync] Projection sync complete: syncId=\(syncId), duration=\(durationFormatted)s")

            await ErrorReportingService.logSyncComplete(
                syncId: syncId,
                duration: duration,
                itemsUploaded: 0,  // Projection sync only downloads
                itemsDownloaded: stacks.count + tasks.count + arcs.count + tags.count + reminders.count
            )
        } catch {
            os_log("[Sync] Projection sync failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Fetches a paginated projection resource, handling pagination automatically.
    /// Requires Sendable to allow safe transfer of results across actor boundaries.
    func fetchProjectionPage<T: Decodable & Sendable>(
        _ type: T.Type,
        url: String,
        token: String
    ) async throws -> [T] {
        var allResults: [T] = []
        var currentURL: String? = url

        while let urlString = currentURL {
            guard let url = URL(string: urlString) else {
                os_log("[Sync] Invalid URL string: \(urlString)")
                throw SyncError.pullFailed
            }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let (data, response) = try await syncSession.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                os_log("[Sync] Invalid response type for \(urlString)")
                throw SyncError.pullFailed
            }

            guard httpResponse.statusCode == 200 else {
                if let responseBody = String(data: data, encoding: .utf8) {
                    os_log(
                        "[Sync] Projection fetch failed (\(httpResponse.statusCode)): \(responseBody)"
                    )
                }
                throw SyncError.pullFailed
            }

            let decoded = try JSONDecoder().decode(ProjectionResponse<T>.self, from: data)
            allResults.append(contentsOf: decoded.data)

            // Handle pagination — use URLComponents to properly manage query parameters
            if let pagination = decoded.pagination,
               pagination.hasMore,
               let nextCursor = pagination.nextCursor {
                var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
                var queryItems = components?.queryItems ?? []
                queryItems.removeAll { $0.name == "cursor" }
                queryItems.append(URLQueryItem(name: "cursor", value: nextCursor))
                components?.queryItems = queryItems
                currentURL = components?.url?.absoluteString
            } else {
                currentURL = nil
            }
        }

        return allResults
    }

    // MARK: - Populate Models from Projections

    /// Populates local SwiftData models from projection data.
    /// Order matters: Arcs before Stacks (foreign key), Tags before Stack-Tag associations,
    /// Reminders last.
    /// Runs on MainActor as required for SwiftData ModelContext operations.
    /// Broken into sub-functions to reduce cyclomatic complexity.
    @MainActor
    func populateFromProjections(
        stacks: [StackProjection],
        tasks: [TaskProjection],
        arcs: [ArcProjection],
        tags: [TagProjection],
        reminders: [ReminderProjection]
    ) async throws {
        let context = ModelContext(syncModelContainer)

        // 1. Create Arcs first (Stacks reference arcId)
        populateArcs(arcs, into: context)

        // 2. Create Tags (Stacks reference tags by ID)
        let tagMap = populateTags(tags, into: context)

        // 3. Create Stacks (without tasks — tasks are fetched separately)
        let stackMap = try populateStacks(stacks, tagMap: tagMap, into: context)

        // 4. Create Tasks (fetched separately via GET /v1/tasks)
        try populateTasks(tasks, stackMap: stackMap, into: context)

        // 5. Create Reminders (must be after Stacks, Arcs, Tasks for foreign key refs)
        try populateReminders(reminders, into: context)

        try context.save()
        let sc = stacks.count, tc = tasks.count, ac = arcs.count
        let tgc = tags.count, rc = reminders.count
        os_log("[Sync] Populated \(sc) stacks, \(tc) tasks, \(ac) arcs, \(tgc) tags, \(rc) reminders")
    }

    @MainActor
    private func populateArcs(_ arcs: [ArcProjection], into context: ModelContext) {
        for arcData in arcs {
            let arc = Arc(
                id: arcData.id,
                title: arcData.title,
                arcDescription: arcData.description,
                colorHex: arcData.color,
                createdAt: dateFromUnixMs(arcData.createdAt),
                updatedAt: dateFromUnixMs(arcData.updatedAt),
                isDeleted: arcData.isDeleted
            )
            context.insert(arc)
        }
    }

    @MainActor
    private func populateTags(
        _ tags: [TagProjection], into context: ModelContext
    ) -> [String: Tag] {
        var tagMap: [String: Tag] = [:]
        for tagData in tags {
            let tag = Tag(
                id: tagData.id,
                name: tagData.name,
                colorHex: tagData.color,
                createdAt: dateFromUnixMs(tagData.createdAt)
            )
            context.insert(tag)
            tagMap[tag.id] = tag
        }
        return tagMap
    }

    @MainActor
    private func populateStacks(
        _ stacks: [StackProjection],
        tagMap: [String: Tag],
        into context: ModelContext
    ) throws -> [String: Stack] {
        var stackMap: [String: Stack] = [:]
        for stackData in stacks {
            let stack = Stack(
                id: stackData.id,
                title: stackData.title,
                stackDescription: stackData.description,
                startTime: dateFromUnixMs(stackData.startTime),
                dueTime: dateFromUnixMs(stackData.dueTime),
                createdAt: dateFromUnixMs(stackData.createdAt),
                updatedAt: dateFromUnixMs(stackData.updatedAt),
                isDeleted: stackData.isDeleted,
                isActive: stackData.isActive
            )
            stack.status = parseStackStatus(stackData.status)

            // Link to Arc if present
            if let arcId = stackData.arcId {
                let fetchDescriptor = FetchDescriptor<Arc>(
                    predicate: #Predicate<Arc> { $0.id == arcId }
                )
                if let arc = try context.fetch(fetchDescriptor).first {
                    stack.arc = arc
                }
            }

            // Populate tags: both the string array (tag IDs) and tagObjects relationship
            if let tagIds = stackData.tags {
                stack.tags = tagIds  // String array of tag IDs
                for tagId in tagIds {
                    if let tag = tagMap[tagId] {
                        stack.tagObjects.append(tag)
                    }
                }
            }

            context.insert(stack)
            stackMap[stack.id] = stack
        }
        return stackMap
    }

    @MainActor
    private func populateTasks(
        _ tasks: [TaskProjection],
        stackMap: [String: Stack],
        into context: ModelContext
    ) throws {
        for taskData in tasks {
            let taskStackId = taskData.stackId
            let stack: Stack?
            if let cached = stackMap[taskStackId] {
                stack = cached
            } else {
                let fetchDescriptor = FetchDescriptor<Stack>(
                    predicate: #Predicate<Stack> { $0.id == taskStackId }
                )
                stack = try context.fetch(fetchDescriptor).first
            }

            guard let parentStack = stack else {
                os_log(
                    "[Sync] Skipping task \(taskData.id) — parent stack \(taskStackId) not found"
                )
                continue
            }

            let task = QueueTask(
                id: taskData.id,
                title: taskData.title,
                taskDescription: taskData.description,
                startTime: dateFromUnixMs(taskData.startTime),
                dueTime: dateFromUnixMs(taskData.dueTime),
                status: parseTaskStatus(taskData.status),
                sortOrder: taskData.sortOrder,
                createdAt: dateFromUnixMs(taskData.createdAt),
                updatedAt: dateFromUnixMs(taskData.updatedAt),
                stack: parentStack
            )
            context.insert(task)
        }
    }

    @MainActor
    private func populateReminders(
        _ reminders: [ReminderProjection], into context: ModelContext
    ) throws {
        for reminderData in reminders {
            // Determine parent type and ID
            let (parentType, parentId): (ParentType, String)
            if let stackId = reminderData.stackId {
                parentType = .stack
                parentId = stackId
            } else if let taskId = reminderData.taskId {
                parentType = .task
                parentId = taskId
            } else if let arcId = reminderData.arcId {
                parentType = .arc
                parentId = arcId
            } else {
                os_log("[Sync] Skipping reminder \(reminderData.id) — no parent ID")
                continue
            }

            let reminder = Reminder(
                id: reminderData.id,
                parentId: parentId,
                parentType: parentType,
                remindAt: dateFromUnixMs(reminderData.triggerTime),
                createdAt: dateFromUnixMs(reminderData.createdAt),
                isDeleted: reminderData.isDeleted
            )

            // Link to Stack if present
            if let stackId = reminderData.stackId {
                let fetchDescriptor = FetchDescriptor<Stack>(
                    predicate: #Predicate<Stack> { $0.id == stackId }
                )
                if let stack = try context.fetch(fetchDescriptor).first {
                    reminder.stack = stack
                }
            }

            // Link to Arc if present
            if let arcId = reminderData.arcId {
                let fetchDescriptor = FetchDescriptor<Arc>(
                    predicate: #Predicate<Arc> { $0.id == arcId }
                )
                if let arc = try context.fetch(fetchDescriptor).first {
                    reminder.arc = arc
                }
            }

            // Link to Task if present
            if let taskId = reminderData.taskId {
                let fetchDescriptor = FetchDescriptor<QueueTask>(
                    predicate: #Predicate<QueueTask> { $0.id == taskId }
                )
                if let task = try context.fetch(fetchDescriptor).first {
                    reminder.task = task
                }
            }

            context.insert(reminder)
        }
    }

    // MARK: - Projection Helpers

    /// Parses ISO8601 date string, returns nil if invalid.
    /// Marked nonisolated because it only does pure string parsing with no actor state access.
    nonisolated func parseISO8601(_ string: String?) -> Date? {
        guard let string = string else { return nil }
        return Self.iso8601Standard.date(from: string)
    }

    /// Converts a Unix millisecond timestamp to Date.
    nonisolated func dateFromUnixMs(_ ms: Int64) -> Date {
        Date(timeIntervalSince1970: Double(ms) / 1_000.0)
    }

    /// Converts an optional Unix millisecond timestamp to Date.
    nonisolated func dateFromUnixMs(_ ms: Int64?) -> Date? {
        guard let ms = ms else { return nil }
        return Date(timeIntervalSince1970: Double(ms) / 1_000.0)
    }

    /// Parses stack status string to enum.
    nonisolated func parseStackStatus(_ status: String) -> StackStatus {
        switch status.lowercased() {
        case "active": return .active
        case "completed": return .completed
        case "closed": return .closed
        case "archived": return .archived
        case "draft": return .active
        case "in_progress": return .active
        default: return .active
        }
    }

    /// Parses task status string to enum.
    nonisolated func parseTaskStatus(_ status: String) -> TaskStatus {
        switch status.lowercased() {
        case "pending": return .pending
        case "completed": return .completed
        case "blocked": return .blocked
        case "closed": return .closed
        case "in_progress": return .pending
        default: return .pending
        }
    }
}
