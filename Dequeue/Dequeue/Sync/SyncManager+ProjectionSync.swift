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
        let syncStart = Date()
        let syncId = Self.generateSyncId()
        os_log("[Sync] Projection sync started: syncId=\(syncId)")

        await MainActor.run {
            ErrorReportingService.logProjectionSyncStart()
        }

        isInitialSyncActive = true
        syncStatusMessage = "Connecting to server\u{2026}"
        defer {
            isInitialSyncActive = false
            syncStatusMessage = ""
        }

        guard let token = try await refreshToken() else {
            os_log("[Sync] Projection sync failed: Not authenticated")
            throw SyncError.notAuthenticated
        }

        let baseURL = await MainActor.run { Configuration.dequeueAPIBaseURL }

        // ── Fetch phase ──────────────────────────────────────────────────────────────
        // DEQ-248: Record fetch-phase wall-clock timing for Sentry performance transaction.
        syncStatusMessage = "Fetching your data\u{2026}"
        let fetchStart = Date()

        // Fetch all resource types in parallel
        // Note: dequeueAPIBaseURL already includes /v1 prefix, so paths are relative
        async let stacksTask: [StackProjection] = fetchProjectionPage(
            StackProjection.self, url: "\(baseURL)/stacks", token: token
        )
        async let tasksTask: [TaskProjection] = fetchProjectionPage(
            TaskProjection.self, url: "\(baseURL)/tasks", token: token
        )
        async let arcsTask: [ArcProjection] = fetchProjectionPage(
            ArcProjection.self, url: "\(baseURL)/arcs", token: token
        )
        async let tagsTask: [TagProjection] = fetchProjectionPage(
            TagProjection.self, url: "\(baseURL)/tags", token: token
        )
        async let remindersTask: [ReminderProjection] = fetchProjectionPage(
            ReminderProjection.self, url: "\(baseURL)/reminders", token: token
        )

        do {
            // Await each task individually to help the type-checker
            let stacks = try await stacksTask
            let tasks = try await tasksTask
            let arcs = try await arcsTask
            let tags = try await tagsTask
            let reminders = try await remindersTask

            let fetchDurationMs = Int(Date().timeIntervalSince(fetchStart) * 1_000)

            let sc = stacks.count, tc = tasks.count, ac = arcs.count
            let tgc = tags.count, rc = reminders.count
            os_log("[Sync] Fetched projections: \(sc) stacks, \(tc) tasks, \(ac) arcs, \(tgc) tags, \(rc) reminders")

            // ── Populate phase ────────────────────────────────────────────────────────
            syncStatusMessage = "Saving locally\u{2026}"
            let populateStart = Date()
            try await populateFromProjections(
                stacks: stacks, tasks: tasks, arcs: arcs, tags: tags, reminders: reminders
            )
            let populateDurationMs = Int(Date().timeIntervalSince(populateStart) * 1_000)

            // Set checkpoint to now (all future events will be synced incrementally)
            let checkpoint = Self.iso8601Standard.string(from: Date())
            saveLastSyncCheckpoint(checkpoint)

            let duration = Date().timeIntervalSince(syncStart)
            let durationFormatted = String(format: "%.2f", duration)
            os_log("[Sync] Projection sync complete: syncId=\(syncId), duration=\(durationFormatted)s")

            await MainActor.run {
                // Existing breadcrumb + log
                ErrorReportingService.logProjectionSyncComplete(
                    stacks: stacks.count,
                    tasks: tasks.count,
                    arcs: arcs.count,
                    tags: tags.count,
                    reminders: reminders.count,
                    duration: duration
                )

                // DEQ-248: Record Sentry performance transaction with retroactive start time.
                // All Sentry Span API calls must happen on MainActor (strict concurrency).
                ErrorReportingService.recordProjectionSyncTransaction(
                    .init(
                        syncId: syncId,
                        syncStart: syncStart,
                        fetchDurationMs: fetchDurationMs,
                        populateDurationMs: populateDurationMs,
                        stacks: stacks.count,
                        tasks: tasks.count,
                        arcs: arcs.count,
                        tags: tags.count,
                        reminders: reminders.count,
                        success: true
                    )
                )
            }

            await ErrorReportingService.logSyncComplete(
                syncId: syncId,
                duration: duration,
                itemsUploaded: 0,  // Projection sync only downloads
                itemsDownloaded: stacks.count + tasks.count + arcs.count + tags.count + reminders.count
            )
        } catch {
            let duration = Date().timeIntervalSince(syncStart)
            os_log("[Sync] Projection sync failed: \(error.localizedDescription)")
            await MainActor.run {
                ErrorReportingService.logProjectionSyncFailed(error: error, duration: duration)
                // DEQ-248: Still record a failed transaction so we can see failure rates.
                ErrorReportingService.recordProjectionSyncTransaction(
                    .init(
                        syncId: syncId,
                        syncStart: syncStart,
                        fetchDurationMs: Int(duration * 1_000),
                        populateDurationMs: 0,
                        stacks: 0, tasks: 0, arcs: 0, tags: 0, reminders: 0,
                        success: false
                    )
                )
            }
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
        var currentToken = token  // Mutable so 401-retry can update for subsequent pages

        while let urlString = currentURL {
            guard let url = URL(string: urlString) else {
                os_log("[Sync] Invalid URL string: \(urlString)")
                throw SyncError.pullFailed
            }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(currentToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let fetchStart = Date()
            let (data, response) = try await syncSession.data(for: request)
            let fetchDuration = Date().timeIntervalSince(fetchStart)

            guard let httpResponse = response as? HTTPURLResponse else {
                os_log("[Sync] Invalid response type for \(urlString)")
                throw SyncError.pullFailed
            }

            // Log every projection fetch for observability (DEQ-246/247)
            await MainActor.run {
                ErrorReportingService.logSyncNetworkRequest(
                    method: "GET",
                    url: urlString,
                    statusCode: httpResponse.statusCode,
                    responseSize: data.count,
                    duration: fetchDuration,
                    error: httpResponse.statusCode >= 400 ? String(data: data, encoding: .utf8) : nil
                )
            }

            // If token was rejected, refresh once and retry — mirrors syncPull 401 handling.
            // This resolves DEQUEUE-APP-1/DEQUEUE-APP-6 where stale tokens cause pullFailed
            // on projection sync endpoints (/v1/tags, /v1/stacks, etc.).
            let decodeData: Data
            if httpResponse.statusCode == 401 {
                os_log("[Sync] Token rejected during projection fetch, refreshing...")
                guard let newToken = try await refreshToken() else {
                    os_log("[Sync] Token refresh failed during projection fetch")
                    throw SyncError.notAuthenticated
                }
                currentToken = newToken
                request.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                let (retryData, retryResponse) = try await syncSession.data(for: request)
                guard let retryHTTP = retryResponse as? HTTPURLResponse,
                      retryHTTP.statusCode == 200 else {
                    let retryStatus = (retryResponse as? HTTPURLResponse)?.statusCode ?? -1
                    os_log("[Sync] Projection fetch retry failed with status: \(retryStatus)")
                    throw SyncError.pullFailed
                }
                decodeData = retryData
            } else {
                guard httpResponse.statusCode == 200 else {
                    if let responseBody = String(data: data, encoding: .utf8) {
                        os_log(
                            "[Sync] Projection fetch failed (\(httpResponse.statusCode)): \(responseBody)"
                        )
                    }
                    throw SyncError.pullFailed
                }
                decodeData = data
            }

            let decoded = try JSONDecoder().decode(ProjectionResponse<T>.self, from: decodeData)
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
                startTime: dateFromUnixMs(arcData.startTime),
                dueTime: dateFromUnixMs(arcData.dueTime),
                createdAt: dateFromUnixMs(arcData.createdAt),
                updatedAt: dateFromUnixMs(arcData.updatedAt),
                isDeleted: arcData.isDeleted
            )
            arc.status = Self.parseArcStatus(arcData.status)
            arc.sortOrder = arcData.sortOrder
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
                createdAt: dateFromUnixMs(tagData.createdAt),
                updatedAt: dateFromUnixMs(tagData.updatedAt)
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
            stack.status = Self.parseStackStatus(stackData.status)
            stack.sortOrder = stackData.sortOrder
            stack.activeTaskId = stackData.activeTaskId

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
                taskDescription: taskData.notes,
                startTime: dateFromUnixMs(taskData.startTime),
                dueTime: dateFromUnixMs(taskData.dueTime),
                status: Self.parseTaskStatus(taskData.status),
                priority: taskData.priority,
                blockedReason: taskData.blockedReason,
                sortOrder: taskData.sortOrder,
                createdAt: dateFromUnixMs(taskData.createdAt),
                updatedAt: dateFromUnixMs(taskData.updatedAt),
                completedAt: dateFromUnixMs(taskData.completedAt),
                stack: parentStack,
                parentTaskId: taskData.parentTaskId
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
                status: Self.parseReminderStatus(reminderData.status),
                snoozedFrom: dateFromUnixMs(reminderData.snoozedFrom),
                remindAt: dateFromUnixMs(reminderData.triggerTime),
                createdAt: dateFromUnixMs(reminderData.createdAt),
                updatedAt: dateFromUnixMs(reminderData.updatedAt),
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

    /// Parses arc status string to enum.
    nonisolated static func parseArcStatus(_ status: String) -> ArcStatus {
        switch status.lowercased() {
        case "active": return .active
        case "completed": return .completed
        case "paused": return .paused
        case "archived": return .archived
        default: return .active
        }
    }

    /// Parses stack status string to enum.
    /// Handles legacy values: "draft" and "in_progress" map to `.active`.
    nonisolated static func parseStackStatus(_ status: String) -> StackStatus {
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
    /// Handles legacy value: "in_progress" maps to `.pending`.
    nonisolated static func parseTaskStatus(_ status: String) -> TaskStatus {
        switch status.lowercased() {
        case "pending": return .pending
        case "completed": return .completed
        case "blocked": return .blocked
        case "closed": return .closed
        case "in_progress": return .pending
        default: return .pending
        }
    }

    /// Parses reminder status string to enum.
    nonisolated static func parseReminderStatus(_ status: String) -> ReminderStatus {
        switch status.lowercased() {
        case "active": return .active
        case "snoozed": return .snoozed
        case "fired": return .fired
        default: return .active
        }
    }
}
