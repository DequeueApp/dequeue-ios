//
//  TaskFilterView.swift
//  Dequeue
//
//  Comprehensive filter sheet for tasks with preset support.
//

import SwiftUI
import SwiftData

// MARK: - Filter Bar

/// Compact filter bar showing active filter count + sort indicator
struct TaskFilterBar: View {
    @Binding var filter: TaskFilter
    @Binding var showFilterSheet: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Filter button
            Button {
                showFilterSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    Text("Filter")
                    if filter.isActive {
                        Text("\(filter.activeFilterCount)")
                            .font(.caption2.bold())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.blue, in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
                .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .tint(filter.isActive ? .blue : .secondary)

            // Sort indicator
            Menu {
                ForEach(TaskSortOption.allCases) { option in
                    Button {
                        if filter.sortBy == option {
                            filter.sortAscending.toggle()
                        } else {
                            filter.sortBy = option
                            filter.sortAscending = true
                        }
                    } label: {
                        HStack {
                            Label(option.displayName, systemImage: option.icon)
                            if filter.sortBy == option {
                                Image(systemName: filter.sortAscending ? "chevron.up" : "chevron.down")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: filter.sortBy.icon)
                    Image(systemName: filter.sortAscending ? "chevron.up" : "chevron.down")
                }
                .font(.subheadline)
            }
            .buttonStyle(.bordered)

            Spacer()

            // Clear button
            if filter.isActive {
                Button("Clear") {
                    withAnimation {
                        filter.reset()
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.red)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

// MARK: - Filter Sheet

struct TaskFilterSheet: View {
    @Binding var filter: TaskFilter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<Tag> { !$0.isDeleted }, sort: \.name)
    private var allTags: [Tag]

    @Query(filter: #Predicate<Stack> { !$0.isDeleted }, sort: \.title)
    private var allStacks: [Stack]

    @State private var savedPresets: [FilterPreset] = []
    @State private var showSavePresetAlert = false
    @State private var presetName = ""

    var body: some View {
        NavigationStack {
            Form {
                // Quick Presets
                presetsSection

                // Status
                statusSection

                // Priority
                prioritySection

                // Date Range
                dateRangeSection

                // Tags
                if !allTags.isEmpty {
                    tagsSection
                }

                // Stacks
                if !allStacks.isEmpty {
                    stacksSection
                }

                // Additional Options
                additionalSection
            }
            .navigationTitle("Filter Tasks")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        withAnimation { filter.reset() }
                    }
                    .foregroundStyle(.red)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                loadPresets()
            }
            .alert("Save Filter Preset", isPresented: $showSavePresetAlert) {
                TextField("Preset name", text: $presetName)
                Button("Save") {
                    if !presetName.isEmpty {
                        let service = TaskFilterService(modelContext: modelContext)
                        let preset = service.addPreset(name: presetName, filter: filter)
                        savedPresets.append(preset)
                        presetName = ""
                    }
                }
                Button("Cancel", role: .cancel) { }
            }
        }
    }

    // MARK: - Presets

    @ViewBuilder
    private var presetsSection: some View {
        Section("Quick Filters") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FilterPreset.builtInPresets) { preset in
                        PresetChip(preset: preset, isSelected: false) {
                            withAnimation { filter = preset.filter }
                        }
                    }

                    ForEach(savedPresets) { preset in
                        PresetChip(preset: preset, isSelected: false) {
                            withAnimation { filter = preset.filter }
                        }
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                let service = TaskFilterService(modelContext: modelContext)
                                service.removePreset(id: preset.id)
                                savedPresets.removeAll { $0.id == preset.id }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Button {
                showSavePresetAlert = true
            } label: {
                Label("Save Current Filter", systemImage: "plus.circle")
            }
            .disabled(!filter.isActive)
        }
    }

    // MARK: - Status

    @ViewBuilder
    private var statusSection: some View {
        Section("Status") {
            Picker("Status", selection: $filter.statusFilter) {
                ForEach(StatusFilter.allCases) { status in
                    Text(status.displayName).tag(status)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Priority

    @ViewBuilder
    private var prioritySection: some View {
        Section("Priority") {
            Picker("Priority", selection: $filter.priorityFilter) {
                ForEach(PriorityFilter.allCases) { priority in
                    Text(priority.displayName).tag(priority)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Date Range

    @ViewBuilder
    private var dateRangeSection: some View {
        Section("Due Date") {
            ForEach(DateRangeFilter.allCases) { range in
                Button {
                    filter.dateRangeFilter = range
                } label: {
                    HStack {
                        Label(range.displayName, systemImage: range.icon)
                            .foregroundStyle(.primary)
                        Spacer()
                        if filter.dateRangeFilter == range {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }

            if filter.dateRangeFilter == .custom {
                DatePicker("From", selection: Binding(
                    get: { filter.customStartDate ?? Date() },
                    set: { filter.customStartDate = $0 }
                ), displayedComponents: .date)

                DatePicker("To", selection: Binding(
                    get: { filter.customEndDate ?? Date() },
                    set: { filter.customEndDate = $0 }
                ), displayedComponents: .date)
            }
        }
    }

    // MARK: - Tags

    @ViewBuilder
    private var tagsSection: some View {
        Section("Tags") {
            ForEach(allTags) { tag in
                Button {
                    if filter.selectedTagIds.contains(tag.id) {
                        filter.selectedTagIds.remove(tag.id)
                    } else {
                        filter.selectedTagIds.insert(tag.id)
                    }
                } label: {
                    HStack {
                        Text(tag.name)
                            .foregroundStyle(.primary)
                        Spacer()
                        if filter.selectedTagIds.contains(tag.id) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Stacks

    @ViewBuilder
    private var stacksSection: some View {
        Section("Stacks") {
            ForEach(allStacks) { stack in
                Button {
                    if filter.selectedStackIds.contains(stack.id) {
                        filter.selectedStackIds.remove(stack.id)
                    } else {
                        filter.selectedStackIds.insert(stack.id)
                    }
                } label: {
                    HStack {
                        Text(stack.title)
                            .foregroundStyle(.primary)
                        Spacer()
                        if filter.selectedStackIds.contains(stack.id) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Additional

    @ViewBuilder
    private var additionalSection: some View {
        Section("Additional") {
            Toggle("Only tasks with due dates", isOn: $filter.showOnlyWithDueDate)
        }
    }

    // MARK: - Helpers

    private func loadPresets() {
        let service = TaskFilterService(modelContext: modelContext)
        savedPresets = service.loadPresets()
    }
}

// MARK: - Preset Chip

private struct PresetChip: View {
    let preset: FilterPreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: preset.icon)
                    .font(.caption)
                Text(preset.name)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isSelected ? Color.blue : Color.secondary.opacity(0.15),
                in: Capsule()
            )
            .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    @Previewable @State var filter = TaskFilter.default
    TaskFilterSheet(filter: $filter)
        .modelContainer(for: [QueueTask.self, Stack.self, Tag.self])
}
