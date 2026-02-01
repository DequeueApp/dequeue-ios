//
//  ContentView.swift
//  Dequeue
//
//  Created by Victor Quinn on 12/21/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(
        filter: #Predicate<Stack> { stack in
            stack.isDeleted == false && stack.isDraft == false
        },
        sort: \Stack.updatedAt,
        order: .reverse
    ) private var stacks: [Stack]

    var body: some View {
        NavigationSplitView {
            List {
                ForEach(stacks) { stack in
                    NavigationLink {
                        Text("Stack: \(stack.title)")
                    } label: {
                        VStack(alignment: .leading) {
                            Text(stack.title)
                                .font(.headline)
                            if let activeTask = stack.activeTask {
                                Text(activeTask.title)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete(perform: deleteStacks)
            }
            #if os(macOS)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            #endif
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
                #endif
                ToolbarItem {
                    Button(action: addStack) {
                        Label("Add Stack", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("Dequeue")
        } detail: {
            Text("Select a stack")
        }
    }

    private func addStack() {
        withAnimation {
            let newStack = Stack(title: "New Stack")
            modelContext.insert(newStack)
        }
    }

    private func deleteStacks(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                stacks[index].isDeleted = true
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Stack.self, QueueTask.self, Reminder.self], inMemory: true)
}
// CI trigger Sat Jan 31 22:09:00 EST 2026
