//
//  AttachmentSettingsView.swift
//  Dequeue
//
//  Settings view for attachment download and storage preferences
//

import SwiftUI
import SwiftData

struct AttachmentSettingsView: View {
    @Environment(\.attachmentSettings) private var settings
    @Environment(\.modelContext) private var modelContext
    @State private var storageUsed: Int64 = 0
    @State private var attachmentCount: Int = 0
    @State private var isCalculating = false

    var body: some View {
        List {
            Section {
                Picker("Download Behavior", selection: Binding(
                    get: { settings.downloadBehavior },
                    set: { settings.downloadBehavior = $0 }
                )) {
                    ForEach(AttachmentDownloadBehavior.allCases, id: \.self) { behavior in
                        Text(behavior.displayName)
                            .tag(behavior)
                    }
                }

                if settings.downloadBehavior != .onDemand {
                    Text(settings.downloadBehavior.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Download")
            }

            Section {
                Picker("Storage Quota", selection: Binding(
                    get: { settings.storageQuota },
                    set: { settings.storageQuota = $0 }
                )) {
                    ForEach(AttachmentStorageQuota.allCases, id: \.self) { quota in
                        Text(quota.displayName)
                            .tag(quota)
                    }
                }

                StorageUsageRow(
                    used: storageUsed,
                    quota: settings.storageQuota,
                    attachmentCount: attachmentCount,
                    isCalculating: isCalculating
                )
            } header: {
                Text("Storage")
            } footer: {
                if settings.storageQuota != .unlimited {
                    // swiftlint:disable:next line_length
                    Text("When the storage quota is reached, older cached files will be removed to make room for new downloads.")
                }
            }

            Section {
                Button("Clear Downloaded Files") {
                    clearDownloadedFiles()
                }
                .foregroundStyle(.red)
                .disabled(storageUsed == 0 || isCalculating)
            } footer: {
                // swiftlint:disable:next line_length
                Text("This will remove all locally cached attachment files. Files will be re-downloaded when you view them.")
            }
        }
        .navigationTitle("Attachments")
        .task {
            await calculateStorageUsage()
        }
    }

    private func calculateStorageUsage() async {
        isCalculating = true
        defer { isCalculating = false }

        // Calculate from Attachments directory
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }

        let attachmentsURL = documentsURL.appendingPathComponent("Attachments")

        // Collect URLs synchronously to avoid Swift 6 concurrency issues with enumerator
        let urls: [URL]
        if let enumerator = fileManager.enumerator(
            at: attachmentsURL,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            urls = enumerator.compactMap { $0 as? URL }
        } else {
            urls = []
        }

        var totalSize: Int64 = 0
        var fileCount = 0

        for fileURL in urls {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  resourceValues.isRegularFile == true else {
                continue
            }

            if let fileSize = resourceValues.fileSize {
                totalSize += Int64(fileSize)
                fileCount += 1
            }
        }

        await MainActor.run {
            self.storageUsed = totalSize
            self.attachmentCount = fileCount
        }
    }

    private func clearDownloadedFiles() {
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }

        let attachmentsURL = documentsURL.appendingPathComponent("Attachments")

        do {
            if fileManager.fileExists(atPath: attachmentsURL.path) {
                try fileManager.removeItem(at: attachmentsURL)
                try fileManager.createDirectory(at: attachmentsURL, withIntermediateDirectories: true)
            }

            // Update local attachment records to clear localPath
            // This will be done by the AttachmentService when integrated

            storageUsed = 0
            attachmentCount = 0
        } catch {
            // Handle error silently for now
        }
    }
}

// MARK: - Storage Usage Row

private struct StorageUsageRow: View {
    let used: Int64
    let quota: AttachmentStorageQuota
    let attachmentCount: Int
    let isCalculating: Bool

    private var usageText: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file

        let usedString = formatter.string(fromByteCount: used)

        if quota == .unlimited {
            return usedString
        } else {
            return "\(usedString) of \(quota.displayName)"
        }
    }

    private var usagePercentage: Double {
        guard quota != .unlimited, quota.bytes > 0 else { return 0 }
        return min(Double(used) / Double(quota.bytes), 1.0)
    }

    private var progressColor: Color {
        if usagePercentage > 0.9 {
            return .red
        } else if usagePercentage > 0.7 {
            return .orange
        } else {
            return .blue
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Storage Used")
                Spacer()
                if isCalculating {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Text(usageText)
                        .foregroundStyle(.secondary)
                }
            }

            if quota != .unlimited && !isCalculating {
                ProgressView(value: usagePercentage)
                    .tint(progressColor)
            }

            if !isCalculating && attachmentCount > 0 {
                Text("\(attachmentCount) cached \(attachmentCount == 1 ? "file" : "files")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Previews

#Preview("Attachment Settings") {
    NavigationStack {
        AttachmentSettingsView()
    }
}

#Preview("Storage Usage - Low") {
    List {
        StorageUsageRow(
            used: 500_000_000,
            quota: .fiveGB,
            attachmentCount: 47,
            isCalculating: false
        )
    }
}

#Preview("Storage Usage - High") {
    List {
        StorageUsageRow(
            used: 4_800_000_000,
            quota: .fiveGB,
            attachmentCount: 234,
            isCalculating: false
        )
    }
}
