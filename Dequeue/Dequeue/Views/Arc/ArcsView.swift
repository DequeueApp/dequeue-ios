//
//  ArcsView.swift
//  Dequeue
//
//  Main view for displaying and managing Arcs with status filtering
//

import SwiftUI
import SwiftData

struct ArcsView: View {
    enum ArcFilter: String, CaseIterable {
        case inProgress = "In Progress"
        case paused = "Paused"
        case completed = "Completed"
    }

    @State private var selectedFilter: ArcFilter = .inProgress
    @State private var showAddSheet = false

    /// Maximum number of active arcs allowed
    private let maxActiveArcs = 5

    /// Active arcs count - fetch on demand for "Add" button state
    @Query(
        filter: #Predicate<Arc> { arc in
            arc.isDeleted == false &&
            arc.statusRawValue == ArcStatus.active.rawValue
        }
    ) private var activeArcs: [Arc]

    /// Whether user can create new arcs
    private var canCreateNewArc: Bool {
        activeArcs.count < maxActiveArcs
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segmented control for filtering
                Picker("Filter", selection: $selectedFilter) {
                    ForEach(ArcFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .accessibilityLabel("Arc filter")
                .accessibilityHint("Select to filter arcs by status")

                // Content based on selection
                switch selectedFilter {
                case .inProgress:
                    ActiveArcsListView()
                case .paused:
                    PausedArcsListView()
                case .completed:
                    CompletedArcsListView()
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
    }

    // MARK: - Subviews

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
