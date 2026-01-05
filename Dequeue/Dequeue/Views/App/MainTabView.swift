//
//  MainTabView.swift
//  Dequeue
//
//  Main tab-based navigation for authenticated users
//

import SwiftUI
import SwiftData

struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var showAddSheet = false
    @State private var activeStackForDetail: Stack?

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
    #endif

    private var iOSLayout: some View {
        #if os(iOS)
        ZStack(alignment: .bottom) {
            // Main content area with TabView (hidden tab bar)
            TabView(selection: $selectedTab) {
                HomeView()
                    .tag(0)

                DraftsView()
                    .tag(1)

                CompletedStacksView()
                    .tag(2)

                SettingsView()
                    .tag(3)
            }
            .toolbar(.hidden, for: .tabBar)

            // Bottom area: Active Stack Banner + Custom Tab Bar
            VStack(spacing: 12) {
                // Active Stack Banner (above tab bar)
                activeStackBanner
                    .frame(maxWidth: isIPad ? 400 : .infinity)
                    .padding(.horizontal, 16)

                // Custom Tab Bar
                CustomTabBar(
                    selectedTab: $selectedTab,
                    onAddTapped: { showAddSheet = true }
                )
                .padding(.bottom, 8)
            }
            .background(
                // Subtle gradient background for the bottom area
                LinearGradient(
                    colors: [.clear, Color(.systemBackground).opacity(0.95)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .bottom)
            )
        }
        .sheet(isPresented: $showAddSheet) {
            StackEditorView(mode: .create)
        }
        .sheet(item: $activeStackForDetail) { stack in
            StackEditorView(mode: .edit(stack))
        }
        #else
        EmptyView()
        #endif
    }

    // MARK: - macOS Layout

    #if os(macOS)
    private var macOSLayout: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                NavigationLink(value: 0) {
                    Label("Home", systemImage: "house")
                }
                NavigationLink(value: 1) {
                    Label("Drafts", systemImage: "doc")
                }
                NavigationLink(value: 2) {
                    Label("Completed", systemImage: "checkmark.circle")
                }
                NavigationLink(value: 3) {
                    Label("Settings", systemImage: "gear")
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .toolbar {
                ToolbarItem {
                    Button {
                        showAddSheet = true
                    } label: {
                        Label("Add Stack", systemImage: "plus")
                    }
                }
            }
        } detail: {
            ZStack(alignment: .bottom) {
                detailContent
                    .frame(maxHeight: .infinity, alignment: .top)

                activeStackBanner
                    .padding(.horizontal)
                    .padding(.bottom, 16)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            StackEditorView(mode: .create)
        }
        .sheet(item: $activeStackForDetail) { stack in
            StackEditorView(mode: .edit(stack))
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedTab {
        case 0:
            HomeView()
        case 1:
            DraftsView()
        case 2:
            CompletedStacksView()
        case 3:
            SettingsView()
        default:
            HomeView()
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
                selectedTab = 0 // Navigate to Home tab
            }
        )
    }
}

#Preview {
    MainTabView()
        .modelContainer(for: [Stack.self, QueueTask.self, Reminder.self], inMemory: true)
}
