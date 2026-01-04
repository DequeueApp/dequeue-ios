//
//  SyncStatusIndicator.swift
//  Dequeue
//
//  Visual indicator for sync status
//

import SwiftUI
import SwiftData

internal struct SyncStatusIndicator: View {
    // MARK: - Constants

    private enum Constants {
        static let iconFrameSize: CGFloat = 32
        static let rotationAnimationDuration: TimeInterval = 2.0
        static let fullRotation = Angle.degrees(360)
        static let popoverMinWidth: CGFloat = 200
        static let badgeOffset = CGSize(width: 6, height: -6)
    }

    @Bindable var viewModel: SyncStatusViewModel
    @State private var showDetails = false

    var body: some View {
        Button {
            showDetails.toggle()
        } label: {
            ZStack(alignment: .topTrailing) {
                // Icon changes based on status
                Image(systemName: iconName)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(iconColor, .primary)
                    .font(.body)
                    .rotationEffect(viewModel.isSyncing ? Constants.fullRotation : .zero)
                    .animation(
                        viewModel.isSyncing ?
                            .linear(duration: Constants.rotationAnimationDuration).repeatForever(autoreverses: false) :
                            .default,
                        value: viewModel.isSyncing
                    )

                // Badge for pending event count
                if viewModel.pendingEventCount > 0 {
                    Text("\(viewModel.pendingEventCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .frame(minWidth: 14, minHeight: 14)
                        .background(badgeColor)
                        .clipShape(Capsule())
                        .offset(Constants.badgeOffset)
                }
            }
            .frame(width: Constants.iconFrameSize, height: Constants.iconFrameSize)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sync Status")
        .accessibilityHint("Tap to view sync details")
        .accessibilityValue(viewModel.statusMessage)
        .popover(isPresented: $showDetails) {
            detailsView
                .padding()
                .frame(minWidth: Constants.popoverMinWidth)
        }
    }

    // MARK: - Subviews

    private var detailsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sync Status")
                .font(.headline)

            Divider()

            HStack {
                Text("Status:")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(viewModel.statusMessage)
                    .foregroundStyle(statusColor)
            }

            if viewModel.pendingEventCount > 0 {
                HStack {
                    Text("Pending:")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(viewModel.pendingEventCount)")
                }
            }

            HStack {
                Text("Last Sync:")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(viewModel.lastSyncTimeFormatted)
            }

            HStack {
                Text("Connection:")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(connectionStatusText)
                    .foregroundStyle(connectionStatusColor)
            }
        }
        .font(.subheadline)
    }

    // MARK: - Computed Properties

    private var iconName: String {
        switch viewModel.connectionStatus {
        case .connected:
            if viewModel.isSyncing {
                return "arrow.triangle.2.circlepath"
            } else if viewModel.pendingEventCount > 0 {
                return "exclamationmark.arrow.triangle.2.circlepath"
            } else {
                return "checkmark.icloud"
            }
        case .connecting:
            return "arrow.triangle.2.circlepath"
        case .disconnected:
            return "icloud.slash"
        }
    }

    private var iconColor: Color {
        switch viewModel.connectionStatus {
        case .connected:
            if viewModel.pendingEventCount > 0 {
                return .orange
            } else {
                return .green
            }
        case .connecting:
            return .orange
        case .disconnected:
            return .red
        }
    }

    private var badgeColor: Color {
        switch viewModel.connectionStatus {
        case .connected, .connecting:
            return .orange
        case .disconnected:
            return .red
        }
    }

    private var statusColor: Color {
        switch viewModel.connectionStatus {
        case .connected:
            return viewModel.pendingEventCount > 0 ? .orange : .green
        case .connecting:
            return .orange
        case .disconnected:
            return .red
        }
    }

    private var connectionStatusText: String {
        switch viewModel.connectionStatus {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting"
        case .disconnected:
            return "Offline"
        }
    }

    private var connectionStatusColor: Color {
        switch viewModel.connectionStatus {
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .disconnected:
            return .red
        }
    }
}

// MARK: - Preview

#Preview {
    // Force try is acceptable in previews - crashes here only affect Xcode previews, not production
    // swiftlint:disable:next force_try
    let container = try! ModelContainer(
        for: Event.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let viewModel = SyncStatusViewModel(modelContext: container.mainContext)

    SyncStatusIndicator(viewModel: viewModel)
}
