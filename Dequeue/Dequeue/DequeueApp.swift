//
//  DequeueApp.swift
//  Dequeue
//
//  Created by Victor Quinn on 12/21/25.
//

import SwiftUI
import SwiftData
import Clerk

@main
struct DequeueApp: App {
    @State private var authService = ClerkAuthService()

    init() {
        ErrorReportingService.configure()
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Stack.self,
            QueueTask.self,
            Reminder.self,
            Event.self,
            Device.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.authService, authService)
                .environment(\.clerk, Clerk.shared)
                .task {
                    await authService.configure()
                }
        }
        .modelContainer(sharedModelContainer)
    }
}

// MARK: - Root View

/// Handles navigation between auth and main app based on authentication state
struct RootView: View {
    @Environment(\.authService) private var authService

    var body: some View {
        Group {
            if authService.isAuthenticated {
                MainTabView()
            } else {
                AuthView()
            }
        }
        .animation(.easeInOut, value: authService.isAuthenticated)
    }
}

#Preview("Authenticated") {
    let mockAuth = MockAuthService()
    mockAuth.mockSignIn()

    return RootView()
        .environment(\.authService, mockAuth)
        .modelContainer(for: [Stack.self, QueueTask.self, Reminder.self], inMemory: true)
}

#Preview("Unauthenticated") {
    RootView()
        .environment(\.authService, MockAuthService())
        .modelContainer(for: [Stack.self, QueueTask.self, Reminder.self], inMemory: true)
}
