//
//  StackPickerForArcSheet.swift
//  Dequeue
//
//  Sheet for selecting a stack to add to an arc
//

import SwiftUI
import SwiftData
import os

private let logger = Logger(subsystem: "com.dequeue", category: "StackPickerForArcSheet")

struct StackPickerForArcSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.syncManager) private var syncManager
    @Environment(\.authService) private var authService
    @Environment(\.dismiss) private var dismiss

    @Query private var stacks: [Stack]

    /// The arc to add a stack to
    let arc: Arc

    @State private var arcService: ArcService?
    @State private var errorMessage: String?
    @State private var showError = false

    init(arc: Arc) {
        self.arc = arc

        // Query for stacks that can be assigned to an arc:
        // - Not deleted
        // - Not a draft
        // - Active status
        // - Not already assigned to an arc
        let activeRawValue = StackStatus.active.rawValue
        _stacks = Query(
            filter: #Predicate<Stack> { stack in
                stack.isDeleted == false &&
                stack.isDraft == false &&
                stack.statusRawValue == activeRawValue &&
                stack.arcId == nil
            },
            sort: \Stack.sortOrder
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if stacks.isEmpty {
                    emptyState
                } else {
                    stackList
                }
            }
            .navigationTitle("Add Stack")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { /* Dismiss handled by SwiftUI */ }
            } message: {
                if let errorMessage {
                    Text(errorMessage)
                }
            }
            .task {
                guard arcService == nil else { return }
                let deviceId = await DeviceService.shared.getDeviceId()
                arcService = ArcService(
                    modelContext: modelContext,
                    userId: authService.currentUserId,
                    deviceId: deviceId,
                    syncManager: syncManager
                )
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView(
            "No Stacks Available",
            systemImage: "tray",
            description: Text("All stacks are either assigned to arcs or have been completed")
        )
    }

    // MARK: - Stack List

    private var stackList: some View {
        List {
            ForEach(stacks) { stack in
                Button {
                    selectStack(stack)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(stack.title)
                                .font(.headline)
                                .foregroundStyle(.primary)

                            if let description = stack.stackDescription, !description.isEmpty {
                                Text(description)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            // Task count
                            let pendingCount = stack.pendingTasks.count
                            Text("\(pendingCount) task\(pendingCount == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Actions

    private func selectStack(_ stack: Stack) {
        guard let service = arcService else {
            errorMessage = "Initializing... please try again"
            showError = true
            return
        }

        do {
            try service.assignStack(stack, to: arc)
            dismiss()
        } catch {
            errorMessage = "Failed to add stack to arc: \(error.localizedDescription)"
            showError = true
        }
    }
}

// MARK: - Previews

#Preview("With Stacks") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    // swiftlint:disable:next force_try
    let container = try! ModelContainer(
        for: Arc.self,
        Stack.self,
        QueueTask.self,
        Reminder.self,
        configurations: config
    )

    let arc = Arc(title: "OEM Strategy", colorHex: "5E5CE6")
    let stack1 = Stack(title: "Unassigned Stack 1", status: .active, sortOrder: 0)
    let stack2 = Stack(title: "Unassigned Stack 2", stackDescription: "Some description", status: .active, sortOrder: 1)

    container.mainContext.insert(arc)
    container.mainContext.insert(stack1)
    container.mainContext.insert(stack2)

    return StackPickerForArcSheet(arc: arc)
        .modelContainer(container)
}

#Preview("Empty") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    // swiftlint:disable:next force_try
    let container = try! ModelContainer(
        for: Arc.self,
        Stack.self,
        QueueTask.self,
        Reminder.self,
        configurations: config
    )

    let arc = Arc(title: "OEM Strategy", colorHex: "5E5CE6")
    container.mainContext.insert(arc)

    return StackPickerForArcSheet(arc: arc)
        .modelContainer(container)
}
