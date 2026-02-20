//
//  DeepLinkManagerTests.swift
//  DequeueTests
//
//  Tests for DeepLinkDestination and deep link notification handling
//

import XCTest
@testable import Dequeue

@MainActor
final class DeepLinkManagerTests: XCTestCase {

    // MARK: - DeepLinkDestination Init - Happy Path

    func testInitWithValidStackDestination() {
        let userInfo: [AnyHashable: Any] = [
            NotificationConstants.UserInfoKey.parentId: "stack-123",
            NotificationConstants.UserInfoKey.parentType: "stack"
        ]

        let destination = DeepLinkDestination(userInfo: userInfo)

        XCTAssertNotNil(destination)
        XCTAssertEqual(destination?.parentId, "stack-123")
        XCTAssertEqual(destination?.parentType, .stack)
    }

    func testInitWithValidTaskDestination() {
        let userInfo: [AnyHashable: Any] = [
            NotificationConstants.UserInfoKey.parentId: "task-456",
            NotificationConstants.UserInfoKey.parentType: "task"
        ]

        let destination = DeepLinkDestination(userInfo: userInfo)

        XCTAssertNotNil(destination)
        XCTAssertEqual(destination?.parentId, "task-456")
        XCTAssertEqual(destination?.parentType, .task)
    }

    func testInitWithValidArcDestination() {
        let userInfo: [AnyHashable: Any] = [
            NotificationConstants.UserInfoKey.parentId: "arc-789",
            NotificationConstants.UserInfoKey.parentType: "arc"
        ]

        let destination = DeepLinkDestination(userInfo: userInfo)

        XCTAssertNotNil(destination)
        XCTAssertEqual(destination?.parentId, "arc-789")
        XCTAssertEqual(destination?.parentType, .arc)
    }

    // MARK: - DeepLinkDestination Init - All ParentType Variants

    func testInitWithAllParentTypes() {
        for parentType in ParentType.allCases {
            let userInfo: [AnyHashable: Any] = [
                NotificationConstants.UserInfoKey.parentId: "id-\(parentType.rawValue)",
                NotificationConstants.UserInfoKey.parentType: parentType.rawValue
            ]

            let destination = DeepLinkDestination(userInfo: userInfo)

            XCTAssertNotNil(destination, "Should create destination for parentType: \(parentType.rawValue)")
            XCTAssertEqual(destination?.parentType, parentType)
            XCTAssertEqual(destination?.parentId, "id-\(parentType.rawValue)")
        }
    }

    // MARK: - DeepLinkDestination Init - Failure Cases

    func testInitWithEmptyUserInfo() {
        let destination = DeepLinkDestination(userInfo: [:])
        XCTAssertNil(destination, "Should return nil for empty userInfo")
    }

    func testInitWithMissingParentId() {
        let userInfo: [AnyHashable: Any] = [
            NotificationConstants.UserInfoKey.parentType: "stack"
        ]

        let destination = DeepLinkDestination(userInfo: userInfo)
        XCTAssertNil(destination, "Should return nil when parentId is missing")
    }

    func testInitWithMissingParentType() {
        let userInfo: [AnyHashable: Any] = [
            NotificationConstants.UserInfoKey.parentId: "stack-123"
        ]

        let destination = DeepLinkDestination(userInfo: userInfo)
        XCTAssertNil(destination, "Should return nil when parentType is missing")
    }

    func testInitWithInvalidParentType() {
        let userInfo: [AnyHashable: Any] = [
            NotificationConstants.UserInfoKey.parentId: "id-123",
            NotificationConstants.UserInfoKey.parentType: "invalid_type"
        ]

        let destination = DeepLinkDestination(userInfo: userInfo)
        XCTAssertNil(destination, "Should return nil for invalid parentType raw value")
    }

    func testInitWithWrongTypeForParentId() {
        let userInfo: [AnyHashable: Any] = [
            NotificationConstants.UserInfoKey.parentId: 12345,  // Int instead of String
            NotificationConstants.UserInfoKey.parentType: "stack"
        ]

        let destination = DeepLinkDestination(userInfo: userInfo)
        XCTAssertNil(destination, "Should return nil when parentId is not a String")
    }

    func testInitWithWrongTypeForParentType() {
        let userInfo: [AnyHashable: Any] = [
            NotificationConstants.UserInfoKey.parentId: "id-123",
            NotificationConstants.UserInfoKey.parentType: 42  // Int instead of String
        ]

        let destination = DeepLinkDestination(userInfo: userInfo)
        XCTAssertNil(destination, "Should return nil when parentType is not a String")
    }

    func testInitWithNilValuesInUserInfo() {
        let userInfo: [AnyHashable: Any] = [
            NotificationConstants.UserInfoKey.parentId: NSNull(),
            NotificationConstants.UserInfoKey.parentType: NSNull()
        ]

        let destination = DeepLinkDestination(userInfo: userInfo)
        XCTAssertNil(destination, "Should return nil when values are NSNull")
    }

    func testInitWithEmptyStringParentId() {
        let userInfo: [AnyHashable: Any] = [
            NotificationConstants.UserInfoKey.parentId: "",
            NotificationConstants.UserInfoKey.parentType: "stack"
        ]

        // Empty string is a valid String, so init should succeed
        // (business logic validation is separate from parsing)
        let destination = DeepLinkDestination(userInfo: userInfo)
        XCTAssertNotNil(destination, "Empty string parentId should still parse successfully")
        XCTAssertEqual(destination?.parentId, "")
    }

    func testInitWithEmptyStringParentType() {
        let userInfo: [AnyHashable: Any] = [
            NotificationConstants.UserInfoKey.parentId: "id-123",
            NotificationConstants.UserInfoKey.parentType: ""
        ]

        let destination = DeepLinkDestination(userInfo: userInfo)
        XCTAssertNil(destination, "Empty string parentType should fail ParentType(rawValue:)")
    }

    func testInitWithExtraKeysInUserInfo() {
        let userInfo: [AnyHashable: Any] = [
            NotificationConstants.UserInfoKey.parentId: "stack-123",
            NotificationConstants.UserInfoKey.parentType: "stack",
            NotificationConstants.UserInfoKey.reminderId: "reminder-456",
            "extraKey": "extraValue"
        ]

        let destination = DeepLinkDestination(userInfo: userInfo)
        XCTAssertNotNil(destination, "Extra keys in userInfo should be ignored")
        XCTAssertEqual(destination?.parentId, "stack-123")
        XCTAssertEqual(destination?.parentType, .stack)
    }

    func testInitWithCaseSensitiveParentType() {
        let userInfo: [AnyHashable: Any] = [
            NotificationConstants.UserInfoKey.parentId: "id-123",
            NotificationConstants.UserInfoKey.parentType: "Stack"  // Capital S
        ]

        let destination = DeepLinkDestination(userInfo: userInfo)
        XCTAssertNil(destination, "ParentType raw value is case-sensitive; 'Stack' should fail")
    }

    // MARK: - Equatable Conformance

    func testEqualDestinations() {
        let userInfo: [AnyHashable: Any] = [
            NotificationConstants.UserInfoKey.parentId: "stack-123",
            NotificationConstants.UserInfoKey.parentType: "stack"
        ]

        let destination1 = DeepLinkDestination(userInfo: userInfo)
        let destination2 = DeepLinkDestination(userInfo: userInfo)

        XCTAssertEqual(destination1, destination2)
    }

    func testUnequalDestinationsDifferentId() {
        let userInfo1: [AnyHashable: Any] = [
            NotificationConstants.UserInfoKey.parentId: "stack-123",
            NotificationConstants.UserInfoKey.parentType: "stack"
        ]
        let userInfo2: [AnyHashable: Any] = [
            NotificationConstants.UserInfoKey.parentId: "stack-456",
            NotificationConstants.UserInfoKey.parentType: "stack"
        ]

        let destination1 = DeepLinkDestination(userInfo: userInfo1)
        let destination2 = DeepLinkDestination(userInfo: userInfo2)

        XCTAssertNotEqual(destination1, destination2)
    }

    func testUnequalDestinationsDifferentType() {
        let userInfo1: [AnyHashable: Any] = [
            NotificationConstants.UserInfoKey.parentId: "id-123",
            NotificationConstants.UserInfoKey.parentType: "stack"
        ]
        let userInfo2: [AnyHashable: Any] = [
            NotificationConstants.UserInfoKey.parentId: "id-123",
            NotificationConstants.UserInfoKey.parentType: "task"
        ]

        let destination1 = DeepLinkDestination(userInfo: userInfo1)
        let destination2 = DeepLinkDestination(userInfo: userInfo2)

        XCTAssertNotEqual(destination1, destination2)
    }

    // MARK: - Notification Name

    func testReminderNotificationTappedName() {
        let name = Notification.Name.reminderNotificationTapped
        XCTAssertEqual(name.rawValue, "com.dequeue.reminderNotificationTapped")
    }

    func testNotificationNameIsStable() {
        // Ensure the notification name doesn't accidentally change
        // (it may be used as a string in other parts of the codebase)
        let name1 = Notification.Name.reminderNotificationTapped
        let name2 = Notification.Name.reminderNotificationTapped
        XCTAssertEqual(name1, name2)
    }

    // MARK: - UserInfo Key Constants

    func testUserInfoKeyConstants() {
        // Verify the key strings match expected values used in notification payloads
        XCTAssertEqual(NotificationConstants.UserInfoKey.parentId, "parentId")
        XCTAssertEqual(NotificationConstants.UserInfoKey.parentType, "parentType")
        XCTAssertEqual(NotificationConstants.UserInfoKey.reminderId, "reminderId")
    }
}
