//
//  SmartNotificationSettingsView.swift
//  Dequeue
//
//  Settings UI for configuring smart notifications
//

import SwiftUI

struct SmartNotificationSettingsView: View {
    @State private var settings = SmartNotificationSettings.default
    @State private var hasLoaded = false
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var body: some View {
        Form {
            // Due Date Section
            Section {
                Toggle("Auto-schedule for due dates", isOn: $settings.autoDueDateNotifications)

                if settings.autoDueDateNotifications {
                    Picker("Notify before due", selection: $settings.dueDateLeadTimeMinutes) {
                        Text("At due time").tag(0)
                        Text("5 minutes before").tag(5)
                        Text("15 minutes before").tag(15)
                        Text("30 minutes before").tag(30)
                        Text("1 hour before").tag(60)
                        Text("2 hours before").tag(120)
                        Text("1 day before").tag(1440)
                    }
                }
            } header: {
                Label("Due Date Alerts", systemImage: "clock.badge.exclamationmark")
            } footer: {
                Text("Automatically notify you when tasks are approaching their due date.")
            }

            // Morning Digest Section
            Section {
                Toggle("Morning digest", isOn: $settings.morningDigestEnabled)

                if settings.morningDigestEnabled {
                    HStack {
                        Text("Delivery time")
                        Spacer()
                        DigestTimePicker(
                            hour: $settings.morningDigestHour,
                            minute: $settings.morningDigestMinute
                        )
                    }
                }
            } header: {
                Label("Morning Summary", systemImage: "sun.max")
            } footer: {
                Text("Get a summary of today's tasks and overdue items each morning.")
            }

            // End of Day Section
            Section {
                Toggle("End-of-day reminder", isOn: $settings.endOfDayReminderEnabled)

                if settings.endOfDayReminderEnabled {
                    Picker("Reminder time", selection: $settings.endOfDayReminderHour) {
                        Text("4:00 PM").tag(16)
                        Text("5:00 PM").tag(17)
                        Text("6:00 PM").tag(18)
                        Text("7:00 PM").tag(19)
                        Text("8:00 PM").tag(20)
                        Text("9:00 PM").tag(21)
                    }
                }
            } header: {
                Label("End of Day", systemImage: "moon.stars")
            } footer: {
                Text("Remind you about incomplete tasks before end of day.")
            }

            // Overdue Section
            Section {
                Toggle("Overdue alerts", isOn: $settings.overdueAlertsEnabled)

                if settings.overdueAlertsEnabled {
                    Picker("Alert frequency", selection: $settings.overdueAlertIntervalHours) {
                        Text("Every 2 hours").tag(2)
                        Text("Every 4 hours").tag(4)
                        Text("Every 8 hours").tag(8)
                        Text("Once daily").tag(24)
                    }
                }
            } header: {
                Label("Overdue Tasks", systemImage: "exclamationmark.triangle")
            } footer: {
                Text("Get periodic reminders about tasks that are past due.")
            }

            // Limits Section
            Section {
                Stepper(
                    "Max \(settings.maxDailyNotifications) per day",
                    value: $settings.maxDailyNotifications,
                    in: 5...50,
                    step: 5
                )
            } header: {
                Label("Limits", systemImage: "slider.horizontal.3")
            } footer: {
                Text("Maximum number of smart notifications per day to prevent overload.")
            }
        }
        .navigationTitle("Smart Notifications")
        .onAppear {
            if !hasLoaded {
                loadSettings()
                hasLoaded = true
            }
        }
        .onChange(of: settings.autoDueDateNotifications) { saveSettings() }
        .onChange(of: settings.dueDateLeadTimeMinutes) { saveSettings() }
        .onChange(of: settings.morningDigestEnabled) { saveSettings() }
        .onChange(of: settings.morningDigestHour) { saveSettings() }
        .onChange(of: settings.morningDigestMinute) { saveSettings() }
        .onChange(of: settings.endOfDayReminderEnabled) { saveSettings() }
        .onChange(of: settings.endOfDayReminderHour) { saveSettings() }
        .onChange(of: settings.overdueAlertsEnabled) { saveSettings() }
        .onChange(of: settings.overdueAlertIntervalHours) { saveSettings() }
        .onChange(of: settings.maxDailyNotifications) { saveSettings() }
    }

    private func loadSettings() {
        if let data = userDefaults.data(forKey: SmartNotificationSettings.storageKey),
           let saved = try? JSONDecoder().decode(SmartNotificationSettings.self, from: data) {
            settings = saved
        }
    }

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            userDefaults.set(data, forKey: SmartNotificationSettings.storageKey)
        }
    }
}

// MARK: - Digest Time Picker

private struct DigestTimePicker: View {
    @Binding var hour: Int
    @Binding var minute: Int

    private var timeText: String {
        let h = hour % 12 == 0 ? 12 : hour % 12
        let ampm = hour < 12 ? "AM" : "PM"
        let m = String(format: "%02d", minute)
        return "\(h):\(m) \(ampm)"
    }

    var body: some View {
        Menu {
            ForEach([6, 7, 8, 9, 10], id: \.self) { h in
                Button("\(h):00 AM") {
                    hour = h
                    minute = 0
                }
                Button("\(h):30 AM") {
                    hour = h
                    minute = 30
                }
            }
        } label: {
            Text(timeText)
                .foregroundStyle(.blue)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SmartNotificationSettingsView()
    }
}
