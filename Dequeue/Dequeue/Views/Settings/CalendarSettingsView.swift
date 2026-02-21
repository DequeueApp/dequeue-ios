//
//  CalendarSettingsView.swift
//  Dequeue
//
//  Settings for calendar integration
//

import SwiftUI

struct CalendarSettingsView: View {
    @StateObject private var calendarService = CalendarService.shared
    @AppStorage("calendarIntegrationEnabled") private var calendarEnabled = false
    @AppStorage("exportTasksToCalendar") private var exportTasks = false
    @State private var showCalendarView = false

    var body: some View {
        Form {
            Section {
                Toggle("Calendar Integration", isOn: $calendarEnabled)

                if calendarEnabled {
                    HStack {
                        Label("Status", systemImage: "checkmark.circle")
                        Spacer()
                        Text(statusText)
                            .foregroundStyle(calendarService.isAuthorized ? .green : .orange)
                    }

                    if !calendarService.isAuthorized {
                        Button("Grant Calendar Access") {
                            Task { await calendarService.requestAccess() }
                        }
                    }
                }
            } header: {
                Text("Calendar")
            } footer: {
                Text("View your calendar events alongside tasks and import events as tasks.")
            }

            if calendarEnabled && calendarService.isAuthorized {
                Section("Options") {
                    Toggle("Export tasks to calendar", isOn: $exportTasks)
                }

                Section("Calendars") {
                    let calendars = calendarService.availableCalendars()
                    if calendars.isEmpty {
                        Text("No calendars found")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(calendars) { cal in
                            HStack {
                                Circle()
                                    .fill(Color(hex: cal.colorHex ?? "#007AFF") ?? .blue)
                                    .frame(width: 10, height: 10)
                                Text(cal.title)
                                if cal.isSubscribed {
                                    Text("(subscribed)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section {
                    Button {
                        showCalendarView = true
                    } label: {
                        Label("Open Calendar View", systemImage: "calendar")
                    }
                }
            }
        }
        .navigationTitle("Calendar")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showCalendarView) {
            NavigationStack {
                CalendarView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showCalendarView = false }
                        }
                    }
            }
        }
    }

    private var statusText: String {
        switch calendarService.authorizationStatus {
        case .fullAccess: return "Connected"
        case .writeOnly: return "Write Only"
        case .restricted: return "Restricted"
        case .denied: return "Denied"
        case .notDetermined: return "Not Set Up"
        @unknown default: return "Unknown"
        }
    }
}

#Preview {
    NavigationStack {
        CalendarSettingsView()
    }
}
