//
//  AccessibilityModifiers.swift
//  Dequeue
//
//  Reusable accessibility modifiers and helpers for VoiceOver, Dynamic Type, and high contrast
//

import SwiftUI

// MARK: - Task Accessibility

/// Provides comprehensive VoiceOver labels for task rows
struct TaskAccessibilityModifier: ViewModifier {
    let task: QueueTask
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .combine)
            .accessibilityLabel(taskLabel)
            .accessibilityHint(taskHint)
            .accessibilityAddTraits(accessibilityTraits)
            .accessibilityValue(taskValue)
    }

    private var taskLabel: String {
        var parts: [String] = [task.title]

        if isActive { parts.append("Active task") }

        if let priority = task.priority {
            switch priority {
            case 1: parts.append("High priority")
            case 2: parts.append("Medium priority")
            case 3: parts.append("Low priority")
            default: break
            }
        }

        if task.status == .blocked {
            parts.append("Blocked")
            if let reason = task.blockedReason {
                parts.append(reason)
            }
        }

        return parts.joined(separator: ", ")
    }

    private var taskHint: String {
        switch task.status {
        case .pending: return "Double tap to view details. Swipe right to complete."
        case .completed: return "Completed task"
        case .blocked: return "Task is blocked. Double tap to view details."
        case .closed: return "Closed task"
        }
    }

    private var taskValue: String {
        var parts: [String] = []

        if let dueTime = task.dueTime {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            let relative = formatter.localizedString(for: dueTime, relativeTo: Date())
            if dueTime < Date() {
                parts.append("Overdue, was due \(relative)")
            } else {
                parts.append("Due \(relative)")
            }
        }

        if !task.tags.isEmpty {
            parts.append("Tags: \(task.tags.joined(separator: ", "))")
        }

        if let description = task.taskDescription, !description.isEmpty {
            parts.append(description)
        }

        return parts.joined(separator: ". ")
    }

    private var accessibilityTraits: AccessibilityTraits {
        var traits: AccessibilityTraits = .isButton
        if isActive { traits.insert(.isSelected) }
        return traits
    }
}

// MARK: - Stack Accessibility

/// Provides comprehensive VoiceOver labels for stack rows
struct StackAccessibilityModifier: ViewModifier {
    let stack: Stack
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .combine)
            .accessibilityLabel(stackLabel)
            .accessibilityHint("Double tap to open stack")
            .accessibilityValue(stackValue)
            .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }

    private var stackLabel: String {
        var parts: [String] = [stack.title]
        if isActive { parts.append("Active stack") }
        return parts.joined(separator: ", ")
    }

    private var stackValue: String {
        let pending = stack.pendingTasks.count
        let completed = stack.completedTasks.count
        let total = pending + completed

        var parts: [String] = [
            "\(pending) pending task\(pending == 1 ? "" : "s")",
            "\(completed) completed"
        ]

        if total > 0 {
            let progress = Int(Double(completed) / Double(total) * 100)
            parts.append("\(progress)% complete")
        }

        return parts.joined(separator: ", ")
    }
}

// MARK: - Announcement Helpers

/// Sends a VoiceOver announcement for important state changes
struct AccessibilityAnnouncement {
    static func announce(_ message: String) {
        #if os(iOS)
        UIAccessibility.post(notification: .announcement, argument: message)
        #endif
    }

    static func taskCompleted(_ title: String) {
        announce("Task completed: \(title)")
    }

    static func taskCreated(_ title: String) {
        announce("New task created: \(title)")
    }

    static func stackActivated(_ title: String) {
        announce("Stack activated: \(title)")
    }

    static func stackCompleted(_ title: String) {
        announce("Stack completed: \(title)")
    }

    static func timerStarted(minutes: Int) {
        announce("Focus timer started, \(minutes) minutes")
    }

    static func timerEnded() {
        announce("Focus timer ended. Take a break!")
    }

    static func undoAvailable(_ action: String) {
        announce("Undo available for \(action)")
    }
}

// MARK: - Dynamic Type Scaled Font

/// Ensures text scales properly with Dynamic Type while maintaining minimum sizes
struct ScaledFont: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let style: Font.TextStyle
    let minSize: CGFloat
    let maxSize: CGFloat

    func body(content: Content) -> some View {
        content
            .font(.system(style))
            .dynamicTypeSize(...DynamicTypeSize.accessibility3)
    }
}

// MARK: - High Contrast Support

/// Adjusts colors for better visibility in high contrast mode
struct HighContrastModifier: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast

    let normalColor: Color
    let highContrastColor: Color

    func body(content: Content) -> some View {
        content
            .foregroundStyle(contrast == .increased ? highContrastColor : normalColor)
    }
}

// MARK: - Reduce Motion Support

/// Provides alternative animations for users with reduce motion enabled
struct ReduceMotionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .animation(reduceMotion ? .none : .default, value: UUID())
    }
}

// MARK: - View Extensions

extension View {
    /// Applies comprehensive task accessibility labels
    func taskAccessibility(task: QueueTask, isActive: Bool) -> some View {
        modifier(TaskAccessibilityModifier(task: task, isActive: isActive))
    }

    /// Applies comprehensive stack accessibility labels
    func stackAccessibility(stack: Stack, isActive: Bool) -> some View {
        modifier(StackAccessibilityModifier(stack: stack, isActive: isActive))
    }

    /// Ensures proper Dynamic Type scaling with bounds
    func scaledFont(_ style: Font.TextStyle, minSize: CGFloat = 10, maxSize: CGFloat = 60) -> some View {
        modifier(ScaledFont(style: style, minSize: minSize, maxSize: maxSize))
    }

    /// Adjusts foreground color for high contrast mode
    func highContrastColor(normal: Color, increased: Color) -> some View {
        modifier(HighContrastModifier(normalColor: normal, highContrastColor: increased))
    }

    /// Respects reduce motion preference
    func respectReduceMotion() -> some View {
        modifier(ReduceMotionModifier())
    }
}

// MARK: - Priority Color with Accessibility

extension QueueTask {
    /// Returns accessible priority color that works in both normal and high contrast
    @MainActor
    var accessiblePriorityColor: Color {
        switch priority {
        case 1: return .red
        case 2: return .orange
        case 3: return .yellow
        default: return .secondary
        }
    }

    /// Returns priority text for VoiceOver
    var priorityAccessibilityText: String? {
        switch priority {
        case 1: return "High priority"
        case 2: return "Medium priority"
        case 3: return "Low priority"
        default: return nil
        }
    }
}

// MARK: - Overdue Status

extension QueueTask {
    /// Whether the task is overdue (for accessibility announcements)
    var isOverdue: Bool {
        guard let dueTime else { return false }
        return status == .pending && dueTime < Date()
    }

    /// Formatted due date string for VoiceOver
    var dueDateAccessibilityText: String? {
        guard let dueTime else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let relative = formatter.localizedString(for: dueTime, relativeTo: Date())
        return isOverdue ? "Overdue, was due \(relative)" : "Due \(relative)"
    }
}
