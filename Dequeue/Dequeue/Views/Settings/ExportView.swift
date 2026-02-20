//
//  ExportView.swift
//  Dequeue
//
//  Data export and backup view
//

import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.dequeue", category: "ExportView")

struct ExportView: View {
    @Environment(\.exportService) private var exportService
    @State private var isExporting = false
    @State private var exportComplete = false
    @State private var exportedFileURL: URL?
    @State private var exportSummary: ExportSummary?
    @State private var errorMessage: String?
    @State private var showShareSheet = false

    var body: some View {
        List {
            infoSection
            exportSection
            if let summary = exportSummary {
                summarySection(summary)
            }
        }
        .navigationTitle("Export Data")
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedFileURL {
                ShareSheet(items: [url])
            }
        }
    }

    // MARK: - Info Section

    private var infoSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Label("Data Export", systemImage: "square.and.arrow.up")
                    .font(.headline)
                Text("Export all your data as a JSON file. This includes arcs, stacks, tasks, tags, and reminders.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Your data stays yours. Export anytime for backup or portability.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Export Section

    private var exportSection: some View {
        Section {
            Button {
                Task { await performExport() }
            } label: {
                HStack {
                    Label("Export to JSON", systemImage: "doc.text")
                    Spacer()
                    if isExporting {
                        ProgressView()
                    } else if exportComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            .disabled(isExporting)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if exportComplete, exportedFileURL != nil {
                Button {
                    showShareSheet = true
                } label: {
                    Label("Share Export File", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    // MARK: - Summary Section

    private func summarySection(_ summary: ExportSummary) -> some View {
        Section("Export Summary") {
            LabeledContent("Arcs", value: "\(summary.arcCount)")
            LabeledContent("Stacks", value: "\(summary.stackCount)")
            LabeledContent("Tasks", value: "\(summary.taskCount)")
            LabeledContent("Tags", value: "\(summary.tagCount)")
            LabeledContent("Reminders", value: "\(summary.reminderCount)")
            LabeledContent("Total Items", value: "\(summary.totalItems)")
            LabeledContent("Exported At", value: summary.exportedAt.formatted())
        }
    }

    // MARK: - Export Logic

    @MainActor
    private func performExport() async {
        guard let exportService else {
            errorMessage = "Export is not available."
            return
        }

        isExporting = true
        errorMessage = nil
        exportComplete = false
        exportedFileURL = nil
        exportSummary = nil

        do {
            let fileURL = try await exportService.exportToFile()
            // Also get the response for summary
            let export = try await exportService.exportData()

            exportedFileURL = fileURL
            exportSummary = ExportSummary(
                arcCount: export.arcs.count,
                stackCount: export.stacks.count,
                taskCount: export.tasks.count,
                tagCount: export.tags.count,
                reminderCount: export.reminders.count,
                totalItems: export.totalItems,
                exportedAt: export.exportedAtDate
            )
            exportComplete = true
            logger.info("Export completed: \(export.totalItems) items → \(fileURL.lastPathComponent)")
        } catch {
            logger.error("Export failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }

        isExporting = false
    }
}

// MARK: - Export Summary

struct ExportSummary {
    let arcCount: Int
    let stackCount: Int
    let taskCount: Int
    let tagCount: Int
    let reminderCount: Int
    let totalItems: Int
    let exportedAt: Date
}

// MARK: - Share Sheet

#if os(iOS)
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#elseif os(macOS)
struct ShareSheet: View {
    let items: [Any]

    var body: some View {
        VStack(spacing: 16) {
            Text("Export Complete")
                .font(.headline)

            if let url = items.first as? URL {
                Text(url.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Reveal in Finder") {
                    NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(minWidth: 300)
    }
}
#endif

#Preview {
    NavigationStack {
        ExportView()
    }
}
