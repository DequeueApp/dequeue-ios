//
//  FocusTimerView.swift
//  Dequeue
//
//  Pomodoro-style focus timer UI with circular progress,
//  phase indicators, and session history.
//

import SwiftUI

// MARK: - Focus Timer View

/// Full-screen focus timer view with circular countdown,
/// phase controls, and today's session summary.
struct FocusTimerView: View {
    @StateObject private var timerService = FocusTimerService()
    @State private var showSettings = false
    @State private var showHistory = false

    let taskId: String?
    let taskTitle: String?
    let onDismiss: () -> Void

    init(
        taskId: String? = nil,
        taskTitle: String? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.taskId = taskId
        self.taskTitle = taskTitle
        self.onDismiss = onDismiss
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                    .ignoresSafeArea()

                VStack(spacing: 32) {
                    phaseIndicator
                    timerCircle
                    taskInfo
                    controls
                    sessionSummary
                }
                .padding()
            }
            .navigationTitle("Focus Timer")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        if timerService.isActive {
                            timerService.stop()
                        }
                        onDismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showSettings = true
                        } label: {
                            Label("Settings", systemImage: "gear")
                        }
                        Button {
                            showHistory = true
                        } label: {
                            Label("History", systemImage: "clock.arrow.circlepath")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                FocusTimerSettingsView(config: $timerService.config)
            }
            .sheet(isPresented: $showHistory) {
                FocusTimerHistoryView(sessions: timerService.todaySessions)
            }
            .onAppear {
                if timerService.state == .idle {
                    timerService.start(taskId: taskId, taskTitle: taskTitle)
                }
            }
        }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: phaseColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .opacity(0.1)
        .animation(.easeInOut(duration: 0.5), value: timerService.phase)
    }

    private var phaseColors: [Color] {
        switch timerService.phase {
        case .work: return [.red, .orange]
        case .shortBreak: return [.green, .teal]
        case .longBreak: return [.blue, .purple]
        }
    }

    // MARK: - Phase Indicator

    private var phaseIndicator: some View {
        HStack(spacing: 16) {
            ForEach(0..<timerService.config.sessionsBeforeLongBreak, id: \.self) { index in
                Circle()
                    .fill(index < timerService.completedSessions ? phaseAccentColor : Color.secondary.opacity(0.3))
                    .frame(width: 12, height: 12)
                    .overlay {
                        if index == timerService.completedSessions && timerService.phase == .work {
                            Circle()
                                .stroke(phaseAccentColor, lineWidth: 2)
                                .frame(width: 18, height: 18)
                        }
                    }
            }
        }
        .accessibilityLabel("Session \(timerService.completedSessions + 1) of \(timerService.config.sessionsBeforeLongBreak)")
    }

    // MARK: - Timer Circle

    private var timerCircle: some View {
        ZStack {
            // Background circle
            Circle()
                .stroke(Color.secondary.opacity(0.2), lineWidth: 12)
                .frame(width: 250, height: 250)

            // Progress circle
            Circle()
                .trim(from: 0, to: timerService.progress)
                .stroke(
                    phaseAccentColor,
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .frame(width: 250, height: 250)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: timerService.progress)

            // Time display
            VStack(spacing: 8) {
                Text(timerService.formattedTimeRemaining)
                    .font(.system(size: 56, weight: .light, design: .monospaced))
                    .monospacedDigit()
                    .contentTransition(.numericText())

                HStack(spacing: 4) {
                    Image(systemName: timerService.phase.icon)
                        .font(.caption)
                    Text(timerService.phase.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundStyle(phaseAccentColor)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(timerService.phase.displayName), \(timerService.formattedTimeRemaining) remaining")
        .accessibilityValue("\(Int(timerService.progress * 100)) percent complete")
    }

    // MARK: - Task Info

    @ViewBuilder
    private var taskInfo: some View {
        if let title = timerService.activeTaskTitle {
            VStack(spacing: 4) {
                Text("Working on")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 24) {
            switch timerService.state {
            case .idle:
                startButton
            case .running:
                pauseButton
                skipButton
            case .paused:
                resumeButton
                stopButton
            case .completed:
                nextPhaseButton
                stopButton
            }
        }
    }

    private var startButton: some View {
        timerButton("Start Focus", icon: "play.fill", color: phaseAccentColor) {
            timerService.start(taskId: taskId, taskTitle: taskTitle)
        }
    }

    private var pauseButton: some View {
        timerButton("Pause", icon: "pause.fill", color: .secondary) {
            timerService.pause()
        }
    }

    private var resumeButton: some View {
        timerButton("Resume", icon: "play.fill", color: phaseAccentColor) {
            timerService.resume()
        }
    }

    private var skipButton: some View {
        timerButton("Skip", icon: "forward.fill", color: .secondary) {
            timerService.skip()
        }
    }

    private var stopButton: some View {
        timerButton("Stop", icon: "stop.fill", color: .red) {
            timerService.stop()
        }
    }

    private var nextPhaseButton: some View {
        timerButton("Continue", icon: "arrow.right", color: phaseAccentColor) {
            timerService.startNextPhase()
        }
    }

    private func timerButton(_ label: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title2)
                    .frame(width: 56, height: 56)
                    .background(color.opacity(0.15))
                    .foregroundStyle(color)
                    .clipShape(Circle())

                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: - Session Summary

    private var sessionSummary: some View {
        HStack(spacing: 24) {
            summaryItem(
                title: "Sessions",
                value: "\(timerService.todaySessions.filter { $0.phase == .work && !$0.wasInterrupted }.count)",
                icon: "checkmark.circle"
            )
            summaryItem(
                title: "Focus Time",
                value: formatFocusTime(timerService.todayFocusTime),
                icon: "clock"
            )
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }

    private func summaryItem(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(title)
                    .font(.caption)
            }
            .foregroundStyle(.secondary)

            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Helpers

    private var phaseAccentColor: Color {
        switch timerService.phase {
        case .work: return .red
        case .shortBreak: return .green
        case .longBreak: return .blue
        }
    }

    private func formatFocusTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - Compact Timer View (for embedding in task views)

/// A compact timer bar that can be embedded in task views or the navigation bar.
struct CompactFocusTimerView: View {
    @ObservedObject var timerService: FocusTimerService

    var body: some View {
        if timerService.isActive {
            HStack(spacing: 8) {
                Circle()
                    .fill(timerService.state == .running ? Color.red : Color.orange)
                    .frame(width: 8, height: 8)
                    .modifier(PulseModifier(isAnimating: timerService.state == .running))

                Text(timerService.formattedTimeRemaining)
                    .font(.caption)
                    .fontWeight(.medium)
                    .monospacedDigit()

                Text(timerService.phase.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(timerService.phase.displayName), \(timerService.formattedTimeRemaining) remaining")
        }
    }
}

private struct PulseModifier: ViewModifier {
    let isAnimating: Bool
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPulsing ? 1.3 : 1.0)
            .opacity(isPulsing ? 0.7 : 1.0)
            .animation(
                isAnimating
                    ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true)
                    : .default,
                value: isPulsing
            )
            .onChange(of: isAnimating) { _, newValue in
                isPulsing = newValue
            }
            .onAppear {
                isPulsing = isAnimating
            }
    }
}

// MARK: - Settings View

struct FocusTimerSettingsView: View {
    @Binding var config: FocusTimerConfig
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Presets") {
                    presetButton("Classic Pomodoro", subtitle: "25 min work, 5 min break", config: .pomodoro)
                    presetButton("Short Sprints", subtitle: "15 min work, 3 min break", config: .shortSprints)
                    presetButton("Deep Work", subtitle: "50 min work, 10 min break", config: .deepWork)
                }

                Section("Work Session") {
                    durationPicker("Duration", value: $config.workDuration, range: 5...120)
                }

                Section("Breaks") {
                    durationPicker("Short Break", value: $config.shortBreakDuration, range: 1...30)
                    durationPicker("Long Break", value: $config.longBreakDuration, range: 5...60)
                    Stepper(
                        "Sessions before long break: \(config.sessionsBeforeLongBreak)",
                        value: $config.sessionsBeforeLongBreak,
                        in: 2...8
                    )
                }

                Section("Automation") {
                    Toggle("Auto-start breaks", isOn: $config.autoStartBreaks)
                    Toggle("Auto-start work after break", isOn: $config.autoStartWork)
                    Toggle("Notification on completion", isOn: $config.notifyOnComplete)
                }
            }
            .navigationTitle("Timer Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func presetButton(_ name: String, subtitle: String, config preset: FocusTimerConfig) -> some View {
        Button {
            config = preset
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func durationPicker(_ label: String, value: Binding<TimeInterval>, range: ClosedRange<Int>) -> some View {
        let minutes = Binding<Int>(
            get: { Int(value.wrappedValue / 60) },
            set: { value.wrappedValue = TimeInterval($0 * 60) }
        )

        return Stepper("\(label): \(minutes.wrappedValue) min", value: minutes, in: range)
    }
}

// MARK: - History View

struct FocusTimerHistoryView: View {
    let sessions: [FocusSessionRecord]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if sessions.isEmpty {
                    ContentUnavailableView {
                        Label("No Sessions Today", systemImage: "clock")
                    } description: {
                        Text("Start a focus session to see your history here.")
                    }
                } else {
                    Section("Today's Sessions") {
                        ForEach(sessions.filter { $0.phase == .work }) { session in
                            sessionRow(session)
                        }
                    }

                    Section {
                        HStack {
                            Text("Total Focus Time")
                                .fontWeight(.medium)
                            Spacer()
                            Text(formatDuration(totalFocusTime))
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Completed Sessions")
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(completedCount)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Session History")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func sessionRow(_ session: FocusSessionRecord) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.taskTitle ?? "Untitled Task")
                    .fontWeight(.medium)
                Text(session.completedAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 4) {
                if session.wasInterrupted {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Text(formatDuration(session.duration))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var totalFocusTime: TimeInterval {
        sessions
            .filter { $0.phase == .work && !$0.wasInterrupted }
            .reduce(0) { $0 + $1.duration }
    }

    private var completedCount: Int {
        sessions.filter { $0.phase == .work && !$0.wasInterrupted }.count
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(mins)m \(secs)s"
    }
}

// MARK: - Preview

#Preview("Focus Timer") {
    FocusTimerView(
        taskId: "test-123",
        taskTitle: "Review pull request",
        onDismiss: {}
    )
}

#Preview("Compact Timer") {
    CompactFocusTimerView(timerService: FocusTimerService())
}
