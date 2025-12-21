//
//  MainTabView.swift
//  Dequeue
//
//  Main tab-based navigation for authenticated users
//

import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

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

            AddStackView()
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
        } detail: {
            switch selectedTab {
            case 0:
                HomeView()
            case 1:
                DraftsView()
            case 2:
                AddStackView()
            case 3:
                CompletedStacksView()
            case 4:
                SettingsView()
            default:
                HomeView()
            }
        }
    }
    #endif
}

#Preview {
    MainTabView()
        .modelContainer(for: [Stack.self, Task.self, Reminder.self], inMemory: true)
}
