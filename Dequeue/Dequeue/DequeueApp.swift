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
import os.log

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
    @State private var consecutiveSyncFailures = 0
    @State private var showSyncError = false
    let sharedModelContainer: ModelContainer
    let syncManager: SyncManager
    let notificationService: NotificationService

    /// Threshold for showing user feedback about sync issues
    private let syncFailureThreshold = 3

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
            RootView(syncManager: syncManager, showSyncError: $showSyncError)
                .environment(\.authService, authService)
                .environment(\.clerk, Clerk.shared)
                .environment(\.syncManager, syncManager)
                .environment(\.attachmentSettings, attachmentSettings)
                .applyAppTheme()
                .task {
                    // Configure error reporting first (runs on background thread)
                    await ErrorReportingService.configure()
                    // Log app launch after Sentry is configured
                    ErrorReportingService.logAppLaunch(isWarmLaunch: false)
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
    @Binding var showSyncError: Bool

    @State private var consecutiveSyncFailures = 0
    private let syncFailureThreshold = 3

    // Initialize view model eagerly to avoid race condition where body evaluates before .task completes
    @State private var syncStatusViewModel: SyncStatusViewModel?

    private var notificationService: NotificationService {
        NotificationService(modelContext: modelContext)
    }

    // Computed property to safely access initial sync state with default
    private var isInitialSyncInProgress: Bool {
        syncStatusViewModel?.isInitialSyncInProgress ?? false
    }

    private var initialSyncEventsProcessed: Int {
        syncStatusViewModel?.initialSyncEventsProcessed ?? 0
    }

    var body: some View {
        Group {
            if authService.isLoading {
                SplashView()
            } else if authService.isAuthenticated {
                if isInitialSyncInProgress {
                    InitialSyncLoadingView(eventsProcessed: initialSyncEventsProcessed)
                } else {
                    MainTabView()
                }
            } else {
                AuthView()
            }
        }
        .task {
            // Initialize sync status view model for tracking initial sync
            // Note: This runs early enough because .task executes before body renders child views
            // and the Group wrapper defers MainTabView/InitialSyncLoadingView creation
            if syncStatusViewModel == nil {
                let viewModel = SyncStatusViewModel(modelContext: modelContext)
                viewModel.setSyncManager(syncManager)
                syncStatusViewModel = viewModel
            }
        }
        .animation(.easeInOut, value: authService.isLoading)
        .animation(.easeInOut, value: authService.isAuthenticated)
        .animation(.easeInOut, value: syncStatusViewModel?.isInitialSyncInProgress)
        .alert("Sync Connection Issue", isPresented: $showSyncError) {
            Button("OK") {
                showSyncError = false
            }
        } message: {
            Text("Unable to connect to sync. Your changes are saved locally and will sync when connection is restored.")
        }
        .onChange(of: authService.isAuthenticated) { _, isAuthenticated in
            Task {
                await handleAuthStateChange(isAuthenticated: isAuthenticated)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                ErrorReportingService.logAppForeground()
                Task {
                    // Refresh auth session when app becomes active
                    // This validates the session if we're back online after being offline
                    await authService.refreshSessionIfNeeded()

                    if authService.isAuthenticated {
                        // Ensure sync is connected with fresh credentials
                        // This handles cases where WebSocket disconnected in background
                        // or user re-authenticated without triggering onChange
                        await ensureSyncConnected()
                        await handleAppBecameActive()
                        await notificationService.updateAppBadge()
                    }
                }
            case .background:
                // Use detached task with utility priority to avoid blocking the background transition.
                // This is fire-and-forget logging that shouldn't delay the app's transition to background.
                Task.detached(priority: .utility) { [self] in
                    let pendingCount = await getPendingSyncItemCount()
                    await ErrorReportingService.logAppBackground(pendingSyncItems: pendingCount)
                }
            case .inactive:
                // No logging needed for inactive state
                break
            @unknown default:
                break
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
            guard let userId = authService.currentUserId else {
                os_log("[Auth] handleAuthStateChange: No userId available")
                return
            }

            os_log("[Auth] handleAuthStateChange: Authenticated, userId: \(userId)")

            // Ensure current device is discovered and registered
            do {
                try await DeviceService.shared.ensureCurrentDeviceDiscovered(
                    modelContext: modelContext,
                    userId: userId
                )
            } catch {
                os_log("[Auth] Device discovery failed: \(error.localizedDescription)")
                ErrorReportingService.capture(
                    error: error,
                    context: ["source": "device_discovery"]
                )
            }

            // Connect to sync with retry
            await connectSyncWithRetry(userId: userId, maxRetries: 3)
        } else {
            os_log("[Auth] handleAuthStateChange: Not authenticated, disconnecting sync")
            await syncManager.disconnect()
            ErrorReportingService.addBreadcrumb(
                category: "sync",
                message: "Sync disconnected"
            )
        }
    }

    /// Connects to sync with retry logic for transient failures
    private func connectSyncWithRetry(userId: String, maxRetries: Int) async {
        for attempt in 1...maxRetries {
            do {
                os_log("[Sync] Connection attempt \(attempt)/\(maxRetries)")
                let token = try await authService.getAuthToken()
                os_log("[Sync] Got auth token, connecting...")
                try await syncManager.connect(
                    userId: userId,
                    token: token,
                    getToken: { @MainActor in try await authService.getAuthToken() }
                )
                os_log("[Sync] Connected successfully on attempt \(attempt)")
                ErrorReportingService.addBreadcrumb(
                    category: "sync",
                    message: "Sync connected",
                    data: ["userId": userId, "attempt": attempt]
                )
                return // Success, exit retry loop
            } catch {
                os_log("[Sync] Connection attempt \(attempt) failed: \(error.localizedDescription)")
                ErrorReportingService.capture(
                    error: error,
                    context: ["source": "sync_connect", "attempt": attempt, "maxRetries": maxRetries]
                )

                if attempt < maxRetries {
                    // Wait before retrying (exponential backoff: 1s, 2s, 4s)
                    let delay = pow(2.0, Double(attempt - 1))
                    os_log("[Sync] Retrying in \(delay) seconds...")
                    try? await Task.sleep(for: .seconds(delay))
                } else {
                    os_log("[Sync] All connection attempts failed")
                }
            }
        }
    }

    /// Ensures sync is connected with fresh credentials.
    /// Called when app becomes active to handle cases where:
    /// - WebSocket disconnected while app was in background
    /// - User re-authenticated without triggering onChange (session refresh)
    /// - Initial connection failed and needs retry
    private func ensureSyncConnected() async {
        guard let userId = authService.currentUserId else { return }

        // Efficient health check: skip connection attempt if already healthy
        if await syncManager.isHealthyConnection {
            os_log("[Sync] Connection already healthy, skipping reconnect")
            return
        }

        os_log("[Sync] Connection not healthy, attempting to reconnect")

        do {
            let token = try await authService.getAuthToken()
            try await syncManager.ensureConnected(
                userId: userId,
                token: token,
                getToken: { @MainActor in try await authService.getAuthToken() }
            )

            // Success: reset failure counter
            consecutiveSyncFailures = 0
        } catch {
            // Track consecutive failures
            consecutiveSyncFailures += 1

            ErrorReportingService.capture(
                error: error,
                context: [
                    "source": "sync_ensure_connected",
                    "consecutive_failures": consecutiveSyncFailures
                ]
            )

            // Show user feedback after threshold
            if consecutiveSyncFailures >= syncFailureThreshold {
                os_log("[Sync] Consecutive failure threshold reached (\(consecutiveSyncFailures))")
                showSyncError = true
            }
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

    /// Get the count of pending sync items for observability
    private func getPendingSyncItemCount() async -> Int {
        do {
            let eventService = EventService.readOnly(modelContext: modelContext)
            let pendingEvents = try eventService.fetchPendingEvents()
            return pendingEvents.count
        } catch {
            return 0
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

    return RootView(syncManager: syncManager, showSyncError: .constant(false))
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

    return RootView(syncManager: syncManager, showSyncError: .constant(false))
        .environment(\.authService, MockAuthService())
        .modelContainer(container)
}
