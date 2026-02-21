//
//  TaskDependencyView.swift
//  Dequeue
//
//  UI for viewing and managing task dependencies
//

import SwiftUI
import SwiftData

// MARK: - Dependencies Section (for TaskDetailView)

struct TaskDependenciesSection: View {
    let task: QueueTask
    @Environment(\.modelContext) private var modelContext
    @Environment(\.syncManager) private var syncManager
    @Environment(\.authService) private var authService
    @State private var showAddDependency = false
    @State private var dependencyTasks: [QueueTask] = []
    @State private var dependentTasks: [QueueTask] = []
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        Section("Dependencies") {
            // Tasks this task depends on
            if dependencyTasks.isEmpty && dependentTasks.isEmpty {
                HStack {
                    Label("No dependencies", systemImage: "arrow.triangle.branch")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        showAddDependency = true
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                }
            } else {
                if !dependencyTasks.isEmpty {
                    ForEach(dependencyTasks) { dep in
                        DependencyRow(
                            task: dep,
                            relationship: .blockedBy,
                            onRemove: {
                                removeDependency(dep.id)
                            }
                        )
                    }
                }

                if !dependentTasks.isEmpty {
                    ForEach(dependentTasks) { dep in
                        DependencyRow(
                            task: dep,
                            relationship: .blocks
                        )
                    }
                }

                Button {
                    showAddDependency = true
                } label: {
                    Label("Add Dependency", systemImage: "plus")
                }
            }
        }
        .task {
            await loadDependencies()
        }
        .sheet(isPresented: $showAddDependency) {
            DependencyPickerSheet(task: task, onAdded: {
                Task { await loadDependencies() }
            })
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }

    private func loadDependencies() async {
        let deviceId = await DeviceService.shared.getDeviceId()
        let userId = authService.currentUserId ?? ""
        let service = TaskDependencyService(
            modelContext: modelContext,
            userId: userId,
            deviceId: deviceId,
            syncManager: syncManager
        )
        dependencyTasks = (try? service.getDependencyTasks(for: task)) ?? []
        dependentTasks = (try? service.getDependentTasks(for: task)) ?? []
    }

    private func removeDependency(_ depId: String) {
        Task {
            let deviceId = await DeviceService.shared.getDeviceId()
            let userId = authService.currentUserId ?? ""
            let service = TaskDependencyService(
                modelContext: modelContext,
                userId: userId,
                deviceId: deviceId,
                syncManager: syncManager
            )
            do {
                try await service.removeDependency(task: task, blockerTaskId: depId)
                await loadDependencies()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

// MARK: - Dependency Row

enum DependencyRelationship {
    case blockedBy
    case blocks

    var label: String {
        switch self {
        case .blockedBy: return "Blocked by"
        case .blocks: return "Blocks"
        }
    }

    var icon: String {
        switch self {
        case .blockedBy: return "exclamationmark.triangle"
        case .blocks: return "arrow.right"
        }
    }

    var color: Color {
        switch self {
        case .blockedBy: return .orange
        case .blocks: return .blue
        }
    }
}

struct DependencyRow: View {
    let task: QueueTask
    let relationship: DependencyRelationship
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: relationship.icon)
                .font(.caption)
                .foregroundStyle(relationship.color)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(relationship.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(task.title)
                    .font(.subheadline)
                    .lineLimit(1)
            }

            Spacer()

            // Status badge
            statusBadge

            if let onRemove {
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch task.status {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .blocked:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
                .font(.caption)
        case .closed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }
}

// MARK: - Dependency Picker Sheet

struct DependencyPickerSheet: View {
    let task: QueueTask
    let onAdded: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.syncManager) private var syncManager
    @Environment(\.authService) private var authService

    @State private var searchText = ""
    @State private var showError = false
    @State private var errorMessage = ""

    @Query(
        filter: #Predicate<QueueTask> { task in
            !task.isDeleted
        },
        sort: [SortDescriptor(\QueueTask.updatedAt, order: .reverse)]
    )
    private var allTasks: [QueueTask]

    private var filteredTasks: [QueueTask] {
        let available = allTasks.filter { $0.id != task.id && $0.status != .closed && !task.dependencyIds.contains($0.id) }
        if searchText.isEmpty { return Array(available.prefix(20)) }
        return available.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if filteredTasks.isEmpty {
                    ContentUnavailableView {
                        Label("No Tasks", systemImage: "magnifyingglass")
                    } description: {
                        Text("No matching tasks found to add as dependency")
                    }
                } else {
                    ForEach(filteredTasks) { candidate in
                        Button {
                            addDependency(candidate)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(candidate.title)
                                        .foregroundStyle(.primary)
                                    if let stack = candidate.stack {
                                        Text(stack.title)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                statusIcon(for: candidate)
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search tasks...")
            .navigationTitle("Add Dependency")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
        }
    }

    @ViewBuilder
    private func statusIcon(for candidate: QueueTask) -> some View {
        switch candidate.status {
        case .completed:
            Label("Completed", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .pending:
            Label("Pending", systemImage: "circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .blocked:
            Label("Blocked", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        case .closed:
            EmptyView()
        }
    }

    private func addDependency(_ blocker: QueueTask) {
        Task {
            let deviceId = await DeviceService.shared.getDeviceId()
            let userId = authService.currentUserId ?? ""
            let service = TaskDependencyService(
                modelContext: modelContext,
                userId: userId,
                deviceId: deviceId,
                syncManager: syncManager
            )
            do {
                let success = try await service.addDependency(task: task, blockedBy: blocker)
                if success {
                    onAdded()
                    dismiss()
                } else {
                    errorMessage = "Cannot add this dependency — it would create a circular dependency chain."
                    showError = true
                }
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

// MARK: - Dependency Badge (for task rows)

struct DependencyBadge: View {
    let count: Int

    var body: some View {
        Label {
            Text("\(count)")
                .font(.caption2)
                .fontWeight(.medium)
        } icon: {
            Image(systemName: "arrow.triangle.branch")
                .font(.caption2)
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.orange.opacity(0.1))
        .clipShape(Capsule())
        .accessibilityLabel("\(count) dependenc\(count == 1 ? "y" : "ies")")
    }
}
