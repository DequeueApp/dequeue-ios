//
//  MainTabView.swift
//  Dequeue
//
//  Main tab-based navigation for authenticated users
//  Uses native TabView with Liquid Glass (iOS 26+)
//

import SwiftUI
import SwiftData
import Combine

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.syncManager) private var syncManager
    @Environment(\.authService) private var authService

    @Query(filter: #Predicate<Stack> { !$0.isDeleted }) private var allStacks: [Stack]
    @Query(filter: #Predicate<QueueTask> { !$0.isDeleted }) private var allTasks: [QueueTask]

    @State private var selectedTab = 0
    @State private var cachedDeviceId: String = ""
    @State private var showStackPicker = false
    @State private var activeStackForDetail: Stack?
    @State private var undoCompletionManager = UndoCompletionManager()
    @State private var attachmentUploadCoordinator: AttachmentUploadCoordinator?

    var body: some View {
        #if os(macOS)
        macOSLayout
        #else
        iOSLayout
        #endif
    }

    // MARK: - Shared Modifiers

    /// Applies common modifiers for both iOS and macOS layouts
    private func applySharedModifiers<Content: View>(_ content: Content) -> some View {
        content
            .sheet(isPresented: $showStackPicker) {
                StackPickerSheet()
            }
            .sheet(item: $activeStackForDetail) { stack in
                StackEditorView(mode: .edit(stack))
            }
            .environment(\.undoCompletionManager, undoCompletionManager)
            .environment(\.attachmentUploadCoordinator, attachmentUploadCoordinator)
            .task {
                if cachedDeviceId.isEmpty {
                    cachedDeviceId = await DeviceService.shared.getDeviceId()
                }
                undoCompletionManager.configure(
                    modelContext: modelContext,
                    syncManager: syncManager,
                    userId: authService.currentUserId ?? "",
                    deviceId: cachedDeviceId
                )
                if attachmentUploadCoordinator == nil {
                    let uploadService = AttachmentUploadService(authService: authService)
                    attachmentUploadCoordinator = AttachmentUploadCoordinator(
                        modelContext: modelContext,
                        uploadService: uploadService
                    )
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .reminderNotificationTapped)) { notification in
                handleDeepLink(from: notification)
            }
    }

    // MARK: - iOS/iPadOS Layout

    #if os(iOS)
    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    /// Standard tab bar height on iOS
    private let tabBarHeight: CGFloat = 49
    #endif

    private var iOSLayout: some View {
        #if os(iOS)
        applySharedModifiers(
            ZStack(alignment: .bottom) {
                TabView(selection: $selectedTab) {
                    ArcsView()
                        .tabItem { Label("Arcs", systemImage: "rays") }
                        .tag(0)
                    StacksView()
                        .tabItem { Label("Stacks", systemImage: "square.stack.3d.up") }
                        .tag(1)
                    ActivityFeedView()
                        .tabItem { Label("Activity", systemImage: "clock.arrow.circlepath") }
                        .tag(2)
                    SettingsView()
                        .tabItem { Label("Settings", systemImage: "gear") }
                        .tag(3)
                }
                floatingBanners
            }
        )
        #else
        EmptyView()
        #endif
    }

    #if os(iOS)
    private var floatingBanners: some View {
        GeometryReader { geometry in
            // Color.clear passes touches through to TabView beneath
            // The overlay content (banners) still receives touches normally
            Color.clear
                .allowsHitTesting(false)
                .overlay(alignment: .bottom) {
                    VStack(spacing: 12) {
                        // Undo completion banner (appears above active stack banner)
                        if undoCompletionManager.hasPendingCompletion,
                           let stack = undoCompletionManager.pendingStack {
                            UndoCompletionBanner(
                                stackTitle: stack.title,
                                progress: undoCompletionManager.progress,
                                onUndo: {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        undoCompletionManager.undoCompletion()
                                    }
                                }
                            )
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .opacity
                            ))
                        }

                        activeStackBanner
                    }
                    .frame(maxWidth: isIPad ? min(400, geometry.size.width / 3) : .infinity)
                    .padding(.horizontal)
                    // Position above tab bar: safe area + tab bar height
                    .padding(.bottom, geometry.safeAreaInsets.bottom + tabBarHeight)
                    .animation(.easeInOut(duration: 0.25), value: undoCompletionManager.hasPendingCompletion)
                }
        }
    }

    #endif

    // MARK: - macOS Layout

    #if os(macOS)
    private var macOSLayout: some View {
        applySharedModifiers(
            NavigationSplitView {
                List(selection: $selectedTab) {
                    NavigationLink(value: 0) { Label("Arcs", systemImage: "rays") }
                    NavigationLink(value: 1) { Label("Stacks", systemImage: "square.stack.3d.up") }
                    NavigationLink(value: 2) { Label("Activity", systemImage: "clock.arrow.circlepath") }
                    NavigationLink(value: 3) { Label("Settings", systemImage: "gear") }
                }
                .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            } detail: {
                ZStack(alignment: .bottom) {
                    detailContent.frame(maxHeight: .infinity, alignment: .top)
                    macOSBanners
                }
            }
        )
    }

    private var macOSBanners: some View {
        VStack(spacing: 12) {
            if undoCompletionManager.hasPendingCompletion,
               let stack = undoCompletionManager.pendingStack {
                UndoCompletionBanner(
                    stackTitle: stack.title,
                    progress: undoCompletionManager.progress,
                    onUndo: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            undoCompletionManager.undoCompletion()
                        }
                    }
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity
                ))
            }
            activeStackBanner
        }
        .padding(.horizontal)
        .padding(.bottom, 16)
        .animation(.easeInOut(duration: 0.25), value: undoCompletionManager.hasPendingCompletion)
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedTab {
        case 0: ArcsView()
        case 1: StacksView()
        case 2: ActivityFeedView()
        case 3: SettingsView()
        default: ArcsView()
        }
    }
    #endif

    // MARK: - Deep Link Navigation (DEQ-211)

    /// Handles navigation from a reminder notification tap
    private func handleDeepLink(from notification: Notification) {
        guard let userInfo = notification.userInfo,
              let destination = DeepLinkDestination(userInfo: userInfo) else {
            return
        }

        // Find the target Stack to navigate to
        let targetStack: Stack?

        switch destination.parentType {
        case .stack:
            targetStack = allStacks.first { $0.id == destination.parentId }
        case .task:
            // Find the task, then get its parent stack
            if let task = allTasks.first(where: { $0.id == destination.parentId }) {
                targetStack = task.stack
            } else {
                targetStack = nil
            }
        case .arc:
            // Arcs don't have a detail view yet - could navigate to Arcs tab in future
            targetStack = nil
        }

        guard let stack = targetStack else { return }

        // Navigate to the Stacks tab and show the stack detail
        withAnimation {
            selectedTab = 1  // Stacks tab
        }

        // Show the stack editor after tab switch animation completes
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            activeStackForDetail = stack
        }
    }

    // MARK: - Active Stack Banner

    private var activeStackBanner: some View {
        ActiveStackBanner(
            onStackTapped: { stack in
                activeStackForDetail = stack
            },
            onEmptyTapped: {
                showStackPicker = true
            }
        )
    }
}

#Preview {
    MainTabView()
        .modelContainer(for: [Stack.self, QueueTask.self, Reminder.self], inMemory: true)
}
