//
//  SnoozePickerSheet.swift
//  Dequeue
//
//  Sheet for selecting snooze duration with preset options (DEQ-18)
//

import SwiftUI

struct SnoozePickerSheet: View {
    @Binding var isPresented: Bool
    let reminder: Reminder
    let onSnooze: (Date) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(SnoozeOption.allCases) { option in
                        Button {
                            onSnooze(option.targetDate)
                            isPresented = false
                        } label: {
                            HStack {
                                Image(systemName: option.iconName)
                                    .foregroundStyle(option.iconColor)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(option.title)
                                        .foregroundStyle(.primary)
                                    Text(option.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(option.targetDate.formatted(date: .omitted, time: .shortened))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("snoozeOption_\(option.rawValue)")
                    }
                } header: {
                    Text("Snooze until")
                } footer: {
                    Text("The reminder will fire again at the selected time.")
                }
            }
            .navigationTitle("Snooze Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Snooze Options

enum SnoozeOption: String, CaseIterable, Identifiable {
    case fifteenMinutes = "15min"
    case oneHour = "1hour"
    case threeHours = "3hours"
    case tomorrowMorning = "tomorrowMorning"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fifteenMinutes:
            return "15 minutes"
        case .oneHour:
            return "1 hour"
        case .threeHours:
            return "3 hours"
        case .tomorrowMorning:
            return "Tomorrow morning"
        }
    }

    var subtitle: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: targetDate, relativeTo: Date())
    }

    var iconName: String {
        switch self {
        case .fifteenMinutes:
            return "clock"
        case .oneHour:
            return "clock.fill"
        case .threeHours:
            return "clock.badge"
        case .tomorrowMorning:
            return "sun.horizon.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .fifteenMinutes:
            return .blue
        case .oneHour:
            return .orange
        case .threeHours:
            return .purple
        case .tomorrowMorning:
            return .yellow
        }
    }

    var targetDate: Date {
        let calendar = Calendar.current
        let now = Date()

        switch self {
        case .fifteenMinutes:
            return now.addingTimeInterval(15 * 60)
        case .oneHour:
            return now.addingTimeInterval(60 * 60)
        case .threeHours:
            return now.addingTimeInterval(3 * 60 * 60)
        case .tomorrowMorning:
            // Tomorrow at 9:00 AM
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else {
                return now.addingTimeInterval(24 * 60 * 60)
            }
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        }
    }
}

// MARK: - Preview

#Preview {
    struct PreviewWrapper: View {
        @State private var isPresented = true

        var body: some View {
            Text("Tap to show sheet")
                .sheet(isPresented: $isPresented) {
                    SnoozePickerSheet(
                        isPresented: $isPresented,
                        reminder: Reminder(
                            parentId: "test",
                            parentType: .task,
                            remindAt: Date()
                        ),
                        onSnooze: { _ in
                            // Preview handler - no-op
                        }
                    )
                }
        }
    }

    return PreviewWrapper()
}
