//
//  AttachmentPreviewCoordinator.swift
//  Dequeue
//
//  Coordinates attachment preview with Quick Look, handling download if needed
//

import SwiftUI
import QuickLook
import os.log

// MARK: - Preview State

/// State for attachment preview operations
@Observable
final class AttachmentPreviewCoordinator {
    /// The URL currently being previewed (nil when not previewing)
    var previewURL: URL?

    /// Whether a download is in progress before preview
    var isDownloading = false

    /// Download progress (0.0 to 1.0)
    var downloadProgress: Double = 0

    /// Error message if preview failed
    var errorMessage: String?

    /// Whether to show the error alert
    var showError = false

    private let logger = Logger(subsystem: "com.dequeue", category: "AttachmentPreview")

    /// Request to preview an attachment
    /// - Parameters:
    ///   - attachment: The attachment to preview
    ///   - downloadHandler: Optional handler to download the file if not available locally
    func preview(
        attachment: Attachment,
        downloadHandler: ((Attachment) async throws -> URL)?
    ) async {
        // Reset state
        errorMessage = nil
        showError = false
        downloadProgress = 0

        // Check if file is available locally
        if attachment.isAvailableLocally, let localPath = attachment.localPath {
            let url = URL(fileURLWithPath: localPath)
            await MainActor.run {
                self.previewURL = url
            }
            return
        }

        // File not local - need to download first
        guard let downloadHandler else {
            await MainActor.run {
                self.errorMessage = "File not available locally and no download handler provided"
                self.showError = true
            }
            return
        }

        // Start download
        await MainActor.run {
            self.isDownloading = true
        }

        do {
            logger.debug("Downloading attachment for preview: \(attachment.filename)")
            let localURL = try await downloadHandler(attachment)

            await MainActor.run {
                self.isDownloading = false
                self.downloadProgress = 1.0
                self.previewURL = localURL
            }
        } catch {
            logger.error("Failed to download attachment for preview: \(error.localizedDescription)")
            await MainActor.run {
                self.isDownloading = false
                self.errorMessage = "Failed to download file: \(error.localizedDescription)"
                self.showError = true
            }
        }
    }

    /// Update download progress
    func updateProgress(_ progress: Double) {
        Task { @MainActor in
            self.downloadProgress = progress
        }
    }

    /// Dismiss the preview
    func dismiss() {
        previewURL = nil
    }
}

// MARK: - Quick Look Preview View

#if os(iOS)
/// Quick Look preview controller wrapper for iOS
struct AttachmentQuickLookView: UIViewControllerRepresentable {
    let url: URL
    var onDismiss: (() -> Void)?

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        context.coordinator.url = url
        uiViewController.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url, onDismiss: onDismiss)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
        var url: URL
        var onDismiss: (() -> Void)?

        init(url: URL, onDismiss: (() -> Void)?) {
            self.url = url
            self.onDismiss = onDismiss
        }

        // MARK: - QLPreviewControllerDataSource

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }

        // MARK: - QLPreviewControllerDelegate

        func previewControllerDidDismiss(_ controller: QLPreviewController) {
            onDismiss?()
        }
    }
}
#endif

#if os(macOS)
import AppKit

/// Quick Look preview for macOS using QLPreviewPanel
struct AttachmentQuickLookView: NSViewRepresentable {
    let url: URL
    var onDismiss: (() -> Void)?

    func makeNSView(context: Context) -> NSView {
        let view = QuickLookHostView(url: url, onDismiss: onDismiss)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let hostView = nsView as? QuickLookHostView {
            hostView.url = url
        }
    }

    final class QuickLookHostView: NSView, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
        var url: URL
        var onDismiss: (() -> Void)?

        init(url: URL, onDismiss: (() -> Void)?) {
            self.url = url
            self.onDismiss = onDismiss
            super.init(frame: .zero)

            // Show Quick Look panel after a brief delay to allow view setup
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.showQuickLook()
            }
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var acceptsFirstResponder: Bool { true }

        // swiftlint:disable implicitly_unwrapped_optional
        // These method signatures are required by the Objective-C QLPreviewPanel API
        override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
            true
        }

        override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
            panel.dataSource = self
            panel.delegate = self
        }

        override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
            onDismiss?()
        }
        // swiftlint:enable implicitly_unwrapped_optional

        private func showQuickLook() {
            guard let panel = QLPreviewPanel.shared() else { return }
            panel.makeKeyAndOrderFront(nil)
        }

        // MARK: - QLPreviewPanelDataSource

        // swiftlint:disable implicitly_unwrapped_optional
        // Protocol method signatures required by Objective-C QLPreviewPanelDataSource
        func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
            1
        }

        func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
            url as NSURL
        }
        // swiftlint:enable implicitly_unwrapped_optional
    }
}
#endif

// MARK: - Preview View Modifier

/// View modifier for presenting attachment preview
struct AttachmentPreviewModifier: ViewModifier {
    @Bindable var coordinator: AttachmentPreviewCoordinator

    func body(content: Content) -> some View {
        content
            #if os(iOS)
            .fullScreenCover(item: $coordinator.previewURL) { url in
                AttachmentQuickLookView(url: url) {
                    coordinator.dismiss()
                }
                .ignoresSafeArea()
            }
            #elseif os(macOS)
            .onChange(of: coordinator.previewURL) { _, newValue in
                if let url = newValue {
                    // macOS uses the QLPreviewPanel system
                    NSWorkspace.shared.open(url)
                    coordinator.dismiss()
                }
            }
            #endif
            .alert("Preview Error", isPresented: $coordinator.showError) {
                Button("OK") {
                    coordinator.errorMessage = nil
                }
            } message: {
                if let errorMessage = coordinator.errorMessage {
                    Text(errorMessage)
                }
            }
    }
}

// MARK: - URL Extension for Identifiable

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

// MARK: - View Extension

extension View {
    /// Adds attachment preview capability using Quick Look
    func attachmentPreview(coordinator: AttachmentPreviewCoordinator) -> some View {
        modifier(AttachmentPreviewModifier(coordinator: coordinator))
    }
}

// MARK: - Download Progress Overlay

/// Overlay view showing download progress before preview
struct AttachmentDownloadOverlay: View {
    let isDownloading: Bool
    let progress: Double
    let filename: String

    var body: some View {
        if isDownloading {
            ZStack {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    ProgressView(value: progress)
                        .progressViewStyle(.circular)
                        .scaleEffect(1.5)

                    Text("Downloading...")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text(filename)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)

                    if progress > 0 {
                        Text("\(Int(progress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .padding(24)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}

// MARK: - Previews

#Preview("Download Overlay") {
    ZStack {
        Color.gray
        AttachmentDownloadOverlay(
            isDownloading: true,
            progress: 0.65,
            filename: "document.pdf"
        )
    }
}
