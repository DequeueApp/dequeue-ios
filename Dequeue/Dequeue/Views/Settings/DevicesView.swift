//
//  DevicesView.swift
//  Dequeue
//
//  Shows all connected devices for multi-device sync
//

import SwiftUI
import SwiftData

struct DevicesView: View {
    @Query(
        filter: #Predicate<Device> { !$0.isDeleted },
        sort: \Device.lastSeenAt,
        order: .reverse
    )
    private var devices: [Device]

    @State private var currentDeviceId: String?

    var body: some View {
        List {
            if devices.isEmpty {
                ContentUnavailableView(
                    "No Devices",
                    systemImage: "iphone.gen3",
                    description: Text("Your connected devices will appear here.")
                )
            } else {
                Section {
                    ForEach(devices) { device in
                        DeviceRow(device: device, isCurrentDevice: device.deviceId == currentDeviceId)
                    }
                } header: {
                    Text("Connected Devices")
                } footer: {
                    Text("Devices automatically sync when connected to the same account.")
                }
            }
        }
        .navigationTitle("Devices")
        .task {
            currentDeviceId = await DeviceService.shared.getDeviceId()
        }
    }
}

// MARK: - Device Row

struct DeviceRow: View {
    let device: Device
    let isCurrentDevice: Bool

    private var deviceIcon: String {
        #if os(iOS)
        if device.model?.lowercased().contains("ipad") == true {
            return "ipad"
        } else if device.model?.lowercased().contains("mac") == true {
            return "laptopcomputer"
        }
        return "iphone"
        #elseif os(macOS)
        if device.model?.lowercased().contains("iphone") == true {
            return "iphone"
        } else if device.model?.lowercased().contains("ipad") == true {
            return "ipad"
        }
        return "laptopcomputer"
        #else
        return "desktopcomputer"
        #endif
    }

    private var lastSeenText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: device.lastSeenAt, relativeTo: Date())
    }

    private var osInfo: String {
        if let version = device.osVersion {
            return "\(device.osName) \(version)"
        }
        return device.osName
    }

    var body: some View {
        HStack(spacing: 12) {
            deviceIconView
            deviceInfoView
            Spacer()
            lastSeenView
        }
        .padding(.vertical, 4)
    }

    private var deviceIconView: some View {
        Image(systemName: deviceIcon)
            .font(.title2)
            .foregroundStyle(isCurrentDevice ? .blue : .secondary)
            .frame(width: 32)
    }

    private var deviceInfoView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(device.name)
                    .fontWeight(isCurrentDevice ? .semibold : .regular)

                if isCurrentDevice {
                    currentDeviceBadge
                }
            }

            HStack(spacing: 4) {
                if let model = device.model {
                    Text(model)
                }
                Text("•")
                Text(osInfo)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var currentDeviceBadge: some View {
        Text("This Device")
            .font(.caption)
            .foregroundStyle(.blue)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.blue.opacity(0.1))
            .clipShape(Capsule())
    }

    @ViewBuilder
    private var lastSeenView: some View {
        if !isCurrentDevice {
            VStack(alignment: .trailing, spacing: 2) {
                Text("Last seen")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(lastSeenText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        DevicesView()
    }
    .modelContainer(for: [Device.self], inMemory: true)
}
