//
//  TagDetailView.swift
//  Dequeue
//
//  Detail view for viewing and managing a single tag
//

import SwiftUI
import SwiftData

/// Detail view for viewing and editing a single tag.
///
/// Features:
/// - Shows list of Stacks using this tag
/// - Edit mode for renaming tag
/// - Delete tag with confirmation
/// - Navigation to Stack detail
struct TagDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.authService) private var authService
    @Environment(\.syncManager) private var syncManager
    @Environment(\.dismiss) private var dismiss

    let tag: Tag

    @State private var isEditing = false
    @State private var editedName: String = ""
    @State private var showDeleteConfirmation = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var tagService: TagService?

    /// Stacks that have this tag (active only)
    private var stacksWithTag: [Stack] {
        tag.stacks.filter { !$0.isDeleted && $0.status == .active }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        List {
            // Header section with count
            Section {
                HStack {
                    TagChip(tag: tag, showRemoveButton: false)
                    Spacer()
                }
            } header: {
                Text("\(stacksWithTag.count) \(stacksWithTag.count == 1 ? "Stack" : "Stacks")")
            }

            // Stacks list
            if !stacksWithTag.isEmpty {
                Section("Stacks Using This Tag") {
                    ForEach(stacksWithTag) { stack in
                        NavigationLink(value: stack) {
                            Text(stack.title)
                        }
                    }
                }
            }

            // Delete section
            Section {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Delete Tag")
                    }
                }
            } footer: {
                Text("Deleting this tag won't delete the Stacks using it.")
            }
        }
        .navigationTitle(isEditing ? "Edit Tag" : tag.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if isEditing {
                    Button("Done") {
                        saveChanges()
                    }
                    .disabled(editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    Button("Edit") {
                        editedName = tag.name
                        isEditing = true
                    }
                }
            }

            if isEditing {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isEditing = false
                    }
                }
            }
        }
        .alert("Delete '\(tag.name)'?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteTag()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This won't delete the Stacks using this tag.")
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            if let errorMessage {
                Text(errorMessage)
            }
        }
        .sheet(isPresented: $isEditing) {
            editSheet
        }
        .navigationDestination(for: Stack.self) { stack in
            StackEditorView(mode: .edit(stack))
        }
        .task {
            guard tagService == nil else { return }
            let deviceId = await DeviceService.shared.getDeviceId()
            tagService = TagService(
                modelContext: modelContext,
                userId: authService.currentUserId ?? "",
                deviceId: deviceId,
                syncManager: syncManager
            )
        }
    }

    // MARK: - Edit Sheet

    private var editSheet: some View {
        NavigationStack {
            Form {
                Section("Tag Name") {
                    TextField("Name", text: $editedName)
                        #if os(iOS)
                        .textInputAutocapitalization(.words)
                        #endif
                }
            }
            .navigationTitle("Edit Tag")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isEditing = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Actions

    private func saveChanges() {
        guard let service = tagService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }
        Task {
            do {
                try await service.updateTag(tag, name: editedName)
                isEditing = false
            } catch {
                errorMessage = error.localizedDescription
                showError = true
                ErrorReportingService.capture(error: error, context: ["action": "rename_tag"])
            }
        }
    }

    private func deleteTag() {
        guard let service = tagService else {
            errorMessage = "Initializing... please try again."
            showError = true
            return
        }
        Task {
            do {
                try await service.deleteTag(tag)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
                ErrorReportingService.capture(error: error, context: ["action": "delete_tag"])
            }
        }
    }
}

// MARK: - Previews

#Preview("Tag with Stacks") {
    @Previewable @State var previewData: (container: ModelContainer, tag: Tag)? = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        guard let container = try? ModelContainer(for: Tag.self, Stack.self, configurations: config) else {
            return nil
        }
        let workTag = Tag(name: "Work", colorHex: "#007AFF")
        container.mainContext.insert(workTag)
        let stack1 = Stack(title: "Quarterly Report", stackDescription: nil, status: .active, sortOrder: 0)
        let stack2 = Stack(title: "Client Proposal", stackDescription: nil, status: .active, sortOrder: 1)
        stack1.tagObjects.append(workTag)
        stack2.tagObjects.append(workTag)
        container.mainContext.insert(stack1)
        container.mainContext.insert(stack2)
        return (container, workTag)
    }()

    if let previewData {
        NavigationStack {
            TagDetailView(tag: previewData.tag)
        }
        .modelContainer(previewData.container)
    } else {
        Text("Failed to create preview")
    }
}

#Preview("Tag without Stacks") {
    @Previewable @State var previewData: (container: ModelContainer, tag: Tag)? = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        guard let container = try? ModelContainer(for: Tag.self, Stack.self, configurations: config) else {
            return nil
        }
        let emptyTag = Tag(name: "Personal", colorHex: "#FF9500")
        container.mainContext.insert(emptyTag)
        return (container, emptyTag)
    }()

    if let previewData {
        NavigationStack {
            TagDetailView(tag: previewData.tag)
        }
        .modelContainer(previewData.container)
    } else {
        Text("Failed to create preview")
    }
}
