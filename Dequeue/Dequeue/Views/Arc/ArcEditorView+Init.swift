//
//  ArcEditorView+Init.swift
//  Dequeue
//
//  Arc editor initialization and data loading
//

import SwiftUI

// MARK: - Initialization Extension

extension ArcEditorView {
    // MARK: - Initialization

    func initializeServices() async {
        if cachedDeviceId.isEmpty {
            cachedDeviceId = await DeviceService.shared.getDeviceId()
        }

        let userId = authService.currentUserId ?? ""

        if arcService == nil {
            arcService = ArcService(
                modelContext: modelContext,
                userId: userId,
                deviceId: cachedDeviceId,
                syncManager: syncManager
            )
        }

        if attachmentService == nil {
            attachmentService = AttachmentService(
                modelContext: modelContext,
                userId: userId,
                deviceId: cachedDeviceId,
                syncManager: syncManager
            )
        }

        if reminderActionHandler == nil {
            reminderActionHandler = ReminderActionHandler(
                modelContext: modelContext,
                userId: userId,
                deviceId: cachedDeviceId,
                onError: { [self] error in
                    errorMessage = error.localizedDescription
                    showError = true
                },
                syncManager: syncManager
            )
        }
    }

    func loadArcData() {
        if let arc = editingArc {
            title = arc.title
            arcDescription = arc.arcDescription ?? ""
            selectedColorHex = arc.colorHex ?? "5E5CE6"
        }
    }
}
