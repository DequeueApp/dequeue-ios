//
//  AddReminderSheet.swift
//  Dequeue
//
//  Sheet for adding a reminder to a task with notification permission handling (DEQ-13)
//

import SwiftUI
import SwiftData
import UserNotifications

struct AddReminderSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let task: QueueTask
    let notificationService: NotificationService

    @State private var selectedDate = Date().addingTimeInterval(3_600) // 1 hour from now
    @State private var permissionState: PermissionState = .checking
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isSaving = false

    private var reminderService: ReminderService {
        ReminderService(modelContext: modelContext)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch permissionState {
                case .checking:
                    loadingView
                case .notDetermined:
                    permissionExplanationView
                case .authorized:
                    datePickerView
                case .denied:
                    permissionDeniedView
                }
            }
            .navigationTitle("Add Reminder")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                if permissionState == .authorized {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            saveReminder()
                        }
                        .disabled(isSaving || selectedDate <= Date())
                        .accessibilityIdentifier("saveReminderButton")
                    }
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
        .presentationDetents([.medium])
        .task {
            await checkPermissionState()
        }
    }

    // MARK: - Views

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Checking notification permissions...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var permissionExplanationView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "bell.badge")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            VStack(spacing: 12) {
                Text("Enable Notifications")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Dequeue needs permission to send you notifications so you don't miss your reminders.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button {
                Task {
                    await requestPermission()
                }
            } label: {
                Text("Enable Notifications")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)
            .accessibilityIdentifier("enableNotificationsButton")

            Button("Not Now") {
                dismiss()
            }
            .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
    }

    private var datePickerView: some View {
        Form {
            Section {
                HStack {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.blue)
                    Text(task.title)
                        .lineLimit(2)
                }
            } header: {
                Text("Task")
            }

            Section {
                DatePicker(
                    "Remind me at",
                    selection: $selectedDate,
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .accessibilityIdentifier("reminderDatePicker")
            } header: {
                Text("When")
            }

            Section {
                quickSelectButtons
            } header: {
                Text("Quick Select")
            }
        }
    }

    private var quickSelectButtons: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                QuickSelectButton(title: "In 1 hour", icon: "clock") {
                    selectedDate = Date().addingTimeInterval(3_600)
                }
                QuickSelectButton(title: "In 3 hours", icon: "clock") {
                    selectedDate = Date().addingTimeInterval(3_600 * 3)
                }
            }
            HStack(spacing: 12) {
                QuickSelectButton(title: "Tomorrow 9 AM", icon: "sunrise") {
                    selectedDate = nextDayAt(hour: 9)
                }
                QuickSelectButton(title: "Tomorrow 6 PM", icon: "sunset") {
                    selectedDate = nextDayAt(hour: 18)
                }
            }
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "bell.slash")
                .font(.system(size: 60))
                .foregroundStyle(.orange)

            VStack(spacing: 12) {
                Text("Notifications Disabled")
                    .font(.title2)
                    .fontWeight(.semibold)

                // swiftlint:disable:next line_length
                Text("You've disabled notifications for Dequeue. To set reminders, please enable notifications in Settings.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button {
                openSettings()
            } label: {
                Text("Open Settings")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)
            .accessibilityIdentifier("openSettingsButton")

            Button("Cancel") {
                dismiss()
            }
            .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
    }

    // MARK: - Actions

    private func checkPermissionState() async {
        let status = await notificationService.getAuthorizationStatus()
        switch status {
        case .authorized, .provisional, .ephemeral:
            permissionState = .authorized
        case .denied:
            permissionState = .denied
        case .notDetermined:
            permissionState = .notDetermined
        @unknown default:
            permissionState = .notDetermined
        }
    }

    private func requestPermission() async {
        let granted = await notificationService.requestPermission()
        if granted {
            permissionState = .authorized
        } else {
            permissionState = .denied
        }
    }

    private func saveReminder() {
        isSaving = true

        Task {
            do {
                let reminder = try reminderService.createReminder(for: task, at: selectedDate)
                try await notificationService.scheduleNotification(for: reminder)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
                ErrorReportingService.capture(error: error, context: ["action": "save_reminder"])
            }
            isSaving = false
        }
    }

    private func openSettings() {
        #if os(iOS)
        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsURL)
        }
        #elseif os(macOS)
        if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(settingsURL)
        }
        #endif
    }

    private func nextDayAt(hour: Int) -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
}

// MARK: - Permission State

private enum PermissionState {
    case checking
    case notDetermined
    case authorized
    case denied
}

// MARK: - Quick Select Button

private struct QuickSelectButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                Text(title)
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color.secondary.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview("Authorized") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    // swiftlint:disable:next force_try
    let container = try! ModelContainer(
        for: Stack.self,
        QueueTask.self,
        Reminder.self,
        Event.self,
        configurations: config
    )

    let stack = Stack(title: "Test Stack", status: .active, sortOrder: 0)
    container.mainContext.insert(stack)

    let task = QueueTask(title: "Test Task", status: .pending, sortOrder: 0)
    task.stack = stack
    container.mainContext.insert(task)

    let service = NotificationService(modelContext: container.mainContext)

    return AddReminderSheet(task: task, notificationService: service)
        .modelContainer(container)
}
