//
//  ActivityFeedView.swift
//  Dequeue
//
//  Activity feed showing recent accomplishments as a scrollable timeline
//

import SwiftUI
import SwiftData
import os

private let logger = Logger(subsystem: "com.dequeue", category: "ActivityFeedView")

struct ActivityFeedView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allEvents: [Event]
    @Query private var allStacks: [Stack]

    @State private var selectedStack: Stack?
    @State private var loadedDays: Int = 7
    @State private var showStackNotFoundAlert: Bool = false

    /// Event types to display in the activity feed (per PRD Section 3.8)
    private static let activityEventTypes: Set<String> = [
        EventType.stackCompleted.rawValue,
        EventType.stackActivated.rawValue,
        EventType.stackCreated.rawValue,
        EventType.taskCompleted.rawValue,
        EventType.taskActivated.rawValue,
        EventType.arcCompleted.rawValue,
        EventType.arcActivated.rawValue
    ]

    init() {
        // Query all events sorted by timestamp descending (newest first)
        _allEvents = Query(
            sort: \Event.timestamp,
            order: .reverse
        )
        // Query all stacks for efficient in-memory lookup
        _allStacks = Query()
    }

    /// Events filtered to activity-feed-worthy types
    private var activityEvents: [Event] {
        allEvents.filter { Self.activityEventTypes.contains($0.type) }
    }

    /// Events grouped by calendar day
    private var eventsByDay: [(date: Date, events: [Event])] {
        let calendar = Calendar.current
        let cutoffDate = calendar.date(byAdding: .day, value: -loadedDays, to: Date()) ?? Date()

        let filteredEvents = activityEvents.filter { $0.timestamp >= cutoffDate }
        let grouped = Dictionary(grouping: filteredEvents) { event in
            calendar.startOfDay(for: event.timestamp)
        }

        return grouped
            .sorted { $0.key > $1.key }
            .map { (date: $0.key, events: $0.value) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if activityEvents.isEmpty {
                    ActivityEmptyView()
                } else {
                    timelineList
                }
            }
            .navigationTitle("Activity")
        }
        .sheet(item: $selectedStack) { stack in
            StackEditorView(mode: .edit(stack))
        }
        .alert("Stack Not Found", isPresented: $showStackNotFoundAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("This stack may have been deleted or not yet synced to this device.")
        }
    }

    private var timelineList: some View {
        List {
            ForEach(eventsByDay, id: \.date) { dayData in
                Section {
                    ForEach(dayData.events, id: \.id) { event in
                        ActivityEventRow(event: event, onStackSelected: selectStack)
                    }
                } header: {
                    DayHeaderView(date: dayData.date)
                }
            }

            // Load more section - show if there might be older events
            if !eventsByDay.isEmpty && !activityEvents.isEmpty {
                Section {
                    Button {
                        loadMoreDays()
                    } label: {
                        HStack {
                            Spacer()
                            Text("Load Earlier Activity")
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.plain)
    }

    private func loadMoreDays() {
        loadedDays += 7
        logger.debug("Loading more activity days, now showing \(loadedDays) days")
    }

    private func selectStack(withId stackId: String) {
        // Use in-memory lookup from @Query results for better performance
        if let stack = allStacks.first(where: { $0.id == stackId }) {
            selectedStack = stack
        } else {
            logger.warning("Stack not found for activity event: \(stackId)")
            showStackNotFoundAlert = true
        }
    }
}

#Preview {
    ActivityFeedView()
        .modelContainer(for: [Event.self, Stack.self, QueueTask.self], inMemory: true)
}
