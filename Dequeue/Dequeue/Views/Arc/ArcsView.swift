//
//  ArcsView.swift
//  Dequeue
//
//  Main view for displaying and managing Arcs
//

import SwiftUI
import SwiftData

struct ArcsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.syncManager) private var syncManager
    @Environment(\.authService) private var authService

    @Query(
        filter: #Predicate<Arc> { !$0.isDeleted },
        sort: \Arc.sortOrder
    ) private var arcs: [Arc]

    @State private var showAddSheet = false
    @State private var selectedArc: Arc?
    @State private var showStackPicker = false
    @State private var arcForStackPicker: Arc?
    @State private var cachedDeviceId: String = ""
    @State private var arcService: ArcService?

    /// Maximum number of active arcs allowed
    private let maxActiveArcs = 5

    /// Active arcs count (not paused, not completed, not archived)
    private var activeArcsCount: Int {
        arcs.filter { $0.status == .active }.count
    }

    /// Whether user can create new arcs
    private var canCreateNewArc: Bool {
        activeArcsCount < maxActiveArcs
    }

    var body: some View {
        NavigationStack {
            Group {
                if arcs.isEmpty {
                    emptyState
                } else {
                    arcsList
                }
            }
            .navigationTitle("Arcs")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    addButton
                }
            }
        }
        .sheet(isPresented: $showAddSheet) {
            ArcEditorView(mode: .create)
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
        ContentUnavailableView {
            Label("No Arcs", systemImage: "rays")
        } description: {
            Text("""
                Arcs help you organize related stacks into higher-level goals.
                Create your first arc to get started.
                """)
        } actions: {
            Button {
                showAddSheet = true
            } label: {
                Label("Create Arc", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
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
            // Trigger sync refresh
            await refreshArcs()
        }
    }

    @ViewBuilder
    private var addButton: some View {
        Button {
            showAddSheet = true
        } label: {
            Label("Add Arc", systemImage: "plus")
        }
        .disabled(!canCreateNewArc)
        #if os(macOS)
        .keyboardShortcut("n", modifiers: .command)
        #endif
        .accessibilityLabel(canCreateNewArc ? "Add new arc" : "Maximum arcs reached")
        .accessibilityHint(canCreateNewArc
            ? "Creates a new arc"
            : "You can have up to \(maxActiveArcs) active arcs")
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

// MARK: - Previews

#Preview("With Arcs") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    // Safe: In-memory container with known schema types cannot fail in preview context
    // swiftlint:disable:next force_try
    let container = try! ModelContainer(
        for: Arc.self, Stack.self, QueueTask.self, Reminder.self, configurations: config)

    // Create sample arcs
    let context = container.mainContext
    let arc1 = Arc(title: "OEM Strategy", arcDescription: "Prepare for tech conference")
    let arc2 = Arc(title: "Product Launch", arcDescription: "Q1 launch preparation", status: .paused)
    let arc3 = Arc(title: "Documentation", status: .completed)
    context.insert(arc1)
    context.insert(arc2)
    context.insert(arc3)

    return ArcsView()
        .modelContainer(container)
}

#Preview("Empty State") {
    ArcsView()
        .modelContainer(for: [Arc.self, Stack.self], inMemory: true)
}
