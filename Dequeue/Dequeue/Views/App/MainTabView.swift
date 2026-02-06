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

    // DEQ-142: Removed @Query for allStacks and allTasks
    // These were only used for deep link navigation (rare event)
    // Now fetched lazily in handleDeepLink() to avoid 2 queries on every init

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

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @ViewBuilder
    private var iOSLayout: some View {
        #if os(iOS)
        // DEQ-51: Use split view on large iPads
        if isIPad && horizontalSizeClass == .regular {
            applySharedModifiers(iPadSplitViewLayout)
        } else {
            applySharedModifiers(iPhoneTabViewLayout)
        }
        #else
        EmptyView()
        #endif
    }

    private var iPhoneTabViewLayout: some View {
        #if os(iOS)
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
        #else
        EmptyView()
        #endif
    }

    /// iPad split view layout with sidebar navigation (DEQ-51)
    private var iPadSplitViewLayout: some View {
        #if os(iOS)
        NavigationSplitView {
            List {
                NavigationLink(value: 0) {
                    Label("Arcs", systemImage: "rays")
                }
                NavigationLink(value: 1) {
                    Label("Stacks", systemImage: "square.stack.3d.up")
                }
                NavigationLink(value: 2) {
                    Label("Activity", systemImage: "clock.arrow.circlepath")
                }
                NavigationLink(value: 3) {
                    Label("Settings", systemImage: "gear")
                }
            }
            .navigationTitle("Dequeue")
            .listStyle(.sidebar)
        } detail: {
            ZStack(alignment: .bottom) {
                detailContentForSelection
                    .frame(maxHeight: .infinity, alignment: .top)
                floatingBanners
            }
        }
        #else
        EmptyView()
        #endif
    }

    @ViewBuilder
    private var detailContentForSelection: some View {
        #if os(iOS)
        switch selectedTab {
        case 0: ArcsView()
        case 1: StacksView()
        case 2: ActivityFeedView()
        case 3: SettingsView()
        default: ArcsView()
        }
        #else
        EmptyView()
        #endif
    }

    private var floatingBanners: some View {
        #if os(iOS)
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
        #else
        EmptyView()
        #endif
    }

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

        // DEQ-142: Fetch stack/task lazily only when deep link is triggered
        // This avoids 2 @Query fetches on every MainTabView init
        let targetStack: Stack? = findTargetStack(for: destination)

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

    /// Lazily fetches the target stack for a deep link destination
    /// DEQ-142: Moved from @Query properties to on-demand fetch
    private func findTargetStack(for destination: DeepLinkDestination) -> Stack? {
        switch destination.parentType {
        case .stack:
            // Fetch single stack by ID
            let stackId = destination.parentId
            let predicate = #Predicate<Stack> { stack in
                stack.id == stackId && !stack.isDeleted
            }
            var descriptor = FetchDescriptor<Stack>(predicate: predicate)
            descriptor.fetchLimit = 1
            return try? modelContext.fetch(descriptor).first

        case .task:
            // Fetch single task by ID and get its parent stack
            let taskId = destination.parentId
            let predicate = #Predicate<QueueTask> { task in
                task.id == taskId && !task.isDeleted
            }
            var descriptor = FetchDescriptor<QueueTask>(predicate: predicate)
            descriptor.fetchLimit = 1
            return try? modelContext.fetch(descriptor).first?.stack

        case .arc:
            // Arcs don't have a detail view yet - could navigate to Arcs tab in future
            return nil
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
