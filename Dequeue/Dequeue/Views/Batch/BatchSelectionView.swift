//
//  BatchSelectionView.swift
//  Dequeue
//
//  Multi-select mode for performing batch operations on tasks within a stack.
//  Supports select all, invert selection, and operation toolbar.
//

import SwiftUI
import SwiftData

/// Manages the selection state for batch task operations.
@Observable
@MainActor
final class BatchSelectionManager {
    var isSelecting: Bool = false
    var selectedTaskIds: Set<String> = []
    var lastOperationResult: BatchOperationResult?
    var showingResultBanner: Bool = false

    func toggle(_ taskId: String) {
        if selectedTaskIds.contains(taskId) {
            selectedTaskIds.remove(taskId)
        } else {
            selectedTaskIds.insert(taskId)
        }
    }

    func selectAll(_ tasks: [QueueTask]) {
        selectedTaskIds = Set(tasks.map(\.id))
    }

    func deselectAll() {
        selectedTaskIds.removeAll()
    }

    func invertSelection(_ allTasks: [QueueTask]) {
        let allIds = Set(allTasks.map(\.id))
        selectedTaskIds = allIds.subtracting(selectedTaskIds)
    }

    func isSelected(_ taskId: String) -> Bool {
        selectedTaskIds.contains(taskId)
    }

    func enterSelectionMode() {
        isSelecting = true
        selectedTaskIds.removeAll()
    }

    func exitSelectionMode() {
        isSelecting = false
        selectedTaskIds.removeAll()
    }

    func showResult(_ result: BatchOperationResult) {
        lastOperationResult = result
        showingResultBanner = true
    }
}

/// Toolbar that appears during batch selection mode with action buttons.
struct BatchToolbar: View {
    let selectedCount: Int
    let availableOperations: [BatchOperation]
    let onOperation: (BatchOperation) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                Text("\(selectedCount) selected")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(availableOperations.prefix(5)) { operation in
                            Button {
                                onOperation(operation)
                            } label: {
                                Label(operation.rawValue, systemImage: operation.systemImage)
                                    .font(.caption.weight(.medium))
                                    .labelStyle(.iconOnly)
                            }
                            .buttonStyle(.bordered)
                            .tint(operation.isDestructive ? .red : .accentColor)
                            .controlSize(.small)
                            .accessibilityLabel(operation.rawValue)
                        }

                        if availableOperations.count > 5 {
                            Menu {
                                ForEach(availableOperations.dropFirst(5)) { operation in
                                    Button(role: operation.isDestructive ? .destructive : nil) {
                                        onOperation(operation)
                                    } label: {
                                        Label(operation.rawValue, systemImage: operation.systemImage)
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.caption.weight(.medium))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }

                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .font(.subheadline)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.regularMaterial)
        }
    }
}

/// A selectable task row for batch mode — shows checkbox + task info.
struct BatchSelectableTaskRow: View {
    let task: QueueTask
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button {
            onToggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .animation(.easeInOut(duration: 0.15), value: isSelected)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if let priority = task.priority, priority > 0 {
                            priorityIndicator(priority)
                        }
                        Text(task.title)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 8) {
                        statusBadge(task.status)

                        if let dueTime = task.dueTime {
                            dueDateLabel(dueTime)
                        }

                        if !task.tags.isEmpty {
                            Text(task.tags.prefix(2).joined(separator: ", "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel("\(task.title), \(isSelected ? "selected" : "not selected")")
    }

    @ViewBuilder
    private func priorityIndicator(_ priority: Int) -> some View {
        let color: Color = switch priority {
        case 3: .red
        case 2: .orange
        case 1: .blue
        default: .gray
        }
        Image(systemName: "flag.fill")
            .font(.caption2)
            .foregroundStyle(color)
    }

    @ViewBuilder
    private func statusBadge(_ status: TaskStatus) -> some View {
        let (label, color): (String, Color) = switch status {
        case .pending: ("Pending", .blue)
        case .completed: ("Done", .green)
        case .blocked: ("Blocked", .orange)
        case .closed: ("Closed", .secondary)
        }
        Text(label)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }

    @ViewBuilder
    private func dueDateLabel(_ date: Date) -> some View {
        let isOverdue = date < Date() 
        HStack(spacing: 2) {
            Image(systemName: "calendar")
            Text(date, style: .date)
        }
        .font(.caption2)
        .foregroundStyle(isOverdue ? .red : .secondary)
    }
}

/// Sheet for picking a target stack when doing batch move.
struct BatchMoveSheet: View {
    let stacks: [Stack]
    let excludeStackId: String?
    let onSelect: (Stack) -> Void
    @Environment(\.dismiss) private var dismiss

    var filteredStacks: [Stack] {
        stacks.filter { !$0.isDeleted && $0.id != excludeStackId }
    }

    var body: some View {
        NavigationStack {
            List(filteredStacks, id: \.id) { stack in
                Button {
                    onSelect(stack)
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(stack.title)
                                .font(.body)
                            Text("\(stack.pendingTasks.count) pending tasks")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Move To")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// Sheet for picking priority in batch operations.
struct BatchPrioritySheet: View {
    let onSelect: (Int?) -> Void
    @Environment(\.dismiss) private var dismiss

    private let priorities: [(label: String, value: Int?, color: Color)] = [
        ("None", nil, .gray),
        ("Low", 1, .blue),
        ("Medium", 2, .orange),
        ("High", 3, .red)
    ]

    var body: some View {
        NavigationStack {
            List {
                ForEach(priorities, id: \.label) { priority in
                    Button {
                        onSelect(priority.value)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: priority.value != nil ? "flag.fill" : "flag.slash")
                                .foregroundStyle(priority.color)
                            Text(priority.label)
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Set Priority")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

/// Sheet for picking a due date in batch operations.
struct BatchDueDateSheet: View {
    @State private var selectedDate = Date()
    let onSelect: (Date) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                DatePicker(
                    "Due Date",
                    selection: $selectedDate,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.graphical)
                .padding()

                // Quick date options
                VStack(spacing: 8) {
                    Text("Quick Options")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        quickDateButton("Today") {
                            Calendar.current.startOfDay(for: Date()).addingTimeInterval(17 * 3600)
                        }
                        quickDateButton("Tomorrow") {
                            let tomorrow = Calendar.current.date(
                                byAdding: .day, value: 1,
                                to: Calendar.current.startOfDay(for: Date())
                            ) ?? Date().addingTimeInterval(86400)
                            return tomorrow.addingTimeInterval(17 * 3600)
                        }
                        quickDateButton("Next Week") {
                            let nextWeek = Calendar.current.date(
                                byAdding: .weekOfYear, value: 1,
                                to: Calendar.current.startOfDay(for: Date())
                            ) ?? Date().addingTimeInterval(7 * 86400)
                            return nextWeek.addingTimeInterval(17 * 3600)
                        }
                    }
                }
                .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("Set Due Date")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onSelect(selectedDate)
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func quickDateButton(_ label: String, date: () -> Date) -> some View {
        let targetDate = date()
        Button {
            selectedDate = targetDate
            onSelect(targetDate)
            dismiss()
        } label: {
            Text(label)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.fill.tertiary, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Result banner shown after a batch operation completes.
struct BatchResultBanner: View {
    let result: BatchOperationResult
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: result.isFullSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(result.isFullSuccess ? .green : .orange)

            Text(result.summary)
                .font(.subheadline)

            Spacer()

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(result.isFullSuccess ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
