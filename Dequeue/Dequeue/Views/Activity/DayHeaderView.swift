//
//  DayHeaderView.swift
//  Dequeue
//
//  Section header for a day in the activity timeline
//

import SwiftUI

struct DayHeaderView: View {
    let date: Date

    private var displayText: String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            return "TODAY"
        } else if calendar.isDateInYesterday(date) {
            return "YESTERDAY"
        } else {
            let formatter = DateFormatter()
            // Check if date is within the current week
            if calendar.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
                formatter.dateFormat = "EEEE"  // Day name only for this week
            } else {
                formatter.dateFormat = "EEEE, MMM d"  // Full format for older dates
            }
            return formatter.string(from: date).uppercased()
        }
    }

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    var body: some View {
        HStack {
            Text(displayText)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            Spacer()

            // Show date on the right for TODAY/YESTERDAY
            if Calendar.current.isDateInToday(date) || Calendar.current.isDateInYesterday(date) {
                Text(dateText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .textCase(nil)  // Prevent automatic uppercasing by List
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(displayText), \(dateText)")
    }
}

#Preview {
    List {
        Section {
            Text("Events")
        } header: {
            DayHeaderView(date: Date())
        }

        Section {
            Text("Events")
        } header: {
            DayHeaderView(date: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())
        }

        Section {
            Text("Events")
        } header: {
            DayHeaderView(date: Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date())
        }

        Section {
            Text("Events")
        } header: {
            DayHeaderView(date: Calendar.current.date(byAdding: .day, value: -10, to: Date()) ?? Date())
        }
    }
    .listStyle(.plain)
}
