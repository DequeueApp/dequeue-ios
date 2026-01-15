//
//  AttachmentProgressView.swift
//  Dequeue
//
//  Progress indicators for attachment upload/download
//

import SwiftUI

// MARK: - Progress Types

/// Represents the current transfer state of an attachment
enum AttachmentTransferState: Equatable {
    /// No transfer in progress
    case idle

    /// Upload in progress
    case uploading(progress: Double)

    /// Download in progress
    case downloading(progress: Double)

    /// Transfer failed
    case failed(isUpload: Bool)

    /// Transfer complete
    case complete
}

// MARK: - Circular Progress Indicator

/// Circular progress indicator for uploads, overlaid on thumbnails
struct CircularProgressIndicator: View {
    let progress: Double
    var showPercentage: Bool = false
    var onCancel: (() -> Void)?

    private let lineWidth: CGFloat = 3
    private let size: CGFloat = 44

    var body: some View {
        ZStack {
            // Background blur
            Circle()
                .fill(.ultraThinMaterial)

            // Track
            Circle()
                .stroke(Color.secondary.opacity(0.3), lineWidth: lineWidth)

            // Progress
            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(
                    Color.blue,
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.1), value: progress)

            // Content
            VStack(spacing: 2) {
                if showPercentage {
                    Text("\(Int(progress * 100))%")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                } else if let onCancel {
                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Linear Progress Bar

/// Linear progress bar for downloads, shown below thumbnails
struct LinearProgressBar: View {
    let progress: Double
    var showBytes: (transferred: Int64, total: Int64)?
    var onCancel: (() -> Void)?

    var body: some View {
        VStack(spacing: 4) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.2))

                    // Progress
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.blue)
                        .frame(width: geometry.size.width * CGFloat(progress))
                        .animation(.linear(duration: 0.1), value: progress)
                }
            }
            .frame(height: 4)

            // Status text
            HStack {
                if let bytes = showBytes {
                    Text(formatBytes(bytes.transferred, total: bytes.total))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(Int(progress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let onCancel {
                    Button("Cancel", action: onCancel)
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }
        }
    }

    private func formatBytes(_ transferred: Int64, total: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB]

        let transferredStr = formatter.string(fromByteCount: transferred)
        let totalStr = formatter.string(fromByteCount: total)
        return "\(transferredStr) / \(totalStr)"
    }
}

// MARK: - Status Badge

/// Badge overlay showing attachment status
struct AttachmentStatusBadge: View {
    let state: AttachmentTransferState
    var onRetry: (() -> Void)?

    var body: some View {
        switch state {
        case .idle:
            EmptyView()

        case .uploading(let progress):
            CircularProgressIndicator(progress: progress)

        case .downloading(let progress):
            downloadingBadge(progress: progress)

        case .failed(let isUpload):
            failedBadge(isUpload: isUpload)

        case .complete:
            completeBadge
        }
    }

    @ViewBuilder
    private func downloadingBadge(progress: Double) -> some View {
        VStack {
            Spacer()
            LinearProgressBar(progress: progress)
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
        }
    }

    @ViewBuilder
    private func failedBadge(isUpload: Bool) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    onRetry?()
                } label: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(.red)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityLabel(isUpload ? "Upload failed. Tap to retry." : "Download failed. Tap to retry.")
    }

    private var completeBadge: some View {
        VStack {
            HStack {
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .background(
                        Circle()
                            .fill(.green)
                            .padding(-2)
                    )
            }
            Spacer()
        }
        .accessibilityLabel("Available offline")
    }
}

// MARK: - Attachment Progress Overlay

/// Complete progress overlay for attachment cells
struct AttachmentProgressOverlay: View {
    let state: AttachmentTransferState
    var onCancel: (() -> Void)?
    var onRetry: (() -> Void)?

    var body: some View {
        ZStack {
            switch state {
            case .idle:
                EmptyView()

            case .uploading(let progress):
                uploadingOverlay(progress: progress)

            case .downloading(let progress):
                downloadingOverlay(progress: progress)

            case .failed(let isUpload):
                failedOverlay(isUpload: isUpload)

            case .complete:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func uploadingOverlay(progress: Double) -> some View {
        Color.black.opacity(0.3)
        CircularProgressIndicator(
            progress: progress,
            showPercentage: true,
            onCancel: onCancel
        )
    }

    @ViewBuilder
    private func downloadingOverlay(progress: Double) -> some View {
        VStack {
            Spacer()
            LinearProgressBar(
                progress: progress,
                onCancel: onCancel
            )
            .padding(8)
            .background(.ultraThinMaterial)
        }
    }

    @ViewBuilder
    private func failedOverlay(isUpload: Bool) -> some View {
        Color.red.opacity(0.1)

        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.red)

            if let onRetry {
                Button {
                    onRetry()
                } label: {
                    Text("Retry")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(.blue)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Previews

#Preview("Circular Progress - 0%") {
    CircularProgressIndicator(progress: 0.0, showPercentage: true)
        .padding()
}

#Preview("Circular Progress - 50%") {
    CircularProgressIndicator(progress: 0.5, showPercentage: true)
        .padding()
}

#Preview("Circular Progress - 100%") {
    CircularProgressIndicator(progress: 1.0, showPercentage: true)
        .padding()
}

#Preview("Circular Progress with Cancel") {
    CircularProgressIndicator(progress: 0.3, onCancel: { })
        .padding()
}

#Preview("Linear Progress - 50%") {
    LinearProgressBar(
        progress: 0.5,
        showBytes: (transferred: 5_000_000, total: 10_000_000),
        onCancel: { }
    )
    .padding()
}

#Preview("Progress Overlay - Uploading") {
    ZStack {
        RoundedRectangle(cornerRadius: 10)
            .fill(.gray.opacity(0.3))
            .frame(width: 100, height: 100)

        AttachmentProgressOverlay(
            state: .uploading(progress: 0.45),
            onCancel: { }
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

#Preview("Progress Overlay - Downloading") {
    ZStack {
        RoundedRectangle(cornerRadius: 10)
            .fill(.gray.opacity(0.3))
            .frame(width: 100, height: 100)

        AttachmentProgressOverlay(
            state: .downloading(progress: 0.65),
            onCancel: { }
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

#Preview("Progress Overlay - Failed") {
    ZStack {
        RoundedRectangle(cornerRadius: 10)
            .fill(.gray.opacity(0.3))
            .frame(width: 100, height: 100)

        AttachmentProgressOverlay(
            state: .failed(isUpload: true),
            onRetry: { }
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

#Preview("Status Badge - Complete") {
    ZStack {
        RoundedRectangle(cornerRadius: 10)
            .fill(.gray.opacity(0.3))
            .frame(width: 80, height: 80)

        AttachmentStatusBadge(state: .complete)
            .padding(4)
    }
}
