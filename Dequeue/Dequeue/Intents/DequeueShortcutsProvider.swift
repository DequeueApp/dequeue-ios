//
//  DequeueShortcutsProvider.swift
//  Dequeue
//
//  Provides discoverable shortcuts for Siri and the Shortcuts app
//

import AppIntents

/// Registers Dequeue shortcuts for Siri and the Shortcuts app.
/// These appear in the Shortcuts app's gallery and can be suggested by Siri.
struct DequeueShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // "Add task" - most common action
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: [
                "Add a task to \(.applicationName)",
                "Create a task in \(.applicationName)",
                "New task in \(.applicationName)",
                "Add to my stack in \(.applicationName)"
            ],
            shortTitle: "Add Task",
            systemImageName: "plus.circle.fill"
        )

        // "Complete task" - second most common
        AppShortcut(
            intent: CompleteCurrentTaskIntent(),
            phrases: [
                "Complete my task in \(.applicationName)",
                "Finish current task in \(.applicationName)",
                "Done with my task in \(.applicationName)",
                "Mark task complete in \(.applicationName)",
                "I finished my task in \(.applicationName)"
            ],
            shortTitle: "Complete Task",
            systemImageName: "checkmark.circle.fill"
        )

        // "View stack" - quick status check
        AppShortcut(
            intent: ViewCurrentStackIntent(),
            phrases: [
                "What's my current task in \(.applicationName)",
                "Show my stack in \(.applicationName)",
                "What am I working on in \(.applicationName)",
                "What's next in \(.applicationName)",
                "Show my progress in \(.applicationName)"
            ],
            shortTitle: "View Stack",
            systemImageName: "list.bullet"
        )

        // "Activate stack" - switch context
        AppShortcut(
            intent: ActivateStackIntent(),
            phrases: [
                "Switch stack in \(.applicationName)",
                "Activate a stack in \(.applicationName)",
                "Focus on a stack in \(.applicationName)",
                "Change stack in \(.applicationName)"
            ],
            shortTitle: "Activate Stack",
            systemImageName: "bolt.circle.fill"
        )
    }
}
