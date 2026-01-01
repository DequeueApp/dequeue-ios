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
    @State private var previousTab = 0
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
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house")
                }
                .tag(0)

            DraftsView()
                .tabItem {
                    Label("Drafts", systemImage: "doc")
                }
                .tag(1)

            // Placeholder for Add tab - actual view presented as sheet
            Color.clear
                .tabItem {
                    Label("Add", systemImage: "plus.circle")
                }
                .tag(2)

            CompletedStacksView()
                .tabItem {
                    Label("Completed", systemImage: "checkmark.circle")
                }
                .tag(3)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(4)
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            if newValue == 2 {
                // Add tab selected - show sheet and return to previous tab
                selectedTab = oldValue
                showAddSheet = true
            }
            previousTab = oldValue
        }
        .sheet(isPresented: $showAddSheet) {
            AddStackView()
        }
        .sheet(item: $activeStackForDetail) { stack in
            StackDetailView(stack: stack)
        }
        .overlay(alignment: .bottom) {
            GeometryReader { geometry in
                activeStackBanner
                    .frame(maxWidth: isIPad ? min(400, geometry.size.width / 3) : .infinity)
                    .padding(.horizontal)
                    .padding(.top, 0)
                    .padding(.bottom, geometry.safeAreaInsets.bottom + 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
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
                NavigationLink(value: 3) {
                    Label("Completed", systemImage: "checkmark.circle")
                }
                NavigationLink(value: 4) {
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
            ZStack(alignment: .top) {
                detailContent

                activeStackBanner
                    .padding(.horizontal)
                    .padding(.top, 8)
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddStackView()
        }
        .sheet(item: $activeStackForDetail) { stack in
            StackDetailView(stack: stack)
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedTab {
        case 0:
            HomeView()
        case 1:
            DraftsView()
        case 3:
            CompletedStacksView()
        case 4:
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
