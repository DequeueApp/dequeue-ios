//
//  HapticManager.swift
//  Dequeue
//
//  Manages haptic feedback for user actions
//

import SwiftUI

#if os(iOS)
import UIKit
#endif

/// Centralized manager for haptic feedback across the app
@MainActor
final class HapticManager {
    /// Shared singleton instance
    static let shared = HapticManager()
    
    private init() {}
    
    /// Triggers a success haptic (e.g., task completion, successful action)
    func success() {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
    }
    
    /// Triggers a selection haptic (e.g., selecting an item, activating a stack)
    func selection() {
        #if os(iOS)
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
        #endif
    }
    
    /// Triggers a warning haptic (e.g., delete confirmation, destructive action)
    func warning() {
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        #endif
    }
    
    /// Triggers a light impact haptic (e.g., drag operations)
    func impact(style: ImpactStyle = .light) {
        #if os(iOS)
        let generator: UIImpactFeedbackGenerator
        switch style {
        case .light:
            generator = UIImpactFeedbackGenerator(style: .light)
        case .medium:
            generator = UIImpactFeedbackGenerator(style: .medium)
        case .heavy:
            generator = UIImpactFeedbackGenerator(style: .heavy)
        }
        generator.impactOccurred()
        #endif
    }
    
    /// Haptic impact styles
    enum ImpactStyle {
        case light
        case medium
        case heavy
    }
}
