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

    var body: some View {
        #if os(macOS)
        macOSLayout
        #else
        iOSLayout
        #endif
    }

    // MARK: - iOS/iPadOS Layout

    private var iOSLayout: some View {
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
        .sheet(isPresented: $showAddSheet) {
            AddStackView()
        }
    }
    #endif
}

#Preview {
    MainTabView()
        .modelContainer(for: [Stack.self, QueueTask.self, Reminder.self], inMemory: true)
}
