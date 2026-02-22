//
//  RecurrencePickerView.swift
//  Dequeue
//
//  UI for selecting and configuring task recurrence patterns
//

import SwiftUI

// MARK: - Recurrence Picker Sheet

struct RecurrencePickerSheet: View {
    @Binding var recurrenceRule: RecurrenceRule?
    @Environment(\.dismiss) private var dismiss

    @State private var isEnabled = false
    @State private var frequency: RecurrenceFrequency = .weekly
    @State private var interval = 1
    @State private var selectedDays: Set<RecurrenceDay> = []
    @State private var dayOfMonth = 1
    @State private var endType: EndType = .never
    @State private var endOccurrences = 10
    @State private var endDate = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()

    enum EndType: String, CaseIterable {
        case never = "Never"
        case afterCount = "After # times"
        case onDate = "On date"
    }

    var body: some View {
        NavigationStack {
            Form {
                // Quick presets
                presetsSection

                // Toggle
                Section {
                    Toggle("Repeat", isOn: $isEnabled)
                }

                if isEnabled {
                    // Frequency & interval
                    frequencySection

                    // Day selection (weekly only)
                    if frequency == .weekly {
                        daySelectionSection
                    }

                    // Day of month (monthly only)
                    if frequency == .monthly {
                        monthDaySection
                    }

                    // End condition
                    endSection

                    // Preview
                    previewSection
                }
            }
            .navigationTitle("Repeat")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveAndDismiss()
                    }
                }
            }
            .onAppear {
                loadFromRule()
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #else
        .frame(minWidth: 400, minHeight: 350)
        #endif
    }

    // MARK: - Sections

    private var presetsSection: some View {
        Section("Quick Presets") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(RecurrenceRule.presets, id: \.name) { preset in
                        Button {
                            applyPreset(preset.rule)
                        } label: {
                            Text(preset.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    isPresetSelected(preset.rule) ? Color.accentColor : Color.secondary.opacity(0.2)
                                )
                                .foregroundStyle(isPresetSelected(preset.rule) ? .white : .primary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var frequencySection: some View {
        Section("Frequency") {
            Picker("Repeat every", selection: $frequency) {
                ForEach(RecurrenceFrequency.allCases, id: \.self) { freq in
                    Text(freq.displayName).tag(freq)
                }
            }

            Stepper(
                "Every \(interval) \(intervalLabel)",
                value: $interval,
                in: 1...99
            )
        }
    }

    private var daySelectionSection: some View {
        Section("On days") {
            HStack(spacing: 4) {
                ForEach(RecurrenceDay.allCases, id: \.rawValue) { day in
                    DayToggleButton(
                        day: day,
                        isSelected: selectedDays.contains(day),
                        onToggle: {
                            if selectedDays.contains(day) {
                                selectedDays.remove(day)
                            } else {
                                selectedDays.insert(day)
                            }
                        }
                    )
                }
            }
            .padding(.vertical, 4)

            // Quick select buttons
            HStack {
                Button("Weekdays") { selectedDays = RecurrenceDay.weekdays }
                    .font(.caption)
                    .buttonStyle(.bordered)
                Button("Weekends") { selectedDays = RecurrenceDay.weekends }
                    .font(.caption)
                    .buttonStyle(.bordered)
                Button("Every day") { selectedDays = Set(RecurrenceDay.allCases) }
                    .font(.caption)
                    .buttonStyle(.bordered)
                Spacer()
                if !selectedDays.isEmpty {
                    Button("Clear") { selectedDays = [] }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var monthDaySection: some View {
        Section("Day of month") {
            Stepper("Day \(dayOfMonth)", value: $dayOfMonth, in: 1...31)
        }
    }

    private var endSection: some View {
        Section("Ends") {
            Picker("End", selection: $endType) {
                ForEach(EndType.allCases, id: \.self) { type in
                    Text(type.rawValue).tag(type)
                }
            }

            switch endType {
            case .never:
                EmptyView()
            case .afterCount:
                Stepper(
                    "\(endOccurrences) occurrence\(endOccurrences == 1 ? "" : "s")",
                    value: $endOccurrences,
                    in: 1...999
                )
            case .onDate:
                DatePicker("End date", selection: $endDate, displayedComponents: .date)
            }
        }
    }

    private var previewSection: some View {
        Section("Preview") {
            let rule = buildRule()
            Label {
                Text(rule.displayText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "repeat")
                    .foregroundStyle(.blue)
            }
        }
    }

    // MARK: - Helpers

    private var intervalLabel: String {
        switch frequency {
        case .daily: return interval == 1 ? "day" : "days"
        case .weekly: return interval == 1 ? "week" : "weeks"
        case .monthly: return interval == 1 ? "month" : "months"
        case .yearly: return interval == 1 ? "year" : "years"
        }
    }

    private func loadFromRule() {
        guard let rule = recurrenceRule else {
            isEnabled = false
            return
        }
        isEnabled = true
        frequency = rule.frequency
        interval = rule.interval
        selectedDays = rule.daysOfWeek
        dayOfMonth = rule.dayOfMonth ?? 1
        switch rule.end {
        case .never:
            endType = .never
        case .afterOccurrences(let count):
            endType = .afterCount
            endOccurrences = count
        case .onDate(let date):
            endType = .onDate
            endDate = date
        }
    }

    private func applyPreset(_ rule: RecurrenceRule) {
        isEnabled = true
        frequency = rule.frequency
        interval = rule.interval
        selectedDays = rule.daysOfWeek
        dayOfMonth = rule.dayOfMonth ?? 1
        endType = .never
    }

    private func isPresetSelected(_ preset: RecurrenceRule) -> Bool {
        guard isEnabled else { return false }
        return frequency == preset.frequency
            && interval == preset.interval
            && selectedDays == preset.daysOfWeek
            && endType == .never
    }

    private func buildRule() -> RecurrenceRule {
        let end: RecurrenceEnd
        switch endType {
        case .never: end = .never
        case .afterCount: end = .afterOccurrences(endOccurrences)
        case .onDate: end = .onDate(endDate)
        }

        return RecurrenceRule(
            frequency: frequency,
            interval: interval,
            daysOfWeek: frequency == .weekly ? selectedDays : [],
            dayOfMonth: frequency == .monthly ? dayOfMonth : nil,
            end: end,
            occurrenceCount: recurrenceRule?.occurrenceCount ?? 0
        )
    }

    private func saveAndDismiss() {
        recurrenceRule = isEnabled ? buildRule() : nil
        dismiss()
    }
}

// MARK: - Day Toggle Button

struct DayToggleButton: View {
    let day: RecurrenceDay
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            Text(day.singleLetter)
                .font(.caption)
                .fontWeight(.semibold)
                .frame(width: 32, height: 32)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.2))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.shortName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Compact Recurrence Badge

/// Small badge showing recurrence info on task rows
struct RecurrenceBadge: View {
    let rule: RecurrenceRule

    var body: some View {
        Label {
            Text(rule.shortText)
                .font(.caption2)
                .fontWeight(.medium)
        } icon: {
            Image(systemName: "repeat")
                .font(.caption2)
        }
        .foregroundStyle(.blue)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.blue.opacity(0.1))
        .clipShape(Capsule())
    }
}

// MARK: - Preview

#Preview("Recurrence Picker") {
    RecurrencePickerSheet(recurrenceRule: .constant(.weekly))
}

#Preview("Recurrence Badge") {
    VStack(spacing: 8) {
        RecurrenceBadge(rule: .daily)
        RecurrenceBadge(rule: .weekdays)
        RecurrenceBadge(rule: .weekly)
        RecurrenceBadge(rule: .biweekly)
        RecurrenceBadge(rule: .monthly)
        RecurrenceBadge(rule: .yearly)
    }
    .padding()
}
