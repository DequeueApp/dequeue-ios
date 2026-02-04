//
//  PausedArcsListView.swift
//  Dequeue
//
//  Displays list of paused arcs
//

import SwiftUI
import SwiftData

struct PausedArcsListView: View {
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
        let pausedRawValue = ArcStatus.paused.rawValue
        _arcs = Query(
            filter: #Predicate<Arc> { arc in
                arc.isDeleted == false &&
                arc.statusRawValue == pausedRawValue
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
            "No Paused Arcs",
            systemImage: "pause.circle",
            description: Text("Paused arcs will appear here")
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
            .onMove(perform: moveArcs)
        }
        .listStyle(.plain)
        .refreshable {
            await refreshArcs()
        }
    }

    // MARK: - Actions

    private func moveArcs(from source: IndexSet, to destination: Int) {
        var reorderedArcs = arcs
        reorderedArcs.move(fromOffsets: source, toOffset: destination)

        Task {
            do {
                try await arcService?.updateSortOrders(reorderedArcs)
            } catch {
                ErrorReportingService.capture(error: error, context: ["action": "move_arcs"])
            }
        }
    }

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
    let arc1 = Arc(title: "On Hold Project", status: .paused)
    let arc2 = Arc(title: "Deferred Initiative", status: .paused)
    context.insert(arc1)
    context.insert(arc2)

    return PausedArcsListView()
        .modelContainer(container)
}
