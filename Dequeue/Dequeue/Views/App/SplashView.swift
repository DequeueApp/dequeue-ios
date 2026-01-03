//
//  SplashView.swift
//  Dequeue
//
//  Splash screen shown while checking authentication state
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Minimal splash screen displayed during app launch while auth state loads
struct SplashView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text("Dequeue")
                .font(.largeTitle)
                .fontWeight(.bold)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(iOS)
        .background(Color(.systemBackground))
        #else
        .background(Color(NSColor.windowBackgroundColor))
        #endif
    }
}

#Preview {
    SplashView()
}
