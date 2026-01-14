//
//  AttachmentPicker.swift
//  Dequeue
//
//  Cross-platform file picker for adding attachments
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Constants

private enum AttachmentPickerConstants {
    /// Maximum file size in bytes (50 MB)
    static let maxFileSizeBytes: Int64 = 50 * 1024 * 1024

    /// Formatted maximum file size for display
    static let maxFileSizeFormatted = "50 MB"
}

// MARK: - Attachment Picker

/// Cross-platform file picker supporting iOS, iPadOS, and macOS.
/// Provides file size validation and multiple file selection.
struct AttachmentPicker: View {
    @Binding var isPresented: Bool
    var allowsMultipleSelection: Bool = true
    var onFilesSelected: ([URL]) -> Void
    var onError: ((AttachmentPickerError) -> Void)?

    var body: some View {
        #if os(iOS)
        DocumentPicker(
            isPresented: $isPresented,
            allowsMultipleSelection: allowsMultipleSelection,
            onFilesSelected: { urls in
                validateAndReturn(urls)
            }
        )
        #elseif os(macOS)
        EmptyView()
            .onChange(of: isPresented) { _, newValue in
                if newValue {
                    showOpenPanel()
                }
            }
        #endif
    }

    private func validateAndReturn(_ urls: [URL]) {
        var validFiles: [URL] = []
        var errors: [AttachmentPickerError] = []

        for url in urls {
            do {
                let fileSize = try getFileSize(url)
                if fileSize > AttachmentPickerConstants.maxFileSizeBytes {
                    errors.append(.fileTooLarge(
                        filename: url.lastPathComponent,
                        size: fileSize,
                        maxSize: AttachmentPickerConstants.maxFileSizeBytes
                    ))
                } else {
                    validFiles.append(url)
                }
            } catch {
                errors.append(.fileAccessError(filename: url.lastPathComponent, error: error))
            }
        }

        // Report first error if any
        if let firstError = errors.first {
            onError?(firstError)
        }

        // Return valid files even if some were invalid
        if !validFiles.isEmpty {
            onFilesSelected(validFiles)
        }
    }

    private func getFileSize(_ url: URL) throws -> Int64 {
        let resourceValues = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = resourceValues.fileSize else {
            throw AttachmentPickerError.fileAccessError(
                filename: url.lastPathComponent,
                error: NSError(
                    domain: "AttachmentPicker",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Unable to determine file size"]
                )
            )
        }
        return Int64(size)
    }

    #if os(macOS)
    private func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = allowsMultipleSelection
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.item] // All file types

        panel.begin { response in
            DispatchQueue.main.async {
                isPresented = false
                if response == .OK {
                    validateAndReturn(panel.urls)
                }
            }
        }
    }
    #endif
}

// MARK: - iOS Document Picker

#if os(iOS)
/// UIViewControllerRepresentable wrapper for UIDocumentPickerViewController
struct DocumentPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var allowsMultipleSelection: Bool
    var onFilesSelected: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item])
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
        // No updates needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker

        init(parent: DocumentPicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            // Start accessing security-scoped resources
            let accessedURLs = urls.compactMap { url -> URL? in
                guard url.startAccessingSecurityScopedResource() else {
                    return nil
                }
                return url
            }

            parent.onFilesSelected(accessedURLs)
            parent.isPresented = false

            // Note: Security-scoped resource access should be stopped after
            // the file has been copied to the app's storage
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.isPresented = false
        }
    }
}
#endif

// MARK: - Error Types

/// Errors that can occur during file selection
enum AttachmentPickerError: LocalizedError {
    case fileTooLarge(filename: String, size: Int64, maxSize: Int64)
    case fileAccessError(filename: String, error: Error)
    case unsupportedFileType(filename: String)

    var errorDescription: String? {
        switch self {
        case .fileTooLarge(let filename, let size, let maxSize):
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            let sizeStr = formatter.string(fromByteCount: size)
            let maxStr = formatter.string(fromByteCount: maxSize)
            return "File '\(filename)' (\(sizeStr)) exceeds the maximum size of \(maxStr)"

        case .fileAccessError(let filename, let error):
            return "Unable to access '\(filename)': \(error.localizedDescription)"

        case .unsupportedFileType(let filename):
            return "File type not supported: \(filename)"
        }
    }
}

// MARK: - View Modifier for Sheet Presentation

extension View {
    /// Presents an attachment picker as a sheet.
    func attachmentPicker(
        isPresented: Binding<Bool>,
        allowsMultipleSelection: Bool = true,
        onFilesSelected: @escaping ([URL]) -> Void,
        onError: ((AttachmentPickerError) -> Void)? = nil
    ) -> some View {
        sheet(isPresented: isPresented) {
            #if os(iOS)
            AttachmentPicker(
                isPresented: isPresented,
                allowsMultipleSelection: allowsMultipleSelection,
                onFilesSelected: onFilesSelected,
                onError: onError
            )
            #else
            // macOS uses NSOpenPanel directly, not a sheet
            EmptyView()
            #endif
        }
        #if os(macOS)
        .onChange(of: isPresented.wrappedValue) { _, newValue in
            if newValue {
                // Show open panel on macOS
                let panel = NSOpenPanel()
                panel.allowsMultipleSelection = allowsMultipleSelection
                panel.canChooseDirectories = false
                panel.canChooseFiles = true
                panel.allowedContentTypes = [.item]

                panel.begin { response in
                    DispatchQueue.main.async {
                        isPresented.wrappedValue = false
                        if response == .OK {
                            onFilesSelected(panel.urls)
                        }
                    }
                }
            }
        }
        #endif
    }
}

// MARK: - Preview

#Preview("Attachment Picker - iOS") {
    struct PreviewWrapper: View {
        @State private var showPicker = false
        @State private var selectedFiles: [URL] = []
        @State private var error: AttachmentPickerError?

        var body: some View {
            VStack(spacing: 20) {
                Button("Select Files") {
                    showPicker = true
                }

                if !selectedFiles.isEmpty {
                    VStack(alignment: .leading) {
                        Text("Selected Files:")
                            .font(.headline)
                        ForEach(selectedFiles, id: \.self) { url in
                            Text(url.lastPathComponent)
                                .font(.caption)
                        }
                    }
                }

                if let error {
                    Text(error.localizedDescription)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            .attachmentPicker(
                isPresented: $showPicker,
                onFilesSelected: { urls in
                    selectedFiles = urls
                },
                onError: { err in
                    error = err
                }
            )
        }
    }

    return PreviewWrapper()
}
