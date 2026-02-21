//
//  SmartTaskInputView.swift
//  Dequeue
//
//  Smart task input with real-time natural language parsing preview.
//  Shows parsed date, priority, and tags as the user types.
//

import SwiftUI

// MARK: - Smart Task Input View

/// A text input view with real-time natural language parsing.
///
/// As the user types, the parser extracts dates, priorities, and tags
/// from the input, showing a live preview of structured data below the text field.
///
/// Usage:
/// ```swift
/// SmartTaskInputView { result in
///     // result.title, result.dueTime, result.priority, result.tags
/// }
/// ```
struct SmartTaskInputView: View {
    @State private var inputText = ""
    @State private var parseResult: NLTaskParseResult?
    @FocusState private var isInputFocused: Bool

    let onSubmit: (NLTaskParseResult) -> Void
    let onCancel: (() -> Void)?

    init(
        onSubmit: @escaping (NLTaskParseResult) -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self.onSubmit = onSubmit
        self.onCancel = onCancel
    }

    private let parser = NLTaskParser()

    var body: some View {
        VStack(spacing: 0) {
            inputField
            if let result = parseResult, result.hasStructuredData {
                parsePreview(result)
            }
        }
    }

    // MARK: - Input Field

    private var inputField: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus.circle.fill")
                .font(.title2)
                .foregroundStyle(.blue)

            TextField("Add task... (try \"Buy milk tomorrow at 3pm #errands\")", text: $inputText)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($isInputFocused)
                .submitLabel(.done)
                .onSubmit(handleSubmit)
                .onChange(of: inputText) { _, newValue in
                    updateParse(newValue)
                }
                .accessibilityLabel("Smart task input")
                .accessibilityHint("Type a task with natural language dates, tags, and priority")

            if !inputText.isEmpty {
                Button(action: handleSubmit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }
                .accessibilityLabel("Add task")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                #if os(iOS)
                .fill(Color(.secondarySystemGroupedBackground))
                #else
                .fill(Color(.windowBackgroundColor).opacity(0.5))
                #endif
        )
    }

    // MARK: - Parse Preview

    private func parsePreview(_ result: NLTaskParseResult) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Title preview
                if !result.title.isEmpty && result.title != inputText {
                    previewChip(
                        icon: "textformat",
                        text: result.title,
                        color: .secondary
                    )
                }

                // Due date
                if let dueTime = result.dueTime {
                    previewChip(
                        icon: "calendar",
                        text: formatDate(dueTime),
                        color: .blue
                    )
                }

                // Start date
                if let startTime = result.startTime {
                    previewChip(
                        icon: "calendar.badge.clock",
                        text: "From: \(formatDate(startTime))",
                        color: .green
                    )
                }

                // Priority
                if let priority = result.priority {
                    previewChip(
                        icon: priorityIcon(priority),
                        text: priorityLabel(priority),
                        color: priorityColor(priority)
                    )
                }

                // Tags
                ForEach(result.tags, id: \.self) { tag in
                    previewChip(
                        icon: "tag",
                        text: tag,
                        color: .purple
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.easeInOut(duration: 0.2), value: result.hasStructuredData)
    }

    private func previewChip(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }

    // MARK: - Actions

    private func updateParse(_ text: String) {
        if text.isEmpty {
            parseResult = nil
        } else {
            parseResult = parser.parse(text)
        }
    }

    private func handleSubmit() {
        let result = parser.parse(inputText)
        guard !result.title.isEmpty else { return }
        onSubmit(result)
        inputText = ""
        parseResult = nil
    }

    // MARK: - Formatting Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            formatter.dateFormat = "'Today' h:mm a"
        } else if calendar.isDateInTomorrow(date) {
            formatter.dateFormat = "'Tomorrow' h:mm a"
        } else if let daysUntil = calendar.dateComponents([.day], from: Date(), to: date).day,
                  daysUntil < 7 {
            formatter.dateFormat = "EEEE h:mm a"
        } else {
            formatter.dateFormat = "MMM d, h:mm a"
        }

        return formatter.string(from: date)
    }

    private func priorityIcon(_ priority: Int) -> String {
        switch priority {
        case 3: return "exclamationmark.3"
        case 2: return "exclamationmark.2"
        case 1: return "exclamationmark"
        default: return "arrow.down"
        }
    }

    private func priorityLabel(_ priority: Int) -> String {
        switch priority {
        case 3: return "Urgent"
        case 2: return "High"
        case 1: return "Medium"
        case 0: return "Low"
        default: return "None"
        }
    }

    private func priorityColor(_ priority: Int) -> Color {
        switch priority {
        case 3: return .red
        case 2: return .orange
        case 1: return .yellow
        case 0: return .gray
        default: return .secondary
        }
    }
}

// MARK: - Preview

#Preview {
    VStack {
        SmartTaskInputView { result in
            print("Title: \(result.title)")
            print("Due: \(String(describing: result.dueTime))")
            print("Priority: \(String(describing: result.priority))")
            print("Tags: \(result.tags)")
        }
        .padding()

        Spacer()
    }
}
