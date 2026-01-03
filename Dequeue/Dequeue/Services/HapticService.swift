//
//  HapticService.swift
//  Dequeue
//
//  Haptic feedback service for tactile user experience
//

#if canImport(UIKit)
import UIKit
#endif

/// Provides haptic feedback for key user actions.
/// Gracefully degrades on macOS where haptics are not available.
enum HapticService {
    // MARK: - Feedback Types

    /// Triggers a success haptic (task completion, successful action)
    static func success() {
        #if canImport(UIKit) && !os(macOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
    }

    /// Triggers an error haptic (failed action, validation error)
    static func error() {
        #if canImport(UIKit) && !os(macOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
        #endif
    }

    /// Triggers a warning haptic (destructive action confirmation)
    static func warning() {
        #if canImport(UIKit) && !os(macOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
        #endif
    }

    /// Triggers a selection haptic (tap, selection change)
    static func selection() {
        #if canImport(UIKit) && !os(macOS)
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
        #endif
    }

    /// Triggers an impact haptic with specified style
    /// - Parameter style: The intensity of the impact (light, medium, heavy)
    static func impact(_ style: ImpactStyle = .medium) {
        #if canImport(UIKit) && !os(macOS)
        let generator = UIImpactFeedbackGenerator(style: style.uiKitStyle)
        generator.impactOccurred()
        #endif
    }

    // MARK: - Impact Styles

    enum ImpactStyle {
        case light
        case medium
        case heavy
        case soft
        case rigid

        #if canImport(UIKit) && !os(macOS)
        var uiKitStyle: UIImpactFeedbackGenerator.FeedbackStyle {
            switch self {
            case .light: return .light
            case .medium: return .medium
            case .heavy: return .heavy
            case .soft: return .soft
            case .rigid: return .rigid
            }
        }
        #endif
    }
}
