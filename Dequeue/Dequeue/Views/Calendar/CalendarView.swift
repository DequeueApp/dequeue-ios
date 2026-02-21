//
//  CalendarView.swift
//  Dequeue
//
//  Shows tasks and calendar events in a unified timeline view
//

import SwiftUI
import SwiftData

struct CalendarView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var calendarService = CalendarService.shared

    @State private var selectedDate = Date()
    @State private var showImportSheet = false
    @State private var selectedEventForImport: CalendarEvent?

    @Query(
        filter: #Predicate<QueueTask> { task in
            task.isDeleted == false
        },
        sort: [SortDescriptor(\QueueTask.dueTime)]
    )
    private var allTasksRaw: [QueueTask]

    /// Filtered to exclude completed/closed tasks (predicate can't compare enums)
    private var allTasks: [QueueTask] {
        allTasksRaw.filter { $0.status != .completed && $0.status != .closed }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Date selector
                dateHeader

                // Content
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
                        hasEvents: hasEvents(on: date),
                        hasTasks: hasTasks(on: date)
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
        List {
            // Tasks due on selected date
            let dateTasks = tasksForDate(selectedDate)
            if !dateTasks.isEmpty {
                Section("Tasks Due") {
                    ForEach(dateTasks) { task in
                        NavigationLink {
                            TaskDetailView(task: task)
                        } label: {
                            CalendarTaskRow(task: task)
                        }
                    }
                }
            }

            // Calendar events on selected date
            let dateEvents = calendarService.events(for: selectedDate)
            if !dateEvents.isEmpty {
                Section("Events") {
                    ForEach(dateEvents) { event in
                        CalendarEventRow(event: event) {
                            selectedEventForImport = event
                            showImportSheet = true
                        }
                    }
                }
            }

            // Empty state
            if dateTasks.isEmpty && dateEvents.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("No Events", systemImage: "calendar")
                    } description: {
                        Text("Nothing scheduled for \(formattedDate(selectedDate))")
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

    private func tasksForDate(_ date: Date) -> [QueueTask] {
        let calendar = Calendar.current
        return allTasks.filter { task in
            if let dueTime = task.dueTime {
                return calendar.isDate(dueTime, inSameDayAs: date)
            }
            if let startTime = task.startTime {
                return calendar.isDate(startTime, inSameDayAs: date)
            }
            return false
        }
    }

    private func hasEvents(on date: Date) -> Bool {
        !calendarService.events(for: date).isEmpty
    }

    private func hasTasks(on date: Date) -> Bool {
        !tasksForDate(date).isEmpty
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
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

// MARK: - Calendar Task Row

struct CalendarTaskRow: View {
    let task: QueueTask

    var body: some View {
        HStack(spacing: 12) {
            // Priority indicator
            Circle()
                .fill(priorityColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if let dueTime = task.dueTime {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption2)
                        Text(dueTime, style: .time)
                            .font(.caption)
                    }
                    .foregroundStyle(isOverdue ? .red : .secondary)
                }
            }

            Spacer()

            if let stack = task.stack {
                Text(stack.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private var priorityColor: Color {
        switch task.priority {
        case 1: return .red
        case 2: return .orange
        case 3: return .yellow
        default: return .gray.opacity(0.3)
        }
    }

    private var isOverdue: Bool {
        guard let dueTime = task.dueTime else { return false }
        return dueTime < Date()
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

    /// Filtered to active stacks only (predicate can't compare enums directly)
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
