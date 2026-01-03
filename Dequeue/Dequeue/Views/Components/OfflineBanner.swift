//
//  OfflineBanner.swift
//  Dequeue
//
//  Banner displayed when app is offline with pending changes
//

import SwiftUI

struct OfflineBanner: View {
    let pendingCount: Int
    @Binding var isDismissed: Bool

    var body: some View {
        if !isDismissed {
            HStack(spacing: 12) {
                Image(systemName: "wifi.slash")
                    .foregroundStyle(.white)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Offline Mode")
                        .font(.headline)
                        .foregroundStyle(.white)

                    if pendingCount > 0 {
                        Text("\(pendingCount) change\(pendingCount == 1 ? "" : "s") will sync when online")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.9))
                    } else {
                        Text("You're currently offline")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }

                Spacer()

                Button {
                    withAnimation {
                        isDismissed = true
                    }
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(.white.opacity(0.8))
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss offline banner")
            }
            .padding()
            .background(Color.orange.gradient)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

#Preview("With Pending Changes") {
    @Previewable @State var isDismissed = false
    OfflineBanner(pendingCount: 5, isDismissed: $isDismissed)
        .padding()
}

#Preview("Without Pending Changes") {
    @Previewable @State var isDismissed = false
    OfflineBanner(pendingCount: 0, isDismissed: $isDismissed)
        .padding()
}
