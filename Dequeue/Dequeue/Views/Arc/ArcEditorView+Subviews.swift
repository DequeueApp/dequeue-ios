//
//  ArcEditorView+Subviews.swift
//  Dequeue
//
//  Arc editor subviews (color picker, stacks section, actions)
//

import SwiftUI
import os

private let logger = Logger(subsystem: "com.dequeue", category: "ArcEditorView+Subviews")

// MARK: - Subviews Extension

extension ArcEditorView {
    // MARK: - Color Picker

    var colorPicker: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
            ForEach(colorPresets, id: \.hex) { preset in
                Button {
                    selectedColorHex = preset.hex
                } label: {
                    Circle()
                        .fill(Color(hex: preset.hex) ?? .indigo)
                        .frame(width: 36, height: 36)
                        .overlay {
                            if selectedColorHex == preset.hex {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(preset.name)
                .accessibilityAddTraits(selectedColorHex == preset.hex ? .isSelected : [])
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Stacks Section

    @ViewBuilder
    func stacksSection(for arc: Arc) -> some View {
        Section {
            if arc.sortedStacks.isEmpty {
                Text("No stacks assigned")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(arc.sortedStacks) { stack in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(stack.title)
                                .font(.body)
                            if stack.status == .completed {
                                Text("Completed")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if stack.status == .completed {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            // Remove from arc button
                            Button {
                                removeStack(stack, from: arc)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Add stack button
            Button {
                showStackPicker = true
            } label: {
                Label("Add Stack", systemImage: "plus.circle")
            }
        } header: {
            HStack {
                Text("Stacks")
                Spacer()
                Text("\(arc.completedStackCount)/\(arc.totalStackCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showStackPicker) {
            StackPickerForArcSheet(arc: arc)
        }
    }

    func removeStack(_ stack: Stack, from arc: Arc) {
        Task {
            do {
                try await arcService?.removeStack(stack, from: arc)
                logger.info("Removed stack \(stack.id) from arc \(arc.id)")
            } catch {
                handleError(error, action: "remove_stack")
            }
        }
    }

    // MARK: - Actions Section

    @ViewBuilder
    func actionsSection(for arc: Arc) -> some View {
        Section {
            // Status actions
            switch arc.status {
            case .active:
                Button {
                    pauseArc()
                } label: {
                    Label("Pause Arc", systemImage: "pause.circle")
                }

                Button {
                    showCompleteConfirmation = true
                } label: {
                    Label("Complete Arc", systemImage: "checkmark.circle")
                }
                .foregroundStyle(.green)

            case .paused:
                Button {
                    resumeArc()
                } label: {
                    Label("Resume Arc", systemImage: "play.circle")
                }
                .foregroundStyle(.blue)

                Button {
                    showCompleteConfirmation = true
                } label: {
                    Label("Complete Arc", systemImage: "checkmark.circle")
                }
                .foregroundStyle(.green)

            case .completed:
                Button {
                    reopenArc()
                } label: {
                    Label("Reopen Arc", systemImage: "arrow.uturn.backward.circle")
                }
                .foregroundStyle(.blue)

            case .archived:
                Button {
                    unarchiveArc()
                } label: {
                    Label("Unarchive Arc", systemImage: "tray.and.arrow.up")
                }
                .foregroundStyle(.blue)
            }

            // Delete action
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete Arc", systemImage: "trash")
            }
        }
    }

    // MARK: - Event History Section

    @ViewBuilder
    func eventHistorySection(for arc: Arc) -> some View {
        Section {
            NavigationLink {
                ArcHistoryView(arc: arc)
            } label: {
                Label("Event History", systemImage: "clock.arrow.circlepath")
            }
        } footer: {
            Text("View the complete history of changes to this arc")
        }
    }
}
