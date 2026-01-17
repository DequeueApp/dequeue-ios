//
//  DequeueApp.swift
//  Dequeue
//
//  Created by Victor Quinn on 12/21/25.
//

import SwiftUI
import SwiftData
import Clerk
import UserNotifications

// MARK: - Environment Key for SyncManager

private struct SyncManagerKey: EnvironmentKey {
    static let defaultValue: SyncManager? = nil
}

extension EnvironmentValues {
    var syncManager: SyncManager? {
        get { self[SyncManagerKey.self] }
        set { self[SyncManagerKey.self] = newValue }
    }
}

@main
struct DequeueApp: App {
    @State private var authService = ClerkAuthService()
    @State private var attachmentSettings = AttachmentSettings()
    let sharedModelContainer: ModelContainer
    let syncManager: SyncManager
    let notificationService: NotificationService

    init() {
        // Note: ErrorReportingService.configure() is now called asynchronously
        // in the body to avoid blocking app launch (was causing 12+ second hangs)

        let schema = Schema([
            Stack.self,
            QueueTask.self,
            Reminder.self,
            Event.self,
            Device.self,
            SyncConflict.self,
            Attachment.self,
            Tag.self
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        do {
            sharedModelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // Schema migration failed - delete store and retry
            ErrorReportingService.capture(error: error, context: ["source": "model_container_init"])
            Self.deleteSwiftDataStore()

            do {
                sharedModelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer after store deletion: \(error)")
            }
        }

        syncManager = SyncManager(modelContainer: sharedModelContainer)

        // Set up notification service as delegate early for background action handling
        notificationService = NotificationService(modelContext: sharedModelContainer.mainContext)
        UNUserNotificationCenter.current().delegate = notificationService
        notificationService.configureNotificationCategories()
    }

    /// Deletes SwiftData store files when schema migration fails
    private static func deleteSwiftDataStore() {
        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }

        let storeURL = appSupport.appendingPathComponent("default.store")
        let storeShmURL = appSupport.appendingPathComponent("default.store-shm")
        let storeWalURL = appSupport.appendingPathComponent("default.store-wal")

        try? fileManager.removeItem(at: storeURL)
        try? fileManager.removeItem(at: storeShmURL)
        try? fileManager.removeItem(at: storeWalURL)

        // Also clear sync checkpoint so we get fresh data from server
        UserDefaults.standard.removeObject(forKey: "com.dequeue.lastSyncCheckpoint")
    }

    var body: some Scene {
        WindowGroup {
            RootView(syncManager: syncManager)
                .environment(\.authService, authService)
                .environment(\.clerk, Clerk.shared)
                .environment(\.syncManager, syncManager)
                .environment(\.attachmentSettings, attachmentSettings)
                .applyAppTheme()
                .task {
                    // Configure error reporting first (runs on background thread)
                    await ErrorReportingService.configure()
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
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    let syncManager: SyncManager

    @State private var syncStatusViewModel: SyncStatusViewModel?

    private var notificationService: NotificationService {
        NotificationService(modelContext: modelContext)
    }

    var body: some View {
        Group {
            if authService.isLoading {
                SplashView()
            } else if authService.isAuthenticated {
                if let viewModel = syncStatusViewModel, viewModel.isInitialSyncInProgress {
                    InitialSyncLoadingView(eventsProcessed: viewModel.initialSyncEventsProcessed)
                } else {
                    MainTabView()
                }
            } else {
                AuthView()
            }
        }
        .task {
            // Initialize sync status view model for tracking initial sync
            if syncStatusViewModel == nil {
                let viewModel = SyncStatusViewModel(modelContext: modelContext)
                viewModel.setSyncManager(syncManager)
                syncStatusViewModel = viewModel
            }
        }
        .animation(.easeInOut, value: authService.isLoading)
        .animation(.easeInOut, value: authService.isAuthenticated)
        .animation(.easeInOut, value: syncStatusViewModel?.isInitialSyncInProgress)
        .onChange(of: authService.isAuthenticated) { _, isAuthenticated in
            Task {
                await handleAuthStateChange(isAuthenticated: isAuthenticated)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    // Refresh auth session when app becomes active
                    // This validates the session if we're back online after being offline
                    await authService.refreshSessionIfNeeded()

                    if authService.isAuthenticated {
                        await handleAppBecameActive()
                        await notificationService.updateAppBadge()
                    }
                }
            }
        }
        .task {
            if authService.isAuthenticated {
                await handleAuthStateChange(isAuthenticated: true)
                await notificationService.updateAppBadge()
            }
        }
    }

    private func handleAuthStateChange(isAuthenticated: Bool) async {
        if isAuthenticated {
            guard let userId = authService.currentUserId else { return }

            // Ensure current device is discovered and registered
            do {
                try await DeviceService.shared.ensureCurrentDeviceDiscovered(
                    modelContext: modelContext,
                    userId: userId
                )
            } catch {
                ErrorReportingService.capture(
                    error: error,
                    context: ["source": "device_discovery"]
                )
            }

            // Connect to sync
            do {
                let token = try await authService.getAuthToken()
                try await syncManager.connect(
                    userId: userId,
                    token: token,
                    getToken: { @MainActor in try await authService.getAuthToken() }
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

    private func handleAppBecameActive() async {
        // Update device activity so other devices see this device as recently active
        do {
            try await DeviceService.shared.updateDeviceActivity(modelContext: modelContext)
        } catch {
            ErrorReportingService.capture(
                error: error,
                context: ["source": "device_activity_update"]
            )
        }
    }
}

#Preview("Authenticated") {
    let mockAuth = MockAuthService()
    mockAuth.mockSignIn()
    // swiftlint:disable:next force_try
    let container = try! ModelContainer(
        for: Stack.self,
        QueueTask.self,
        Reminder.self,
        Event.self,
        Attachment.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let syncManager = SyncManager(modelContainer: container)

    return RootView(syncManager: syncManager)
        .environment(\.authService, mockAuth)
        .modelContainer(container)
}

#Preview("Unauthenticated") {
    // swiftlint:disable:next force_try
    let container = try! ModelContainer(
        for: Stack.self,
        QueueTask.self,
        Reminder.self,
        Event.self,
        Attachment.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let syncManager = SyncManager(modelContainer: container)

    return RootView(syncManager: syncManager)
        .environment(\.authService, MockAuthService())
        .modelContainer(container)
}
