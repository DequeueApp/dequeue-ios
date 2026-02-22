//
//  DequeueApp.swift
//  Dequeue
//
//  Created by Victor Quinn on 12/21/25.
//

import SwiftUI
import SwiftData
import Clerk
import CoreSpotlight
import UserNotifications
import WidgetKit
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
    #if os(iOS)
    @UIApplicationDelegateAdaptor(DequeueAppDelegate.self) var appDelegate
    #endif

    @State private var authService: any AuthServiceProtocol
    @State private var attachmentSettings = AttachmentSettings()
    @State private var consecutiveSyncFailures = 0
    @State private var showSyncError = false
    let sharedModelContainer: ModelContainer
    let syncManager: SyncManager
    let notificationService: NotificationService

    /// Non-nil when ModelContainer failed to initialize even after store deletion.
    /// The app falls back to an in-memory container and shows an error screen.
    let databaseErrorMessage: String?

    /// Threshold for showing user feedback about sync issues
    private let syncFailureThreshold = 3

    /// Check if running in a test environment (unit tests use app as TEST_HOST)
    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Check if running UI tests (launched with --uitesting argument)
    private static var isRunningUITests: Bool {
        ProcessInfo.processInfo.arguments.contains("--uitesting")
    }

    init() {
        // Configure Sentry FIRST — before anything else — so crashes during
        // ModelContainer init are captured. This is synchronous and fast.
        ErrorReportingService.configure()

        // Use mock auth service for UI tests to bypass Clerk authentication
        if Self.isRunningUITests {
            let mockAuth = MockAuthService()
            // Only auto-sign in if NOT explicitly testing unauthenticated flow
            if !ProcessInfo.processInfo.arguments.contains("--unauthenticated") {
                mockAuth.mockSignIn(userId: "ui-test-user")
            }
            authService = mockAuth
        } else {
            authService = ClerkAuthService()
        }

        let schema = Schema([
            Stack.self,
            QueueTask.self,
            Reminder.self,
            Event.self,
            Device.self,
            SyncConflict.self,
            Attachment.self,
            Tag.self,
            Arc.self
        ])

        // Use in-memory store when running tests or UI tests to avoid file system issues
        // and ensure test isolation
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: Self.isRunningTests || Self.isRunningUITests,
            cloudKitDatabase: .none
        )

        var dbError: String?
        let container: ModelContainer

        do {
            container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // Schema migration failed - delete store and retry
            ErrorReportingService.capture(error: error, context: ["source": "model_container_init"])
            Self.deleteSwiftDataStore()

            do {
                container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                // Graceful recovery: fall back to an in-memory container so the app
                // can at least launch and show an error screen instead of crashing.
                ErrorReportingService.capture(
                    error: error,
                    context: ["source": "model_container_init_after_deletion", "recovery": "in_memory_fallback"]
                )
                dbError = error.localizedDescription

                let inMemoryConfig = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                )
                do {
                    container = try ModelContainer(for: schema, configurations: [inMemoryConfig])
                } catch {
                    // Last resort: minimal in-memory container — this should essentially never fail
                    ErrorReportingService.capture(
                        error: error,
                        context: ["source": "model_container_in_memory_fallback"]
                    )
                    // swiftlint:disable:next force_try
                    container = try! ModelContainer(
                        for: schema,
                        configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
                    )
                }
            }
        }

        sharedModelContainer = container
        databaseErrorMessage = dbError

        syncManager = SyncManager(modelContainer: sharedModelContainer)

        // Set up notification service as delegate early for background action handling
        notificationService = NotificationService(modelContext: sharedModelContainer.mainContext)
        UNUserNotificationCenter.current().delegate = notificationService
        notificationService.configureNotificationCategories()
    }

    /// Deletes SwiftData store files when schema migration fails.
    /// Checks both the default app container and the App Group container
    /// since the store location can vary depending on entitlements.
    static func deleteSwiftDataStore() {
        let fileManager = FileManager.default
        let storeFileNames = ["default.store", "default.store-shm", "default.store-wal"]

        // 1. Delete from default app Application Support directory
        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            for fileName in storeFileNames {
                try? fileManager.removeItem(at: appSupport.appendingPathComponent(fileName))
            }
        }

        // 2. Delete from App Group container (widgets share data via group container)
        if let groupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.com.ardonos.Dequeue") {
            let groupAppSupport = groupURL.appendingPathComponent("Library/Application Support")
            for fileName in storeFileNames {
                try? fileManager.removeItem(at: groupAppSupport.appendingPathComponent(fileName))
            }
        }

        // Also clear sync checkpoint so we get fresh data from server
        UserDefaults.standard.removeObject(forKey: "com.dequeue.lastSyncCheckpoint")
    }

    var body: some Scene {
        WindowGroup {
            if let errorMessage = databaseErrorMessage {
                DatabaseErrorView(message: errorMessage)
            } else {
                RootView(syncManager: syncManager, showSyncError: $showSyncError)
                    .environment(\.authService, authService)
                    .environment(\.clerk, Clerk.shared)
                    .environment(\.syncManager, syncManager)
                    .environment(\.attachmentSettings, attachmentSettings)
                    .environment(\.searchService, SearchService(authService: authService))
                    .environment(\.statsService, StatsService(authService: authService))
                    .environment(\.exportService, ExportService(authService: authService))
                    .environment(\.webhookService, WebhookService(authService: authService))
                    .environment(\.batchService, BatchService(authService: authService))
                    .applyAppTheme()
                    .task {
                        // Sentry is already configured synchronously in init()
                        ErrorReportingService.logAppLaunch(isWarmLaunch: false)
                        await authService.configure()
                    }
            }
        }
        .modelContainer(sharedModelContainer)
        #if os(macOS)
        .commands {
            AppCommands()  // DEQ-50: Add macOS keyboard shortcuts
        }
        #endif
    }
}

// MARK: - Database Error View

/// Shown when the persistent store cannot be created even after deletion.
/// Gives the user a clear explanation and a way to attempt recovery.
struct DatabaseErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.orange)

            Text("Database Error")
                .font(.title)
                .fontWeight(.bold)

            Text(
                "The app's local database could not be initialized. " +
                "This can happen after an update changes the data format."
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 32)

            Text(message)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 32)

            Button("Delete Local Data & Relaunch") {
                DequeueApp.deleteSwiftDataStore()
                // Clean exit so the user can relaunch with a fresh store.
                // Data will re-sync from the server on next launch.
                exit(0)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)

            Text("Your data is safe on the server and will re-sync after relaunch.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
        }
        .padding()
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

    @State private var syncStatusViewModel: SyncStatusViewModel?
    @State private var showAddTaskSheet = false
    @State private var showNewStackSheet = false
    @State private var showSearchView = false

    private var notificationService: NotificationService {
        NotificationService(modelContext: modelContext)
    }

    // Initial sync loading removed — sync happens in the background.
    // Users should never be blocked from using the app while syncing.

    var body: some View {
        Group {
            if authService.isLoading {
                SplashView()
            } else if authService.isAuthenticated {
                MainTabView()
            } else {
                AuthView()
            }
        }
        .task {
            // Initialize sync status view model early to track initial sync progress.
            // This reactive approach avoids polling - the view model tracks sync state changes.
            if syncStatusViewModel == nil {
                let viewModel = SyncStatusViewModel(modelContext: modelContext)
                viewModel.setSyncManager(syncManager)
                syncStatusViewModel = viewModel
            }
        }
        .animation(.easeInOut, value: authService.isLoading)
        .animation(.easeInOut, value: authService.isAuthenticated)
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
                // Handle pending quick actions (home screen 3D Touch shortcuts)
                handlePendingQuickAction()
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

                        // Update home screen quick action shortcuts with current context
                        #if os(iOS)
                        let activeStackName = QuickActionService.fetchActiveStackName(modelContext: modelContext)
                        QuickActionService.shared.updateShortcutItems(activeStackName: activeStackName)
                        #endif
                    }
                }
            case .background:
                // Update widget data before going to background (DEQ-120)
                // This ensures widgets show the latest state when the user leaves the app
                WidgetDataService.updateAllWidgets(context: modelContext)

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
        .task {
            // Observe session state changes for multi-device scenarios
            // This handles cases where session is invalidated or restored asynchronously
            await observeSessionStateChanges()
        }
        .onOpenURL { url in
            // Handle dequeue:// deep links from widgets, Spotlight, and Shortcuts
            DeepLinkManager.handleURL(url)
        }
        .onContinueUserActivity(CSSearchableItemActionType) { userActivity in
            // Handle Spotlight search result taps
            DeepLinkManager.handleSpotlight(userActivity)
        }
    }

    /// Observes session state changes and handles multi-device session scenarios
    private func observeSessionStateChanges() async {
        for await change in authService.sessionStateChanges {
            switch change {
            case .sessionInvalidated(let reason):
                os_log("[Auth] Session invalidated: \(String(describing: reason))")
                // Disconnect sync when session is unexpectedly invalidated
                await syncManager.disconnect()
                // Reset consecutive failures since this is an auth issue, not connectivity
                consecutiveSyncFailures = 0

            case .sessionRestored(let userId):
                os_log("[Auth] Session restored for userId: \(userId)")
                // Re-establish sync connection with restored session
                await connectSyncWithRetry(userId: userId, maxRetries: 3)
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

            // Store user context in App Group for widgets and App Intents
            let deviceId = await DeviceService.shared.getDeviceId()
            AppGroupConfig.storeUserContext(userId: userId, deviceId: deviceId)

            // Run one-time data migrations (e.g., attachment path format)
            await runMigrationsIfNeeded()

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

    /// Ensures sync is connected with fresh credentials when app becomes active
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

    /// Runs one-time data migrations (attachment paths, duplicate tags).
    /// Note: Runs before sync connection; migrations are idempotent and retry on next launch if failed.
    private func runMigrationsIfNeeded() async {
        guard let userId = authService.currentUserId else { return }
        let deviceId = await DeviceService.shared.getDeviceId()
        await runAttachmentPathMigration(userId: userId, deviceId: deviceId)
        await runDuplicateTagMigration()
    }

    private func runAttachmentPathMigration(userId: String, deviceId: String) async {
        let migrationKey = "com.dequeue.migrations.attachmentRelativePaths"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
        let attachmentService = AttachmentService(
            modelContext: modelContext, userId: userId, deviceId: deviceId
        )
        do {
            let migratedCount = try attachmentService.migrateAttachmentPaths()
            if migratedCount > 0 {
                os_log("[Migration] Migrated \(migratedCount) attachment paths to relative format")
            }
            UserDefaults.standard.set(true, forKey: migrationKey)
        } catch {
            os_log("[Migration] Failed to migrate attachment paths: \(error.localizedDescription)")
            ErrorReportingService.capture(error: error, context: ["source": "attachment_path_migration"])
        }
    }

    private func getPendingSyncItemCount() async -> Int {
        do {
            return try EventService.readOnly(modelContext: modelContext).fetchPendingEvents().count
        } catch {
            os_log("[App] Failed to get pending sync count: \(error.localizedDescription)")
            return 0
        }
    }

    private func runDuplicateTagMigration() async {
        guard let result = try? TagService.mergeDuplicateTags(modelContext: modelContext),
              result.duplicateGroupsFound > 0 else { return }
        os_log("[Migration] Merged \(result.tagsMerged) tags in \(result.duplicateGroupsFound) groups")
    }

    // MARK: - Quick Actions

    /// Processes a pending quick action triggered from the home screen.
    /// Called when the scene becomes active after a quick action launch.
    private func handlePendingQuickAction() {
        #if os(iOS)
        guard let action = QuickActionService.shared.pendingAction else { return }
        QuickActionService.shared.clearPendingAction()

        os_log("[QuickActions] Processing pending action: \(action.rawValue)")

        switch action {
        case .addTask:
            showAddTaskSheet = true
        case .viewActiveStack:
            // Navigate to active stack via deep link
            if let url = URL(string: "dequeue://action/active-stack") {
                DeepLinkManager.handleURL(url)
            }
        case .search:
            showSearchView = true
        case .newStack:
            showNewStackSheet = true
        }
        #endif
    }
}

// swiftlint:disable force_try
private func makePreviewContainer() -> ModelContainer {
    try! ModelContainer(
        for: Stack.self,
        QueueTask.self,
        Reminder.self,
        Event.self,
        Attachment.self,
        Arc.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
}
// swiftlint:enable force_try

#Preview("Authenticated") {
    let mockAuth = MockAuthService()
    mockAuth.mockSignIn()
    let container = makePreviewContainer()
    return RootView(syncManager: SyncManager(modelContainer: container), showSyncError: .constant(false))
        .environment(\.authService, mockAuth)
        .modelContainer(container)
}

#Preview("Unauthenticated") {
    let container = makePreviewContainer()
    return RootView(syncManager: SyncManager(modelContainer: container), showSyncError: .constant(false))
        .environment(\.authService, MockAuthService())
        .modelContainer(container)
}
