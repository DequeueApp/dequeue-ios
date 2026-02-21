//
//  TaskTemplatesView.swift
//  Dequeue
//
//  UI for browsing, creating, and applying task templates.
//

import SwiftUI

// MARK: - Template Picker Sheet

/// A sheet that displays available templates for quick task creation.
struct TemplatePickerSheet: View {
    @StateObject private var templateService = TaskTemplateService()
    @Environment(\.dismiss) private var dismiss

    let onSelect: (TemplateApplicationResult) -> Void

    var body: some View {
        NavigationStack {
            List {
                if !builtInTemplates.isEmpty {
                    Section("Built-in") {
                        ForEach(builtInTemplates) { template in
                            templateRow(template)
                        }
                    }
                }

                if !customTemplates.isEmpty {
                    Section("Custom") {
                        ForEach(customTemplates) { template in
                            templateRow(template)
                        }
                        .onDelete { offsets in
                            let customOffset = builtInTemplates.count
                            let adjustedOffsets = IndexSet(offsets.map { $0 + customOffset })
                            templateService.delete(at: adjustedOffsets)
                        }
                    }
                }
            }
            .navigationTitle("Templates")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var builtInTemplates: [TaskTemplate] {
        templateService.templates.filter(\.isBuiltIn)
    }

    private var customTemplates: [TaskTemplate] {
        templateService.templates.filter { !$0.isBuiltIn }
    }

    private func templateRow(_ template: TaskTemplate) -> some View {
        Button {
            let result = templateService.apply(template)
            onSelect(result)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: template.icon)
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .frame(width: 32, height: 32)
                    .background(Color.blue.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name)
                        .font(.body)
                        .foregroundStyle(.primary)

                    if !template.title.isEmpty {
                        Text(template.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if let priority = template.priority {
                    priorityBadge(priority)
                }

                if !template.tags.isEmpty {
                    Text("\(template.tags.count) tags")
                        .font(.caption2)
                        .foregroundStyle(.purple)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
        }
        .accessibilityLabel("\(template.name) template")
        .accessibilityHint("Double tap to create task from this template")
    }

    private func priorityBadge(_ priority: Int) -> some View {
        Text(priorityLabel(priority))
            .font(.caption2)
            .foregroundStyle(priorityColor(priority))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(priorityColor(priority).opacity(0.1))
            .clipShape(Capsule())
    }

    private func priorityLabel(_ priority: Int) -> String {
        switch priority {
        case 3: return "Urgent"
        case 2: return "High"
        case 1: return "Medium"
        default: return "Low"
        }
    }

    private func priorityColor(_ priority: Int) -> Color {
        switch priority {
        case 3: return .red
        case 2: return .orange
        case 1: return .yellow
        default: return .gray
        }
    }
}

// MARK: - Template Editor

/// View for creating or editing a task template.
struct TemplateEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var icon: String
    @State private var title: String
    @State private var taskDescription: String
    @State private var priority: Int?
    @State private var tags: String
    @State private var hasDueDate: Bool
    @State private var dueDays: Int
    @State private var dueHours: Int
    @State private var hasStartDate: Bool
    @State private var startDays: Int

    private let isEditing: Bool
    private let templateId: String
    let onSave: (TaskTemplate) -> Void

    init(template: TaskTemplate? = nil, onSave: @escaping (TaskTemplate) -> Void) {
        let tmpl = template
        _name = State(initialValue: tmpl?.name ?? "")
        _icon = State(initialValue: tmpl?.icon ?? "doc.text")
        _title = State(initialValue: tmpl?.title ?? "")
        _taskDescription = State(initialValue: tmpl?.taskDescription ?? "")
        _priority = State(initialValue: tmpl?.priority)
        _tags = State(initialValue: tmpl?.tags.joined(separator: ", ") ?? "")
        _hasDueDate = State(initialValue: tmpl?.dueDateOffset != nil)
        _dueDays = State(initialValue: Int((tmpl?.dueDateOffset ?? 0) / 86400))
        _dueHours = State(initialValue: Int(((tmpl?.dueDateOffset ?? 0).truncatingRemainder(dividingBy: 86400)) / 3600))
        _hasStartDate = State(initialValue: tmpl?.startDateOffset != nil)
        _startDays = State(initialValue: Int((tmpl?.startDateOffset ?? 0) / 86400))
        self.isEditing = tmpl != nil
        self.templateId = tmpl?.id ?? UUID().uuidString
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Template Info") {
                    TextField("Template name", text: $name)
                        .accessibilityIdentifier("templateNameField")
                    iconPicker
                }

                Section("Task Fields") {
                    TextField("Task title", text: $title)
                        .accessibilityIdentifier("templateTitleField")
                    TextField("Description (optional)", text: $taskDescription, axis: .vertical)
                        .lineLimit(3...6)
                    priorityPicker
                    TextField("Tags (comma-separated)", text: $tags)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                }

                Section("Due Date") {
                    Toggle("Set relative due date", isOn: $hasDueDate)
                    if hasDueDate {
                        Stepper("Days: \(dueDays)", value: $dueDays, in: 0...365)
                        Stepper("Hours: \(dueHours)", value: $dueHours, in: 0...23)
                    }
                }

                Section("Start Date") {
                    Toggle("Set relative start date", isOn: $hasStartDate)
                    if hasStartDate {
                        Stepper("Days from now: \(startDays)", value: $startDays, in: 0...365)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Template" : "New Template")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveTemplate() }
                        .disabled(name.isEmpty || title.isEmpty)
                }
            }
        }
    }

    private var iconPicker: some View {
        let icons = [
            "doc.text", "bolt", "person.3", "eye", "ladybug",
            "calendar.badge.checkmark", "arrow.uturn.right", "star",
            "phone", "envelope", "cart", "house", "heart",
            "brain", "book", "wrench.and.screwdriver"
        ]

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(icons, id: \.self) { iconName in
                    Button {
                        icon = iconName
                    } label: {
                        Image(systemName: iconName)
                            .font(.title3)
                            .frame(width: 40, height: 40)
                            .background(icon == iconName ? Color.blue.opacity(0.2) : Color.secondary.opacity(0.1))
                            .foregroundStyle(icon == iconName ? .blue : .secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var priorityPicker: some View {
        Picker("Priority", selection: Binding(
            get: { priority ?? -1 },
            set: { priority = $0 == -1 ? nil : $0 }
        )) {
            Text("None").tag(-1)
            Text("Low").tag(0)
            Text("Medium").tag(1)
            Text("High").tag(2)
            Text("Urgent").tag(3)
        }
    }

    private func saveTemplate() {
        let parsedTags = tags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let dueDateOffset = hasDueDate
            ? TimeInterval(dueDays * 86400 + dueHours * 3600)
            : nil

        let startDateOffset = hasStartDate
            ? TimeInterval(startDays * 86400)
            : nil

        let template = TaskTemplate(
            id: templateId,
            name: name,
            icon: icon,
            title: title,
            taskDescription: taskDescription.isEmpty ? nil : taskDescription,
            priority: priority,
            tags: parsedTags,
            dueDateOffset: dueDateOffset,
            startDateOffset: startDateOffset
        )

        onSave(template)
        dismiss()
    }
}

// MARK: - Template Management View

/// Full template management view for settings.
struct TaskTemplateManagementView: View {
    @StateObject private var templateService = TaskTemplateService()
    @State private var showEditor = false
    @State private var editingTemplate: TaskTemplate?

    var body: some View {
        List {
            ForEach(templateService.templates) { template in
                Button {
                    editingTemplate = template
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: template.icon)
                            .font(.title3)
                            .foregroundStyle(.blue)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(template.name)
                                    .foregroundStyle(.primary)
                                if template.isBuiltIn {
                                    Text("Built-in")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.secondary.opacity(0.1))
                                        .clipShape(Capsule())
                                }
                            }
                            Text(template.title.isEmpty ? "Empty title" : template.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .onDelete { offsets in
                templateService.delete(at: offsets)
            }
            .onMove { source, destination in
                templateService.move(from: source, to: destination)
            }
        }
        .navigationTitle("Task Templates")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showEditor = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showEditor) {
            TemplateEditorView { template in
                templateService.add(template)
            }
        }
        .sheet(item: $editingTemplate) { template in
            TemplateEditorView(template: template) { updated in
                templateService.update(updated)
            }
        }
    }
}

// MARK: - Preview

#Preview("Template Picker") {
    TemplatePickerSheet { result in
        print("Selected: \(result.title)")
    }
}

#Preview("Template Editor") {
    TemplateEditorView { template in
        print("Saved: \(template.name)")
    }
}

#Preview("Template Management") {
    NavigationStack {
        TaskTemplateManagementView()
    }
}
