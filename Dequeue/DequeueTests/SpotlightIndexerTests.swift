//
//  SpotlightIndexerTests.swift
//  DequeueTests
//
//  Tests for CoreSpotlight indexing
//

import Testing
import Foundation
import CoreSpotlight
@testable import Dequeue

@Suite("SpotlightIndexer")
struct SpotlightIndexerTests {

    // MARK: - Spotlight Activity Handling

    @Test("Handles Spotlight activity with valid stack identifier")
    func handlesStackActivity() throws {
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [
            CSSearchableItemActivityIdentifier: "dequeue://stack/stack-abc-123"
        ]

        let url = SpotlightIndexer.handleSpotlightActivity(activity)
        #expect(url != nil)
        #expect(url?.absoluteString == "dequeue://stack/stack-abc-123")
    }

    @Test("Handles Spotlight activity with valid task identifier")
    func handlesTaskActivity() throws {
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [
            CSSearchableItemActivityIdentifier: "dequeue://task/task-xyz-789"
        ]

        let url = SpotlightIndexer.handleSpotlightActivity(activity)
        #expect(url != nil)
        #expect(url?.absoluteString == "dequeue://task/task-xyz-789")
    }

    @Test("Returns nil for wrong activity type")
    func rejectsWrongActivityType() throws {
        let activity = NSUserActivity(activityType: "com.other.activity")
        activity.userInfo = [
            CSSearchableItemActivityIdentifier: "dequeue://stack/abc"
        ]

        let url = SpotlightIndexer.handleSpotlightActivity(activity)
        #expect(url == nil)
    }

    @Test("Returns nil for missing identifier")
    func rejectsMissingIdentifier() throws {
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [:]

        let url = SpotlightIndexer.handleSpotlightActivity(activity)
        #expect(url == nil)
    }

    @Test("Returns nil for nil userInfo")
    func rejectsNilUserInfo() throws {
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)

        let url = SpotlightIndexer.handleSpotlightActivity(activity)
        #expect(url == nil)
    }

    // MARK: - Singleton

    @MainActor
    @Test("Shared instance is consistent")
    func sharedInstance() {
        let instance1 = SpotlightIndexer.shared
        let instance2 = SpotlightIndexer.shared
        #expect(instance1 === instance2)
    }
}
