//
//  CompletedArcsListView.swift
//  Dequeue
//
//  Displays list of completed arcs
//

import SwiftUI
import SwiftData

struct CompletedArcsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.syncManager) private var syncManager
    @Environment(\.authService) private var authService

    @Query private var arcs: [Arc]

    @State private var selectedArc: Arc?
    @State private var showStackPicker = false
    @State private var arcForStackPicker: Arc?
    @State private var cachedDeviceId: String = ""
    @State private var arcService: ArcService?

    init() {
        let completedRawValue = ArcStatus.completed.rawValue
        _arcs = Query(
            filter: #Predicate<Arc> { arc in
                arc.isDeleted == false &&
                arc.statusRawValue == completedRawValue
            },
            sort: \Arc.sortOrder
        )
    }

    var body: some View {
        Group {
            if arcs.isEmpty {
                emptyState
            } else {
                arcsList
            }
        }
        .sheet(item: $selectedArc) { arc in
            ArcEditorView(mode: .edit(arc))
        }
        .sheet(item: $arcForStackPicker) { arc in
            StackPickerForArcSheet(arc: arc)
        }
        .task {
            if cachedDeviceId.isEmpty {
                cachedDeviceId = await DeviceService.shared.getDeviceId()
            }
            if arcService == nil {
                arcService = ArcService(
                    modelContext: modelContext,
                    userId: authService.currentUserId,
                    deviceId: cachedDeviceId,
                    syncManager: syncManager
                )
            }
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        ContentUnavailableView(
            "No Completed Arcs",
            systemImage: "checkmark.circle",
            description: Text("Completed arcs will appear here")
        )
    }

    private var arcsList: some View {
        List {
            ForEach(arcs) { arc in
                ArcCardView(
                    arc: arc,
                    onTap: {
                        selectedArc = arc
                    },
                    onAddStackTap: {
                        arcForStackPicker = arc
                        showStackPicker = true
                    }
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            // Note: No reordering for completed arcs
        }
        .listStyle(.plain)
        .refreshable {
            await refreshArcs()
        }
    }

    // MARK: - Actions

    private func refreshArcs() async {
        // Just wait a moment for any pending sync operations
        try? await Task.sleep(for: .milliseconds(500))
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    // swiftlint:disable:next force_try
    let container = try! ModelContainer(
        for: Arc.self, Stack.self, configurations: config)

    let context = container.mainContext
    let arc1 = Arc(title: "Finished Project", status: .completed)
    let arc2 = Arc(title: "Delivered Initiative", status: .completed)
    context.insert(arc1)
    context.insert(arc2)

    return CompletedArcsListView()
        .modelContainer(container)
}
