//
//  MainTabView.swift
//  Dequeue
//
//  Main tab-based navigation for authenticated users
//  Uses native TabView with Liquid Glass (iOS 26+)
//

import SwiftUI
import SwiftData

struct MainTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.syncManager) private var syncManager
    @Environment(\.authService) private var authService

    @State private var selectedTab = 0
    @State private var cachedDeviceId: String = ""
    @State private var showStackPicker = false
    @State private var activeStackForDetail: Stack?
    @State private var undoCompletionManager = UndoCompletionManager()

    var body: some View {
        #if os(macOS)
        macOSLayout
        #else
        iOSLayout
        #endif
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
        ZStack(alignment: .bottom) {
            // Native TabView with Liquid Glass (automatic in iOS 26)
            TabView(selection: $selectedTab) {
                StacksView()
                    .tabItem {
                        Label("Stacks", systemImage: "square.stack.3d.up")
                    }
                    .tag(0)

                ActivityFeedView()
                    .tabItem {
                        Label("Activity", systemImage: "clock.arrow.circlepath")
                    }
                    .tag(1)

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
                    .tag(2)
            }

            // Floating banners positioned above tab bar
            floatingBanners
        }
        .sheet(isPresented: $showStackPicker) {
            StackPickerSheet()
        }
        .sheet(item: $activeStackForDetail) { stack in
            StackEditorView(mode: .edit(stack))
        }
        .environment(\.undoCompletionManager, undoCompletionManager)
        .task {
            // Fetch device ID if not cached
            if cachedDeviceId.isEmpty {
                cachedDeviceId = await DeviceService.shared.getDeviceId()
            }
            // Configure the undo completion manager with required dependencies
            undoCompletionManager.configure(
                modelContext: modelContext,
                syncManager: syncManager,
                userId: authService.currentUserId ?? "",
                deviceId: cachedDeviceId
            )
        }
        #else
        EmptyView()
        #endif
    }

    #if os(iOS)
    private var floatingBanners: some View {
        GeometryReader { geometry in
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
            // Position above tab bar: safe area + tab bar height + padding
            .padding(.bottom, geometry.safeAreaInsets.bottom + tabBarHeight + 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .animation(.easeInOut(duration: 0.25), value: undoCompletionManager.hasPendingCompletion)
        }
    }

    #endif

    // MARK: - macOS Layout

    #if os(macOS)
    private var macOSLayout: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                NavigationLink(value: 0) {
                    Label("Stacks", systemImage: "square.stack.3d.up")
                }
                NavigationLink(value: 1) {
                    Label("Activity", systemImage: "clock.arrow.circlepath")
                }
                NavigationLink(value: 3) {
                    Label("Settings", systemImage: "gear")
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            ZStack(alignment: .bottom) {
                detailContent
                    .frame(maxHeight: .infinity, alignment: .top)

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
                .padding(.horizontal)
                .padding(.bottom, 16)
                .animation(.easeInOut(duration: 0.25), value: undoCompletionManager.hasPendingCompletion)
            }
        }
        .sheet(isPresented: $showStackPicker) {
            StackPickerSheet()
        }
        .sheet(item: $activeStackForDetail) { stack in
            StackEditorView(mode: .edit(stack))
        }
        .environment(\.undoCompletionManager, undoCompletionManager)
        .task {
            // Fetch device ID if not cached
            if cachedDeviceId.isEmpty {
                cachedDeviceId = await DeviceService.shared.getDeviceId()
            }
            // Configure the undo completion manager with required dependencies
            undoCompletionManager.configure(
                modelContext: modelContext,
                syncManager: syncManager,
                userId: authService.currentUserId ?? "",
                deviceId: cachedDeviceId
            )
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedTab {
        case 0:
            StacksView()
        case 1:
            ActivityFeedView()
        case 3:
            SettingsView()
        default:
            StacksView()
        }
    }
    #endif

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
