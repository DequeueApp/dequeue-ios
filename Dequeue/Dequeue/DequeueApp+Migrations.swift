//
//  DequeueApp+Migrations.swift
//  Dequeue
//
//  Data migration logic for DequeueApp
//

import SwiftUI
import SwiftData
import os

extension DequeueApp {
    /// DEQ-197: Merges duplicate tags that were created across devices before the sync fix.
    /// This migration runs every app launch until no duplicates are found, since new duplicates
    /// may arrive from older clients that haven't been updated yet.
    func runDuplicateTagMigration() async {
        do {
            let result = try TagService.mergeDuplicateTags(modelContext: modelContext)
            if result.duplicateGroupsFound > 0 {
                os_log(
                    "[Migration] Merged \(result.tagsMerged) tags in \(result.duplicateGroupsFound) groups"
                )
                ErrorReportingService.addBreadcrumb(
                    category: "migration",
                    message: "Merged duplicate tags",
                    data: [
                        "duplicate_groups": result.duplicateGroupsFound,
                        "tags_merged": result.tagsMerged,
                        "stacks_updated": result.stacksUpdated
                    ]
                )
            }
        } catch {
            os_log("[Migration] Failed to merge duplicate tags: \(error.localizedDescription)")
            ErrorReportingService.capture(
                error: error,
                context: ["source": "duplicate_tag_migration"]
            )
        }
    }
}
