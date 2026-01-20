//
//  ArcPickerSheet.swift
//  Dequeue
//
//  Sheet for selecting which arc to assign a stack to
//

import SwiftUI
import SwiftData

struct ArcPickerSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.syncManager) private var syncManager
    @Environment(\.authService) private var authService
    @Environment(\.dismiss) private var dismiss

    @Query private var arcs: [Arc]

    /// The stack to assign to an arc
    let stack: Stack

    /// Callback when an arc is selected or removed
    var onArcSelected: ((Arc?) -> Void)?

    @State private var arcService: ArcService?
    @State private var errorMessage: String?
    @State private var showError = false

    init(stack: Stack, onArcSelected: ((Arc?) -> Void)? = nil) {
        self.stack = stack
        self.onArcSelected = onArcSelected

        // Query for arcs that can have stacks assigned:
        // - Not deleted
        // - Active or paused (not completed or archived)
        let activeRawValue = ArcStatus.active.rawValue
        let pausedRawValue = ArcStatus.paused.rawValue
        _arcs = Query(
            filter: #Predicate<Arc> { arc in
                arc.isDeleted == false &&
                (arc.statusRawValue == activeRawValue || arc.statusRawValue == pausedRawValue)
            },
            sort: \Arc.sortOrder
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if arcs.isEmpty {
                    emptyState
                } else {
                    arcList
                }
            }
            .navigationTitle("Assign to Arc")
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
            "No Arcs Available",
            systemImage: "rays",
            description: Text("Create an arc first to organize your stacks")
        )
    }

    // MARK: - Arc List

    private var arcList: some View {
        List {
            // Option to remove from arc
            if stack.arc != nil {
                Button {
                    removeFromArc()
                } label: {
                    HStack {
                        Label("No Arc", systemImage: "minus.circle")
                            .foregroundStyle(.secondary)

                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            // Available arcs
            ForEach(arcs) { arc in
                Button {
                    selectArc(arc)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                // Color indicator
                                Circle()
                                    .fill(arcColor(for: arc))
                                    .frame(width: 12, height: 12)

                                Text(arc.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                            }

                            if let description = arc.arcDescription, !description.isEmpty {
                                Text(description)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            // Stack count
                            Text("\(arc.totalStackCount) stack\(arc.totalStackCount == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()

                        // Check if this arc is currently selected
                        if stack.arc?.id == arc.id {
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

    // MARK: - Helpers

    private func arcColor(for arc: Arc) -> Color {
        if let hex = arc.colorHex {
            return Color(hex: hex) ?? .indigo
        }
        return .indigo
    }

    // MARK: - Actions

    private func selectArc(_ arc: Arc) {
        guard let service = arcService else {
            errorMessage = "Initializing... please try again"
            showError = true
            return
        }

        // If already assigned to this arc, just dismiss
        if stack.arc?.id == arc.id {
            dismiss()
            return
        }

        do {
            try service.assignStack(stack, to: arc)
            onArcSelected?(arc)
            dismiss()
        } catch {
            errorMessage = "Failed to assign stack to arc: \(error.localizedDescription)"
            showError = true
        }
    }

    private func removeFromArc() {
        guard let service = arcService,
              let currentArc = stack.arc else {
            return
        }

        do {
            try service.removeStack(stack, from: currentArc)
            onArcSelected?(nil)
            dismiss()
        } catch {
            errorMessage = "Failed to remove stack from arc: \(error.localizedDescription)"
            showError = true
        }
    }
}

// MARK: - Previews

#Preview("With Arcs") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    // swiftlint:disable:next force_try
    let container = try! ModelContainer(
        for: Arc.self,
        Stack.self,
        QueueTask.self,
        Reminder.self,
        configurations: config
    )

    let arc1 = Arc(title: "OEM Strategy", arcDescription: "Conference preparation", colorHex: "5E5CE6")
    let arc2 = Arc(title: "Product Launch", colorHex: "FF6B6B")
    let stack = Stack(title: "Demo Prep", status: .active, sortOrder: 0)

    container.mainContext.insert(arc1)
    container.mainContext.insert(arc2)
    container.mainContext.insert(stack)

    return ArcPickerSheet(stack: stack)
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

    let stack = Stack(title: "Some Stack", status: .active, sortOrder: 0)
    container.mainContext.insert(stack)

    return ArcPickerSheet(stack: stack)
        .modelContainer(container)
}
