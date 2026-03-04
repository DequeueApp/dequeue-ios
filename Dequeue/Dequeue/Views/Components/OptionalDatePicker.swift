//
//  OptionalDatePicker.swift
//  Dequeue
//
//  A date picker that properly handles optional dates.
//  Shows "Not set" with an add button when nil, and a DatePicker with clear when set.
//

import SwiftUI

struct OptionalDatePicker: View {
    let label: String
    let icon: String
    @Binding var date: Date?
    var displayedComponents: DatePickerComponents = [.date, .hourAndMinute]

    var body: some View {
        if let currentDate = date {
            // Date is set — show DatePicker with clear action
            DatePicker(
                label,
                selection: Binding(
                    get: { currentDate },
                    set: { date = $0 }
                ),
                displayedComponents: displayedComponents
            )
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    withAnimation {
                        date = nil
                    }
                } label: {
                    Label("Clear", systemImage: "xmark")
                }
            }
        } else {
            // Date is nil — show "Not set" with add button
            Button {
                withAnimation {
                    date = Date()
                }
            } label: {
                HStack {
                    Label(label, systemImage: icon)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text("Not set")
                        .foregroundStyle(.secondary)
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.blue)
                        .imageScale(.medium)
                }
            }
        }
    }
}

#Preview("Not Set") {
    List {
        Section("Dates") {
            OptionalDatePicker(
                label: "Start Date",
                icon: "calendar.badge.clock",
                date: .constant(nil)
            )
            OptionalDatePicker(
                label: "Due Date",
                icon: "calendar.badge.exclamationmark",
                date: .constant(nil)
            )
        }
    }
}

#Preview("Set") {
    List {
        Section("Dates") {
            OptionalDatePicker(
                label: "Start Date",
                icon: "calendar.badge.clock",
                date: .constant(Date())
            )
            OptionalDatePicker(
                label: "Due Date",
                icon: "calendar.badge.exclamationmark",
                date: .constant(Date())
            )
        }
    }
}
