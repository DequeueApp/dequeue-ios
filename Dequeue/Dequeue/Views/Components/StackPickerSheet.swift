//
//  StackPickerSheet.swift
//  Dequeue
//
//  Sheet for selecting which stack to set as active
//

import SwiftUI
import SwiftData

struct StackPickerSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.syncManager) private var syncManager
    @Environment(\.authService) private var authService
    @Environment(\.dismiss) private var dismiss
    @Query private var stacks: [Stack]

    @State private var stackService: StackService?
    @State private var errorMessage: String?
    @State private var showError = false

    init() {
        // Query for stacks that can be set as active:
        // - Not deleted
        // - Not a draft
        // - Has active status (not completed or closed)
        let activeRawValue = StackStatus.active.rawValue
        _stacks = Query(
            filter: #Predicate<Stack> { stack in
                stack.isDeleted == false &&
                stack.isDraft == false &&
                stack.statusRawValue == activeRawValue
            },
            sort: \Stack.updatedAt,
            order: .reverse
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
            .navigationTitle("Select Active Stack")
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
                Button("OK", role: .cancel) { }
            } message: {
                if let errorMessage {
                    Text(errorMessage)
                }
            }
            .task {
                guard stackService == nil else { return }
                let deviceId = await DeviceService.shared.getDeviceId()
                stackService = StackService(
                    modelContext: modelContext,
                    userId: authService.currentUserId ?? "",
                    deviceId: deviceId,
                    syncManager: syncManager
                )
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #else
        .frame(minWidth: 400, minHeight: 300)
        #endif
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView(
            "No Stacks Available",
            systemImage: "tray",
            description: Text("Create a stack to get started")
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

                            if let activeTask = stack.activeTask {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.right.circle.fill")
                                        .font(.caption2)
                                    Text(activeTask.title)
                                        .font(.caption)
                                        .lineLimit(1)
                                }
                                .foregroundStyle(.blue)
                            }
                        }

                        Spacer()

                        if stack.isActive {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
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
        guard let service = stackService else {
            errorMessage = "Initializing... please try again"
            showError = true
            return
        }

        Task {
            do {
                try await service.setAsActive(stack)
                // Note: syncManager?.triggerImmediatePush() is called internally by setAsActive()
                dismiss()
            } catch {
                errorMessage = "Failed to set stack as active: \(error.localizedDescription)"
                showError = true
            }
        }
    }
}

#Preview("With Stacks") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    // swiftlint:disable:next force_try multiline_arguments
    let container = try! ModelContainer(
        for: Stack.self,
        QueueTask.self,
        Reminder.self,
        configurations: config
    )

    let stack1 = Stack(
        title: "Work Tasks",
        stackDescription: "Important work items",
        status: .active,
        sortOrder: 0,
        isActive: false
    )
    let stack2 = Stack(
        title: "Personal",
        stackDescription: nil,
        status: .active,
        sortOrder: 1,
        isActive: false
    )
    container.mainContext.insert(stack1)
    container.mainContext.insert(stack2)

    return StackPickerSheet()
        .modelContainer(container)
}

#Preview("Empty") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    // swiftlint:disable:next force_try multiline_arguments
    let container = try! ModelContainer(
        for: Stack.self,
        QueueTask.self,
        Reminder.self,
        configurations: config
    )

    return StackPickerSheet()
        .modelContainer(container)
}
