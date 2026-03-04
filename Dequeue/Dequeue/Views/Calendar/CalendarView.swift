//
//  CalendarView.swift
//  Dequeue
//
//  Shows tasks, stacks, arcs, reminders, and calendar events in a unified timeline view
//

import SwiftUI
import SwiftData

// MARK: - Unified Calendar Item

/// A single item in the unified calendar timeline.
/// Wraps calendar events, tasks, stacks, arcs, and reminders into a sortable timeline.
enum CalendarItem: Identifiable {
    case calendarEvent(CalendarEvent)
    case task(QueueTask, dateType: DateType)
    case stack(Stack, dateType: DateType)
    case arc(Arc, dateType: DateType)
    case reminder(Reminder, parent: ReminderParent)

    enum DateType: String {
        case startAt = "Starts"
        case dueAt = "Due"
    }

    enum ReminderParent {
        case stack(Stack)
        case task(QueueTask)
        case arc(Arc)

        var title: String {
            switch self {
            case .stack(let parentStack): return parentStack.title
            case .task(let parentTask): return parentTask.title
            case .arc(let parentArc): return parentArc.title
            }
        }
    }

    var id: String {
        switch self {
        case let .calendarEvent(event): return "event-\(event.id)"
        case let .task(task, dateType): return "task-\(task.id)-\(dateType.rawValue)"
        case let .stack(stack, dateType): return "stack-\(stack.id)-\(dateType.rawValue)"
        case let .arc(arc, dateType): return "arc-\(arc.id)-\(dateType.rawValue)"
        case let .reminder(reminder, _): return "reminder-\(reminder.id)"
        }
    }

    /// The time used for sorting in the timeline
    var sortTime: Date {
        switch self {
        case let .calendarEvent(event):
            return event.startDate
        case let .task(task, dateType):
            return dateType == .startAt ? (task.startTime ?? .distantFuture) : (task.dueTime ?? .distantFuture)
        case let .stack(stack, dateType):
            return dateType == .startAt ? (stack.startTime ?? .distantFuture) : (stack.dueTime ?? .distantFuture)
        case let .arc(arc, dateType):
            return dateType == .startAt ? (arc.startTime ?? .distantFuture) : (arc.dueTime ?? .distantFuture)
        case let .reminder(reminder, _):
            return reminder.remindAt
        }
    }

    /// Whether this is an all-day item (no specific time)
    var isAllDay: Bool {
        if case .calendarEvent(let event) = self { return event.isAllDay }
        return false
    }
}

// MARK: - Calendar View

struct CalendarView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var calendarService = CalendarService.shared

    @State private var selectedDate = Date()
    @State private var showImportSheet = false
    @State private var selectedEventForImport: CalendarEvent?
    @State private var selectedStack: Stack?
    @State private var selectedTask: QueueTask?
    @State private var selectedArc: Arc?

    // Query all non-deleted tasks
    @Query(
        filter: #Predicate<QueueTask> { task in
            task.isDeleted == false
        },
        sort: [SortDescriptor(\QueueTask.dueTime)]
    )
    private var allTasksRaw: [QueueTask]

    // Query all non-deleted stacks
    @Query(
        filter: #Predicate<Stack> { stack in
            stack.isDeleted == false
        },
        sort: [SortDescriptor(\Stack.dueTime)]
    )
    private var allStacksRaw: [Stack]

    // Query all non-deleted arcs
    @Query(
        filter: #Predicate<Arc> { arc in
            arc.isDeleted == false
        },
        sort: [SortDescriptor(\Arc.dueTime)]
    )
    private var allArcsRaw: [Arc]

    // Query all non-deleted reminders
    @Query(
        filter: #Predicate<Reminder> { reminder in
            reminder.isDeleted == false
        },
        sort: [SortDescriptor(\Reminder.remindAt)]
    )
    private var allReminders: [Reminder]

    /// Filtered to exclude completed/closed tasks
    private var activeTasks: [QueueTask] {
        allTasksRaw.filter { $0.status != .completed && $0.status != .closed }
    }

    /// Filtered to active stacks only
    private var activeStacks: [Stack] {
        allStacksRaw.filter { $0.status == .active }
    }

    /// Filtered to active arcs only
    private var activeArcs: [Arc] {
        allArcsRaw.filter { $0.status == .active }
    }

    /// Active reminders only
    private var activeReminders: [Reminder] {
        allReminders.filter { $0.status == .active }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                dateHeader

                if calendarService.isAuthorized {
                    authorizedContent
                } else {
                    unauthorizedContent
                }
            }
            .navigationTitle("Calendar")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(for: QueueTask.self) { task in
                TaskDetailView(task: task)
            }
            .sheet(item: $selectedStack) { stack in
                StackEditorView(mode: .edit(stack))
            }
            .sheet(item: $selectedTask) { task in
                TaskDetailView(task: task)
            }
            .sheet(item: $selectedArc) { arc in
                ArcEditorView(mode: .edit(arc))
            }
            .task {
                if calendarService.isAuthorized {
                    await calendarService.refreshEvents()
                }
            }
        }
    }

    // MARK: - Date Header

    private var dateHeader: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(-1..<7, id: \.self) { offset in
                    let date = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
                    DateChip(
                        date: date,
                        isSelected: Calendar.current.isDate(date, inSameDayAs: selectedDate),
                        hasEvents: hasCalendarEvents(on: date),
                        hasTasks: hasDequeueItems(on: date)
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedDate = date
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        #if os(iOS)
        .background(Color(.systemGroupedBackground))
        #else
        .background(Color(.windowBackgroundColor))
        #endif
    }

    // MARK: - Authorized Content

    private var authorizedContent: some View {
        let items = unifiedTimelineItems(for: selectedDate)

        return Group {
            if items.isEmpty {
                List {
                    Section {
                        ContentUnavailableView {
                            Label("No Events", systemImage: "calendar")
                        } description: {
                            Text("Nothing scheduled for \(formattedDate(selectedDate))")
                        }
                    }
                }
            } else {
                List {
                    // All-day items first
                    let allDayItems = items.filter(\.isAllDay)
                    if !allDayItems.isEmpty {
                        Section("All Day") {
                            ForEach(allDayItems) { item in
                                calendarItemRow(item)
                            }
                        }
                    }

                    // Timed items in chronological order
                    let timedItems = items.filter { !$0.isAllDay }
                    if !timedItems.isEmpty {
                        Section("Timeline") {
                            ForEach(timedItems) { item in
                                calendarItemRow(item)
                            }
                        }
                    }
                }
            }
        }
        .refreshable {
            await calendarService.refreshEvents()
        }
        .sheet(isPresented: $showImportSheet) {
            if let event = selectedEventForImport {
                ImportEventSheet(event: event)
            }
        }
    }

    // MARK: - Unified Timeline Builder

    private func unifiedTimelineItems(for date: Date) -> [CalendarItem] {
        let calendar = Calendar.current
        var items: [CalendarItem] = []

        items += calendarEventItems(for: date)
        items += taskItems(for: date, calendar: calendar)
        items += stackItems(for: date, calendar: calendar)
        items += arcItems(for: date, calendar: calendar)
        items += reminderItems(for: date, calendar: calendar)

        return items.sorted { $0.sortTime < $1.sortTime }
    }

    private func calendarEventItems(for date: Date) -> [CalendarItem] {
        calendarService.events(for: date).map { .calendarEvent($0) }
    }

    private func taskItems(for date: Date, calendar: Calendar) -> [CalendarItem] {
        var items: [CalendarItem] = []
        for task in activeTasks {
            let startIsOnDay = task.startTime.map { calendar.isDate($0, inSameDayAs: date) } ?? false
            if startIsOnDay {
                items.append(.task(task, dateType: .startAt))
            }
            if let dueTime = task.dueTime, calendar.isDate(dueTime, inSameDayAs: date) {
                // Skip dueAt if start is on same day with identical time (avoid duplicate)
                if !(startIsOnDay && task.startTime == task.dueTime) {
                    items.append(.task(task, dateType: .dueAt))
                }
            }
        }
        return items
    }

    private func stackItems(for date: Date, calendar: Calendar) -> [CalendarItem] {
        var items: [CalendarItem] = []
        for stack in activeStacks {
            let startIsOnDay = stack.startTime.map { calendar.isDate($0, inSameDayAs: date) } ?? false
            if startIsOnDay {
                items.append(.stack(stack, dateType: .startAt))
            }
            if let dueTime = stack.dueTime, calendar.isDate(dueTime, inSameDayAs: date) {
                if !(startIsOnDay && stack.startTime == stack.dueTime) {
                    items.append(.stack(stack, dateType: .dueAt))
                }
            }
        }
        return items
    }

    private func arcItems(for date: Date, calendar: Calendar) -> [CalendarItem] {
        var items: [CalendarItem] = []
        for arc in activeArcs {
            let startIsOnDay = arc.startTime.map { calendar.isDate($0, inSameDayAs: date) } ?? false
            if startIsOnDay {
                items.append(.arc(arc, dateType: .startAt))
            }
            if let dueTime = arc.dueTime, calendar.isDate(dueTime, inSameDayAs: date) {
                if !(startIsOnDay && arc.startTime == arc.dueTime) {
                    items.append(.arc(arc, dateType: .dueAt))
                }
            }
        }
        return items
    }

    private func reminderItems(for date: Date, calendar: Calendar) -> [CalendarItem] {
        var items: [CalendarItem] = []
        for reminder in activeReminders where calendar.isDate(reminder.remindAt, inSameDayAs: date) {
            if let stack = reminder.stack {
                items.append(.reminder(reminder, parent: .stack(stack)))
            } else if let task = reminder.task {
                items.append(.reminder(reminder, parent: .task(task)))
            } else if let arc = reminder.arc {
                items.append(.reminder(reminder, parent: .arc(arc)))
            }
        }
        return items
    }

    // MARK: - Row Rendering

    @ViewBuilder
    private func calendarItemRow(_ item: CalendarItem) -> some View {
        switch item {
        case .calendarEvent(let event):
            CalendarEventRow(event: event) {
                selectedEventForImport = event
                showImportSheet = true
            }

        case let .task(task, dateType):
            NavigationLink(value: task) {
                DequeueItemRow(
                    title: task.title,
                    time: dateType == .startAt ? task.startTime : task.dueTime,
                    dateLabel: dateType.rawValue,
                    icon: "checklist",
                    iconColor: .blue,
                    parentTitle: task.stack?.title,
                    isOverdue: dateType == .dueAt && (task.dueTime ?? .distantFuture) < Date()
                )
            }

        case let .stack(stack, dateType):
            Button {
                selectedStack = stack
            } label: {
                DequeueItemRow(
                    title: stack.title,
                    time: dateType == .startAt ? stack.startTime : stack.dueTime,
                    dateLabel: dateType.rawValue,
                    icon: "square.stack.3d.up",
                    iconColor: .purple,
                    parentTitle: nil,
                    isOverdue: dateType == .dueAt && (stack.dueTime ?? .distantFuture) < Date()
                )
            }
            .buttonStyle(.plain)

        case let .arc(arc, dateType):
            Button {
                selectedArc = arc
            } label: {
                DequeueItemRow(
                    title: arc.title,
                    time: dateType == .startAt ? arc.startTime : arc.dueTime,
                    dateLabel: dateType.rawValue,
                    icon: "arrow.triangle.branch",
                    iconColor: .orange,
                    parentTitle: nil,
                    isOverdue: dateType == .dueAt && (arc.dueTime ?? .distantFuture) < Date()
                )
            }
            .buttonStyle(.plain)

        case let .reminder(reminder, parent):
            Button {
                switch parent {
                case let .stack(parentStack): selectedStack = parentStack
                case let .task(parentTask): selectedTask = parentTask
                case let .arc(parentArc): selectedArc = parentArc
                }
            } label: {
                DequeueItemRow(
                    title: parent.title,
                    time: reminder.remindAt,
                    dateLabel: "Reminder",
                    icon: "bell",
                    iconColor: .red,
                    parentTitle: nil,
                    isOverdue: reminder.remindAt < Date()
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Unauthorized Content

    private var unauthorizedContent: some View {
        ContentUnavailableView {
            Label("Calendar Access", systemImage: "calendar.badge.exclamationmark")
        } description: {
            Text("Grant calendar access to see your events alongside tasks")
        } actions: {
            Button("Allow Access") {
                Task { await calendarService.requestAccess() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Helpers

    private func hasCalendarEvents(on date: Date) -> Bool {
        !calendarService.events(for: date).isEmpty
    }

    private func hasDequeueItems(on date: Date) -> Bool {
        let calendar = Calendar.current
        let hasTask = activeTasks.contains { task in
            task.startTime.map { calendar.isDate($0, inSameDayAs: date) } == true ||
            task.dueTime.map { calendar.isDate($0, inSameDayAs: date) } == true
        }
        let hasStack = activeStacks.contains { stack in
            stack.startTime.map { calendar.isDate($0, inSameDayAs: date) } == true ||
            stack.dueTime.map { calendar.isDate($0, inSameDayAs: date) } == true
        }
        let hasArc = activeArcs.contains { arc in
            arc.startTime.map { calendar.isDate($0, inSameDayAs: date) } == true ||
            arc.dueTime.map { calendar.isDate($0, inSameDayAs: date) } == true
        }
        let hasReminder = activeReminders.contains { reminder in
            calendar.isDate(reminder.remindAt, inSameDayAs: date)
        }
        return hasTask || hasStack || hasArc || hasReminder
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Dequeue Item Row (Unified style for tasks/stacks/arcs/reminders)

struct DequeueItemRow: View {
    let title: String
    let time: Date?
    let dateLabel: String
    let icon: String
    let iconColor: Color
    let parentTitle: String?
    let isOverdue: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Type icon
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(dateLabel)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(isOverdue ? .red : iconColor)

                    if let time {
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(time, style: .time)
                            .font(.caption)
                            .foregroundStyle(isOverdue ? .red : .secondary)
                    }

                    if let parentTitle {
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(parentTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Date Chip

struct DateChip: View {
    let date: Date
    let isSelected: Bool
    let hasEvents: Bool
    let hasTasks: Bool
    let onTap: () -> Void

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Text(dayOfWeek)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(isSelected ? .white : .secondary)

                Text(dayNumber)
                    .font(.title3)
                    .fontWeight(isToday ? .bold : .regular)
                    .foregroundStyle(isSelected ? .white : .primary)

                HStack(spacing: 2) {
                    if hasTasks {
                        Circle()
                            .fill(isSelected ? .white : .blue)
                            .frame(width: 4, height: 4)
                    }
                    if hasEvents {
                        Circle()
                            .fill(isSelected ? .white.opacity(0.7) : .orange)
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(height: 4)
            }
            .frame(width: 48, height: 64)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor : (isToday ? Color.accentColor.opacity(0.1) : .clear))
            )
        }
        .buttonStyle(.plain)
    }

    private var dayOfWeek: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private var dayNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }
}

// MARK: - Calendar Event Row

struct CalendarEventRow: View {
    let event: CalendarEvent
    let onImport: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Calendar color indicator
            RoundedRectangle(cornerRadius: 2)
                .fill(calendarColor)
                .frame(width: 4, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if event.isAllDay {
                        Text("All day")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(event.startDate, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("–")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(event.endDate, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let location = event.location, !location.isEmpty {
                        Text("• \(location)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            Button {
                onImport()
            } label: {
                Image(systemName: "plus.circle")
                    .font(.title3)
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)
            .help("Import as task")
        }
        .padding(.vertical, 2)
    }

    private var calendarColor: Color {
        if let hex = event.calendarColor {
            return Color(hex: hex) ?? .blue
        }
        return .blue
    }
}

// MARK: - Import Event Sheet

struct ImportEventSheet: View {
    let event: CalendarEvent
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.syncManager) private var syncManager
    @Environment(\.authService) private var authService

    @State private var title: String
    @State private var description: String
    @State private var startTime: Date?
    @State private var dueTime: Date?
    @State private var selectedStack: Stack?
    @State private var showError = false
    @State private var errorMessage = ""

    @Query(
        filter: #Predicate<Stack> { stack in
            stack.isDeleted == false
        },
        sort: [SortDescriptor(\Stack.sortOrder)]
    )
    private var allStacks: [Stack]

    /// Filtered to active stacks only
    private var activeStacks: [Stack] {
        allStacks.filter { $0.status == .active }
    }

    init(event: CalendarEvent) {
        self.event = event
        let data = CalendarService.shared.taskDataFromEvent(event)
        _title = State(initialValue: data.title)
        _description = State(initialValue: data.description ?? "")
        _startTime = State(initialValue: data.startTime)
        _dueTime = State(initialValue: data.dueTime)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section("Dates") {
                    if let startTime {
                        LabeledContent("Start") {
                            Text(startTime, style: .date)
                            Text(startTime, style: .time)
                        }
                    }
                    if let dueTime {
                        LabeledContent("End") {
                            Text(dueTime, style: .date)
                            Text(dueTime, style: .time)
                        }
                    }
                }

                Section("Add to Stack") {
                    if activeStacks.isEmpty {
                        Text("No active stacks")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(activeStacks) { stack in
                            Button {
                                selectedStack = stack
                            } label: {
                                HStack {
                                    Text(stack.title)
                                    Spacer()
                                    if selectedStack?.id == stack.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.blue)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }

                if let location = event.location, !location.isEmpty {
                    Section("Location") {
                        Text(location)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Import Event")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        importAsTask()
                    }
                    .disabled(title.isEmpty || selectedStack == nil)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #else
        .frame(minWidth: 400, minHeight: 300)
        #endif
        .onAppear {
            selectedStack = activeStacks.first
        }
    }

    private func importAsTask() {
        guard let stack = selectedStack else { return }

        Task {
            let deviceId = await DeviceService.shared.getDeviceId()
            let userId = authService.currentUserId ?? ""
            let taskService = TaskService(
                modelContext: modelContext,
                userId: userId,
                deviceId: deviceId,
                syncManager: syncManager
            )
            do {
                _ = try await taskService.createTask(
                    title: title,
                    description: description.isEmpty ? nil : description,
                    startTime: startTime,
                    dueTime: dueTime,
                    stack: stack
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

// MARK: - Preview

#Preview("Calendar View") {
    CalendarView()
}
