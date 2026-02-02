//
//  RemindersListView+DateItems.swift
//  Dequeue
//
//  Date-based item filtering and sections for RemindersListView
//

import SwiftUI

// MARK: - Date-Based Item Filtering

extension RemindersListView {
    /// Items (Stacks, Tasks, Arcs) with startTime in the next 24 hours
    var startingSoonItems: [DateScheduledItem] {
        let now = Date()
        let in24Hours = now.addingTimeInterval(24 * 60 * 60)

        var items: [DateScheduledItem] = []

        // Stacks starting soon
        for stack in stacks where stack.status == .active {
            if let startTime = stack.startTime, startTime > now && startTime <= in24Hours {
                items.append(DateScheduledItem(
                    id: stack.id,
                    title: stack.title,
                    date: startTime,
                    parentType: .stack,
                    isStartDate: true
                ))
            }
        }

        // Tasks starting soon
        for task in tasks where task.status == .pending {
            if let startTime = task.startTime, startTime > now && startTime <= in24Hours {
                items.append(DateScheduledItem(
                    id: task.id,
                    title: task.title,
                    date: startTime,
                    parentType: .task,
                    isStartDate: true
                ))
            }
        }

        // Arcs starting soon
        for arc in arcs where arc.status == .active {
            if let startTime = arc.startTime, startTime > now && startTime <= in24Hours {
                items.append(DateScheduledItem(
                    id: arc.id,
                    title: arc.title,
                    date: startTime,
                    parentType: .arc,
                    isStartDate: true
                ))
            }
        }

        return items.sorted { $0.date < $1.date }
    }

    /// Items (Stacks, Tasks, Arcs) with dueTime in the next 48 hours (but not overdue)
    var dueSoonItems: [DateScheduledItem] {
        let now = Date()
        let in48Hours = now.addingTimeInterval(48 * 60 * 60)

        var items: [DateScheduledItem] = []

        // Stacks due soon
        for stack in stacks where stack.status == .active {
            if let dueTime = stack.dueTime, dueTime > now && dueTime <= in48Hours {
                items.append(DateScheduledItem(
                    id: stack.id,
                    title: stack.title,
                    date: dueTime,
                    parentType: .stack,
                    isStartDate: false
                ))
            }
        }

        // Tasks due soon
        for task in tasks where task.status == .pending {
            if let dueTime = task.dueTime, dueTime > now && dueTime <= in48Hours {
                items.append(DateScheduledItem(
                    id: task.id,
                    title: task.title,
                    date: dueTime,
                    parentType: .task,
                    isStartDate: false
                ))
            }
        }

        // Arcs due soon
        for arc in arcs where arc.status == .active {
            if let dueTime = arc.dueTime, dueTime > now && dueTime <= in48Hours {
                items.append(DateScheduledItem(
                    id: arc.id,
                    title: arc.title,
                    date: dueTime,
                    parentType: .arc,
                    isStartDate: false
                ))
            }
        }

        return items.sorted { $0.date < $1.date }
    }

    /// Items (Stacks, Tasks, Arcs) that are past their dueTime but not completed
    var overdueItems: [DateScheduledItem] {
        let now = Date()

        var items: [DateScheduledItem] = []

        // Stacks overdue
        for stack in stacks where stack.status == .active {
            if let dueTime = stack.dueTime, dueTime <= now {
                items.append(DateScheduledItem(
                    id: stack.id,
                    title: stack.title,
                    date: dueTime,
                    parentType: .stack,
                    isStartDate: false
                ))
            }
        }

        // Tasks overdue
        for task in tasks where task.status == .pending {
            if let dueTime = task.dueTime, dueTime <= now {
                items.append(DateScheduledItem(
                    id: task.id,
                    title: task.title,
                    date: dueTime,
                    parentType: .task,
                    isStartDate: false
                ))
            }
        }

        // Arcs overdue
        for arc in arcs where arc.status == .active {
            if let dueTime = arc.dueTime, dueTime <= now {
                items.append(DateScheduledItem(
                    id: arc.id,
                    title: arc.title,
                    date: dueTime,
                    parentType: .arc,
                    isStartDate: false
                ))
            }
        }

        return items.sorted { $0.date < $1.date }
    }
}

// MARK: - Date-Based Item Section Views

extension RemindersListView {
    var overdueItemsSection: some View {
        Section {
            ForEach(overdueItems) { item in
                dateScheduledItemRow(for: item, isOverdue: true)
            }
        } header: {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text("Overdue Items")
            }
        }
    }

    var dueSoonSection: some View {
        Section {
            ForEach(dueSoonItems) { item in
                dateScheduledItemRow(for: item, isOverdue: false)
            }
        } header: {
            HStack {
                Image(systemName: "clock.badge.exclamationmark")
                    .foregroundStyle(.orange)
                Text("Due Soon")
            }
        }
    }

    var startingSoonSection: some View {
        Section {
            ForEach(startingSoonItems) { item in
                dateScheduledItemRow(for: item, isOverdue: false)
            }
        } header: {
            HStack {
                Image(systemName: "play.circle.fill")
                    .foregroundStyle(.green)
                Text("Starting Soon")
            }
        }
    }

    func dateScheduledItemRow(for item: DateScheduledItem, isOverdue: Bool) -> some View {
        Button {
            // Dismiss sheet first, then navigate
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                onGoToItem?(item.id, item.parentType)
            }
        } label: {
            HStack {
                // Icon based on type
                Image(systemName: iconForParentType(item.parentType))
                    .foregroundStyle(isOverdue ? .red : .secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.body)
                        .foregroundStyle(.primary)
                    HStack {
                        Text(item.isStartDate ? "Starts" : "Due")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(item.date.smartFormatted())
                            .font(.caption)
                            .foregroundStyle(isOverdue ? .red : .secondary)
                    }
                }

                Spacer()

                // Type label
                Text(labelForParentType(item.parentType))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    #if os(iOS)
                    .background(Color(.systemGray5))
                    #else
                    .background(Color.gray.opacity(0.2))
                    #endif
                    .clipShape(Capsule())
            }
        }
        .buttonStyle(.plain)
    }

    func iconForParentType(_ type: ParentType) -> String {
        switch type {
        case .stack: return "tray.full"
        case .task: return "checkmark.circle"
        case .arc: return "point.3.filled.connected.trianglepath.dotted"
        }
    }

    func labelForParentType(_ type: ParentType) -> String {
        switch type {
        case .stack: return "Stack"
        case .task: return "Task"
        case .arc: return "Arc"
        }
    }
}
