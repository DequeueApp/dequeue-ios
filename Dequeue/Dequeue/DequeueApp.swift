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
    let sharedModelContainer: ModelContainer
    let syncManager: SyncManager

    init() {
        ErrorReportingService.configure()

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
            sharedModelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }

        syncManager = SyncManager(modelContainer: sharedModelContainer)
    }

    var body: some Scene {
        WindowGroup {
            RootView(syncManager: syncManager)
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
    let syncManager: SyncManager

    var body: some View {
        Group {
            if authService.isAuthenticated {
                MainTabView()
            } else {
                AuthView()
            }
        }
        .animation(.easeInOut, value: authService.isAuthenticated)
        .onChange(of: authService.isAuthenticated) { _, isAuthenticated in
            Task {
                await handleAuthStateChange(isAuthenticated: isAuthenticated)
            }
        }
        .task {
            if authService.isAuthenticated {
                await handleAuthStateChange(isAuthenticated: true)
            }
        }
    }

    private func handleAuthStateChange(isAuthenticated: Bool) async {
        if isAuthenticated {
            guard let userId = authService.currentUserId else { return }
            do {
                let token = try await authService.getAuthToken()
                try await syncManager.connect(
                    userId: userId,
                    token: token,
                    getToken: { try await authService.getAuthToken() }
                )
                ErrorReportingService.addBreadcrumb(
                    category: "sync",
                    message: "Sync connected",
                    data: ["userId": userId]
                )
            } catch {
                ErrorReportingService.capture(
                    error: error,
                    context: ["source": "sync_connect"]
                )
            }
        } else {
            await syncManager.disconnect()
            ErrorReportingService.addBreadcrumb(
                category: "sync",
                message: "Sync disconnected"
            )
        }
    }
}

#Preview("Authenticated") {
    let mockAuth = MockAuthService()
    mockAuth.mockSignIn()
    let container = try! ModelContainer(for: Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let syncManager = SyncManager(modelContainer: container)

    return RootView(syncManager: syncManager)
        .environment(\.authService, mockAuth)
        .modelContainer(container)
}

#Preview("Unauthenticated") {
    let container = try! ModelContainer(for: Stack.self, QueueTask.self, Reminder.self, Event.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let syncManager = SyncManager(modelContainer: container)

    return RootView(syncManager: syncManager)
        .environment(\.authService, MockAuthService())
        .modelContainer(container)
}
