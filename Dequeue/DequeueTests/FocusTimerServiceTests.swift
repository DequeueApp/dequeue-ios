//
//  FocusTimerServiceTests.swift
//  DequeueTests
//
//  Tests for the Pomodoro-style focus timer service.
//

import XCTest
@testable import Dequeue

@MainActor
final class FocusTimerServiceTests: XCTestCase {

    private var service: FocusTimerService!
    private var userDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        // Use a unique suite to avoid interfering with real data
        suiteName = "FocusTimerTests-\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)!
        service = FocusTimerService(userDefaults: userDefaults)
    }

    override func tearDown() {
        service.stop()
        userDefaults.removePersistentDomain(forName: suiteName)
        service = nil
        userDefaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialState() {
        XCTAssertEqual(service.state, .idle)
        XCTAssertEqual(service.phase, .work)
        XCTAssertEqual(service.timeRemaining, 0)
        XCTAssertEqual(service.completedSessions, 0)
        XCTAssertNil(service.activeTaskId)
        XCTAssertNil(service.activeTaskTitle)
        XCTAssertFalse(service.isActive)
    }

    // MARK: - Start

    func testStartSetsWorkPhase() {
        service.start(taskId: "task-1", taskTitle: "Test Task")

        XCTAssertEqual(service.state, .running)
        XCTAssertEqual(service.phase, .work)
        XCTAssertEqual(service.activeTaskId, "task-1")
        XCTAssertEqual(service.activeTaskTitle, "Test Task")
        XCTAssertTrue(service.isActive)
    }

    func testStartSetsDefaultDuration() {
        service.start()

        XCTAssertEqual(service.totalDuration, 25 * 60) // 25 minutes default
        XCTAssertEqual(service.timeRemaining, 25 * 60)
    }

    func testStartWithCustomConfig() {
        service.config = .shortSprints
        service.start()

        XCTAssertEqual(service.totalDuration, 15 * 60) // 15 minutes
    }

    func testStartWithoutTaskInfo() {
        service.start()

        XCTAssertEqual(service.state, .running)
        XCTAssertNil(service.activeTaskId)
        XCTAssertNil(service.activeTaskTitle)
    }

    // MARK: - Pause / Resume

    func testPause() {
        service.start()
        service.pause()

        XCTAssertEqual(service.state, .paused)
        XCTAssertTrue(service.isActive) // Still "active" when paused
    }

    func testPauseWhenNotRunningDoesNothing() {
        service.pause() // idle state

        XCTAssertEqual(service.state, .idle)
    }

    func testResume() {
        service.start()
        let timeAtPause = service.timeRemaining
        service.pause()
        service.resume()

        XCTAssertEqual(service.state, .running)
        // Time remaining should be close to what it was at pause
        XCTAssertEqual(service.timeRemaining, timeAtPause, accuracy: 2)
    }

    func testResumeWhenNotPausedDoesNothing() {
        service.start()
        let stateBefore = service.state
        service.resume() // Already running

        XCTAssertEqual(service.state, stateBefore)
    }

    // MARK: - Stop

    func testStop() {
        service.start(taskId: "task-1", taskTitle: "Test")
        service.stop()

        XCTAssertEqual(service.state, .idle)
        XCTAssertEqual(service.phase, .work)
        XCTAssertEqual(service.timeRemaining, 0)
        XCTAssertEqual(service.totalDuration, 0)
        XCTAssertNil(service.activeTaskId)
        XCTAssertNil(service.activeTaskTitle)
        XCTAssertFalse(service.isActive)
    }

    func testStopRecordsInterruptedSession() {
        service.start(taskId: "task-1", taskTitle: "Test")
        service.stop()

        // Should have recorded an interrupted session
        XCTAssertEqual(service.todaySessions.count, 1)
        XCTAssertTrue(service.todaySessions.first!.wasInterrupted)
    }

    // MARK: - Skip

    func testSkipFromWork() {
        service.start()
        XCTAssertEqual(service.phase, .work)

        service.skip()

        // Should move to short break
        XCTAssertEqual(service.phase, .shortBreak)
        XCTAssertEqual(service.state, .running)
    }

    func testSkipFromShortBreak() {
        service.start()
        service.skip() // work → short break
        XCTAssertEqual(service.phase, .shortBreak)

        service.skip() // short break → work

        XCTAssertEqual(service.phase, .work)
        XCTAssertEqual(service.state, .running)
    }

    func testSkipRecordsInterruptedWorkSession() {
        service.start()
        service.skip()

        // Should record the interrupted work session
        let workSessions = service.todaySessions.filter { $0.phase == .work }
        XCTAssertEqual(workSessions.count, 1)
        XCTAssertTrue(workSessions.first!.wasInterrupted)
    }

    // MARK: - Progress

    func testProgressInitiallyZero() {
        XCTAssertEqual(service.progress, 0)
    }

    func testProgressAfterStart() {
        service.start()
        // Just started, progress should be 0 (or very close)
        XCTAssertEqual(service.progress, 0, accuracy: 0.01)
    }

    // MARK: - Formatted Time

    func testFormattedTimeRemaining() {
        service.start()
        // Default 25 min = "25:00"
        XCTAssertEqual(service.formattedTimeRemaining, "25:00")
    }

    // MARK: - Config

    func testDefaultConfig() {
        let config = FocusTimerConfig.default
        XCTAssertEqual(config.workDuration, 25 * 60)
        XCTAssertEqual(config.shortBreakDuration, 5 * 60)
        XCTAssertEqual(config.longBreakDuration, 15 * 60)
        XCTAssertEqual(config.sessionsBeforeLongBreak, 4)
        XCTAssertFalse(config.autoStartBreaks)
        XCTAssertFalse(config.autoStartWork)
        XCTAssertTrue(config.notifyOnComplete)
    }

    func testShortSprintsConfig() {
        let config = FocusTimerConfig.shortSprints
        XCTAssertEqual(config.workDuration, 15 * 60)
        XCTAssertEqual(config.shortBreakDuration, 3 * 60)
    }

    func testDeepWorkConfig() {
        let config = FocusTimerConfig.deepWork
        XCTAssertEqual(config.workDuration, 50 * 60)
        XCTAssertEqual(config.shortBreakDuration, 10 * 60)
        XCTAssertEqual(config.longBreakDuration, 30 * 60)
        XCTAssertEqual(config.sessionsBeforeLongBreak, 2)
    }

    func testConfigPersistence() {
        service.config = .deepWork

        // Create a new service with the same UserDefaults
        let service2 = FocusTimerService(userDefaults: userDefaults)
        XCTAssertEqual(service2.config.workDuration, 50 * 60)
    }

    // MARK: - Timer Phase

    func testTimerPhaseDisplayNames() {
        XCTAssertEqual(TimerPhase.work.displayName, "Focus")
        XCTAssertEqual(TimerPhase.shortBreak.displayName, "Short Break")
        XCTAssertEqual(TimerPhase.longBreak.displayName, "Long Break")
    }

    func testTimerPhaseIcons() {
        XCTAssertEqual(TimerPhase.work.icon, "brain.head.profile")
        XCTAssertEqual(TimerPhase.shortBreak.icon, "cup.and.saucer")
        XCTAssertEqual(TimerPhase.longBreak.icon, "figure.walk")
    }

    // MARK: - Timer State

    func testTimerStateEquality() {
        XCTAssertEqual(TimerState.idle, TimerState.idle)
        XCTAssertEqual(TimerState.running, TimerState.running)
        XCTAssertNotEqual(TimerState.idle, TimerState.running)
    }

    // MARK: - Session Record

    func testFocusSessionRecord() {
        let record = FocusSessionRecord(
            id: "test-id",
            taskId: "task-1",
            taskTitle: "Test Task",
            stackId: nil,
            phase: .work,
            duration: 25 * 60,
            completedAt: Date(),
            wasInterrupted: false
        )

        XCTAssertEqual(record.id, "test-id")
        XCTAssertEqual(record.taskId, "task-1")
        XCTAssertEqual(record.taskTitle, "Test Task")
        XCTAssertEqual(record.phase, .work)
        XCTAssertEqual(record.duration, 25 * 60)
        XCTAssertFalse(record.wasInterrupted)
    }

    // MARK: - Today Focus Time

    func testTodayFocusTimeInitiallyZero() {
        XCTAssertEqual(service.todayFocusTime, 0)
    }

    func testTodaySessionsInitiallyEmpty() {
        XCTAssertTrue(service.todaySessions.isEmpty)
    }

    // MARK: - Phase Cycling

    func testCompletedSessionsInitiallyZero() {
        XCTAssertEqual(service.completedSessions, 0)
    }

    func testMultipleStartStopCycles() {
        // Start, stop, start again — should reset properly
        service.start(taskId: "task-1", taskTitle: "First")
        service.stop()

        service.start(taskId: "task-2", taskTitle: "Second")
        XCTAssertEqual(service.activeTaskId, "task-2")
        XCTAssertEqual(service.activeTaskTitle, "Second")
        XCTAssertEqual(service.state, .running)
    }

    func testPauseResumePreservesTaskInfo() {
        service.start(taskId: "task-1", taskTitle: "Test Task")
        service.pause()

        XCTAssertEqual(service.activeTaskId, "task-1")
        XCTAssertEqual(service.activeTaskTitle, "Test Task")

        service.resume()

        XCTAssertEqual(service.activeTaskId, "task-1")
        XCTAssertEqual(service.activeTaskTitle, "Test Task")
    }
}
