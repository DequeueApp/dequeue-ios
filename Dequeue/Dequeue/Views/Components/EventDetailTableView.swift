//
//  EventDetailTableView.swift
//  Dequeue
//
//  Shows event payload as a key/value table for developer mode
//

import SwiftUI

struct EventDetailTableView: View {
    let event: Event
    @Environment(\.dismiss) private var dismiss

    private var keyValuePairs: [(key: String, value: String)] {
        guard let jsonObject = try? JSONSerialization.jsonObject(with: event.payload) as? [String: Any] else {
            return []
        }
        return flattenJSON(jsonObject, prefix: "")
    }

    var body: some View {
        NavigationStack {
            List {
                eventInfoSection
                payloadSection
            }
            .navigationTitle("Event Details")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 400)
        #endif
    }

    private var eventInfoSection: some View {
        Section("Event Info") {
            LabeledContent("Type", value: event.type)
            LabeledContent("Timestamp", value: event.timestamp.formatted(date: .abbreviated, time: .standard))
            if let entityId = event.entityId {
                LabeledContent("Entity ID", value: entityId)
            }
            LabeledContent("Synced", value: event.isSynced ? "Yes" : "No")
        }
    }

    private var payloadSection: some View {
        Section("Payload") {
            if keyValuePairs.isEmpty {
                Text("No payload data")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(keyValuePairs, id: \.key) { pair in
                    PayloadRow(key: pair.key, value: pair.value)
                }
            }
        }
    }

    /// Flattens nested JSON into dot-notation key paths
    private func flattenJSON(_ json: [String: Any], prefix: String) -> [(key: String, value: String)] {
        var result: [(key: String, value: String)] = []

        let sortedKeys = json.keys.sorted()
        for key in sortedKeys {
            let fullKey = prefix.isEmpty ? key : "\(prefix).\(key)"
            guard let value = json[key] else { continue }

            if let nested = value as? [String: Any] {
                result.append(contentsOf: flattenJSON(nested, prefix: fullKey))
            } else if let array = value as? [Any] {
                result.append((fullKey, formatArray(array)))
            } else {
                result.append((fullKey, formatValue(value)))
            }
        }
        return result
    }

    private func formatValue(_ value: Any) -> String {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let bool as Bool:
            return bool ? "true" : "false"
        case is NSNull:
            return "null"
        default:
            return String(describing: value)
        }
    }

    private func formatArray(_ array: [Any]) -> String {
        let items = array.map { formatValue($0) }
        return "[\(items.joined(separator: ", "))]"
    }
}

// MARK: - Payload Row

private struct PayloadRow: View {
    let key: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(key)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    let samplePayload: [String: Any] = [
        "stackId": "abc123",
        "state": [
            "id": "abc123",
            "title": "My Stack",
            "status": "active"
        ]
    ]
    guard let payloadData = try? JSONSerialization.data(withJSONObject: samplePayload) else {
        return EventDetailTableView(event: Event(
            type: "stack.created",
            payload: Data(),
            userId: "user1",
            deviceId: "device1",
            appId: "com.dequeue"
        ))
    }
    let sampleEvent = Event(
        type: "stack.created",
        payload: payloadData,
        userId: "user1",
        deviceId: "device1",
        appId: "com.dequeue"
    )

    return EventDetailTableView(event: sampleEvent)
}
