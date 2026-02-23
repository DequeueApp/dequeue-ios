//
//  FocusTimerService.swift
//  Dequeue
//
//  Pomodoro-style focus timer tied to the active task.
//  Supports work sessions, short breaks, and long breaks with
//  configurable durations and auto-progression.
//

import Foundation
import Combine
import UserNotifications
import os.log

nonisolated private let logger = Logger(subsystem: "com.dequeue", category: "FocusTimer")

// MARK: - Timer Phase

/// Represents the current phase of the focus timer cycle.
enum TimerPhase: String, Codable, Sendable, Equatable {
    /// Active work session
    case work
    /// Short break between work sessions
    case shortBreak
    /// Long break after completing a full cycle
    case longBreak

    var displayName: String {
        switch self {
        case .work: return "Focus"
        case .shortBreak: return "Short Break"
        case .longBreak: return "Long Break"
        }
    }

    var icon: String {
        switch self {
        case .work: return "brain.head.profile"
        case .shortBreak: return "cup.and.saucer"
        case .longBreak: return "figure.walk"
        }
    }
}

// MARK: - Timer State

/// The current state of the focus timer.
enum TimerState: Equatable, Sendable {
    /// Timer is not running and not started
    case idle
    /// Timer is actively counting down
    case running
    /// Timer is paused mid-session
    case paused
    /// Current phase completed, waiting for user to proceed
    case completed
}

// MARK: - Timer Configuration

/// Configuration for focus timer durations (in seconds).
struct FocusTimerConfig: Codable, Equatable, Sendable {
    /// Duration of a work session (default: 25 minutes)
    var workDuration: TimeInterval
    /// Duration of a short break (default: 5 minutes)
    var shortBreakDuration: TimeInterval
    /// Duration of a long break (default: 15 minutes)
    var longBreakDuration: TimeInterval
    /// Number of work sessions before a long break (default: 4)
    var sessionsBeforeLongBreak: Int
    /// Whether to auto-start the next phase
    var autoStartBreaks: Bool
    /// Whether to auto-start work after breaks
    var autoStartWork: Bool
    /// Whether to send notifications when phases complete
    var notifyOnComplete: Bool

    static let `default` = FocusTimerConfig(
        workDuration: 25 * 60,
        shortBreakDuration: 5 * 60,
        longBreakDuration: 15 * 60,
        sessionsBeforeLongBreak: 4,
        autoStartBreaks: false,
        autoStartWork: false,
        notifyOnComplete: true
    )

    /// Preset configurations
    static let pomodoro = FocusTimerConfig.default

    static let shortSprints = FocusTimerConfig(
        workDuration: 15 * 60,
        shortBreakDuration: 3 * 60,
        longBreakDuration: 10 * 60,
        sessionsBeforeLongBreak: 4,
        autoStartBreaks: false,
        autoStartWork: false,
        notifyOnComplete: true
    )

    static let deepWork = FocusTimerConfig(
        workDuration: 50 * 60,
        shortBreakDuration: 10 * 60,
        longBreakDuration: 30 * 60,
        sessionsBeforeLongBreak: 2,
        autoStartBreaks: false,
        autoStartWork: false,
        notifyOnComplete: true
    )
}

// MARK: - Focus Session Record

/// A completed focus session for history/analytics.
struct FocusSessionRecord: Codable, Identifiable, Sendable {
    let id: String
    let taskId: String?
    let taskTitle: String?
    let stackId: String?
    let phase: TimerPhase
    let duration: TimeInterval
    let completedAt: Date
    let wasInterrupted: Bool
}

// MARK: - Focus Timer Service

/// Manages a Pomodoro-style focus timer with work/break cycles.
///
/// The timer runs independently and publishes state changes via `@Published` properties.
/// It integrates with the active task to track what was being worked on.
///
/// Usage:
/// ```swift
/// let timer = FocusTimerService()
/// timer.start(taskId: "abc", taskTitle: "Review PR")
/// // Timer counts down, publishes updates
/// timer.pause()
/// timer.resume()
/// timer.skip() // Skip to next phase
/// timer.stop() // Reset completely
/// ```
@MainActor
final class FocusTimerService: ObservableObject {
    // MARK: - Published State

    /// Current timer state
    @Published private(set) var state: TimerState = .idle

    /// Current phase (work, short break, long break)
    @Published private(set) var phase: TimerPhase = .work

    /// Time remaining in seconds
    @Published private(set) var timeRemaining: TimeInterval = 0

    /// Total duration of the current phase
    @Published private(set) var totalDuration: TimeInterval = 0

    /// Number of completed work sessions in the current cycle
    @Published private(set) var completedSessions: Int = 0

    /// Total focus time today (work sessions only)
    @Published private(set) var todayFocusTime: TimeInterval = 0

    /// Currently active task info
    @Published private(set) var activeTaskId: String?
    @Published private(set) var activeTaskTitle: String?

    // MARK: - Configuration

    /// Timer configuration
    var config: FocusTimerConfig {
        didSet {
            saveConfig()
        }
    }

    // MARK: - History

    /// Today's completed sessions
    @Published private(set) var todaySessions: [FocusSessionRecord] = []

    // MARK: - Private

    private var timer: Timer?
    private var phaseStartDate: Date?
    private var pausedTimeRemaining: TimeInterval?

    private let userDefaults: UserDefaults
    private let notificationCenter: UNUserNotificationCenter

    // MARK: - Init

    init(
        userDefaults: UserDefaults = .standard,
        notificationCenter: UNUserNotificationCenter = .current()
    ) {
        self.userDefaults = userDefaults
        self.notificationCenter = notificationCenter

        // Load saved config
        if let data = userDefaults.data(forKey: "focusTimerConfig"),
           let saved = try? JSONDecoder().decode(FocusTimerConfig.self, from: data) {
            self.config = saved
        } else {
            self.config = .default
        }

        // Load today's sessions
        loadTodaySessions()
        calculateTodayFocusTime()
    }

    // MARK: - Public API

    /// Start a new focus session.
    /// - Parameters:
    ///   - taskId: Optional ID of the task being worked on
    ///   - taskTitle: Optional title of the task
    func start(taskId: String? = nil, taskTitle: String? = nil) {
        activeTaskId = taskId
        activeTaskTitle = taskTitle
        phase = .work
        startPhase()
        logger.info("Focus timer started for task: \(taskTitle ?? "none")")
    }

    /// Pause the current timer.
    func pause() {
        guard state == .running else { return }
        timer?.invalidate()
        timer = nil
        pausedTimeRemaining = timeRemaining
        state = .paused
        logger.info("Focus timer paused at \(self.formatTime(self.timeRemaining))")
    }

    /// Resume a paused timer.
    func resume() {
        guard state == .paused, let remaining = pausedTimeRemaining else { return }
        timeRemaining = remaining
        pausedTimeRemaining = nil
        startCountdown()
        state = .running
        logger.info("Focus timer resumed with \(self.formatTime(self.timeRemaining)) remaining")
    }

    /// Skip the current phase and move to the next one.
    func skip() {
        let wasWork = phase == .work
        if wasWork && state == .running {
            // Record interrupted session
            recordSession(interrupted: true)
        }

        timer?.invalidate()
        timer = nil
        advancePhase()
    }

    /// Stop the timer completely and reset to idle.
    func stop() {
        if phase == .work && state == .running {
            // Record interrupted session
            recordSession(interrupted: true)
        }

        timer?.invalidate()
        timer = nil
        state = .idle
        phase = .work
        timeRemaining = 0
        totalDuration = 0
        pausedTimeRemaining = nil
        activeTaskId = nil
        activeTaskTitle = nil
        logger.info("Focus timer stopped")
    }

    /// Start the next phase after completion.
    func startNextPhase() {
        guard state == .completed else { return }
        advancePhase()
    }

    // MARK: - Computed Properties

    /// Progress from 0.0 to 1.0
    var progress: Double {
        guard totalDuration > 0 else { return 0 }
        return 1.0 - (timeRemaining / totalDuration)
    }

    /// Formatted time remaining (MM:SS)
    var formattedTimeRemaining: String {
        formatTime(timeRemaining)
    }

    /// Whether the timer is active (running or paused)
    var isActive: Bool {
        state == .running || state == .paused
    }

    // MARK: - Private Methods

    private func startPhase() {
        let duration = durationForPhase(phase)
        timeRemaining = duration
        totalDuration = duration
        phaseStartDate = Date()
        startCountdown()
        state = .running
    }

    private func startCountdown() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func tick() {
        guard state == .running else { return }

        timeRemaining -= 1

        if timeRemaining <= 0 {
            timeRemaining = 0
            timer?.invalidate()
            timer = nil
            phaseCompleted()
        }
    }

    private func phaseCompleted() {
        if phase == .work {
            recordSession(interrupted: false)
            completedSessions += 1
        }

        state = .completed

        // Send notification
        if config.notifyOnComplete {
            sendCompletionNotification()
        }

        // Auto-advance if configured
        let shouldAutoStart = phase == .work ? config.autoStartBreaks : config.autoStartWork
        if shouldAutoStart {
            advancePhase()
        }

        logger.info("Phase completed: \(self.phase.displayName), sessions: \(self.completedSessions)")
    }

    private func advancePhase() {
        switch phase {
        case .work:
            if completedSessions >= config.sessionsBeforeLongBreak {
                phase = .longBreak
                completedSessions = 0
            } else {
                phase = .shortBreak
            }
        case .shortBreak, .longBreak:
            phase = .work
        }
        startPhase()
    }

    private func durationForPhase(_ phase: TimerPhase) -> TimeInterval {
        switch phase {
        case .work: return config.workDuration
        case .shortBreak: return config.shortBreakDuration
        case .longBreak: return config.longBreakDuration
        }
    }

    // MARK: - Session Recording

    private func recordSession(interrupted: Bool) {
        let elapsed: TimeInterval
        if let start = phaseStartDate {
            elapsed = Date().timeIntervalSince(start)
        } else {
            elapsed = totalDuration - timeRemaining
        }

        let record = FocusSessionRecord(
            id: UUID().uuidString,
            taskId: activeTaskId,
            taskTitle: activeTaskTitle,
            stackId: nil,
            phase: phase,
            duration: elapsed,
            completedAt: Date(),
            wasInterrupted: interrupted
        )

        todaySessions.append(record)
        saveTodaySessions()
        calculateTodayFocusTime()
    }

    private func calculateTodayFocusTime() {
        todayFocusTime = todaySessions
            .filter { $0.phase == .work && !$0.wasInterrupted }
            .reduce(0) { $0 + $1.duration }
    }

    // MARK: - Notifications

    private func sendCompletionNotification() {
        let content = UNMutableNotificationContent()

        switch phase {
        case .work:
            content.title = "Focus Session Complete! 🎉"
            content.body = "Great work! Time for a \(nextPhaseIsLongBreak ? "long" : "short") break."
        case .shortBreak:
            content.title = "Break Over ☕"
            content.body = "Ready to get back to work?"
        case .longBreak:
            content.title = "Long Break Over 🏃"
            content.body = "Refreshed? Let's start a new cycle!"
        }

        content.sound = .default
        content.categoryIdentifier = "FOCUS_TIMER_CATEGORY"

        let request = UNNotificationRequest(
            identifier: "focus-timer-\(UUID().uuidString)",
            content: content,
            trigger: nil // Deliver immediately
        )

        notificationCenter.add(request) { error in
            if let error = error {
                logger.error("Failed to send timer notification: \(error.localizedDescription)")
            }
        }
    }

    private var nextPhaseIsLongBreak: Bool {
        completedSessions + 1 >= config.sessionsBeforeLongBreak
    }

    // MARK: - Persistence

    private func saveConfig() {
        if let data = try? JSONEncoder().encode(config) {
            userDefaults.set(data, forKey: "focusTimerConfig")
        }
    }

    private func saveTodaySessions() {
        if let data = try? JSONEncoder().encode(todaySessions) {
            userDefaults.set(data, forKey: "focusTimerSessions")
            userDefaults.set(Date(), forKey: "focusTimerSessionsDate")
        }
    }

    private func loadTodaySessions() {
        // Only load if from today
        if let date = userDefaults.object(forKey: "focusTimerSessionsDate") as? Date,
           Calendar.current.isDateInToday(date),
           let data = userDefaults.data(forKey: "focusTimerSessions"),
           let sessions = try? JSONDecoder().decode([FocusSessionRecord].self, from: data) {
            todaySessions = sessions
        } else {
            todaySessions = []
        }
    }

    // MARK: - Formatting

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
