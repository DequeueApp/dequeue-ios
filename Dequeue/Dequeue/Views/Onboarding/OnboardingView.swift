//
//  OnboardingView.swift
//  Dequeue
//
//  First-run onboarding experience with animated page transitions,
//  progress indicator, and call-to-action.
//

import SwiftUI

/// Full-screen onboarding view with paginated content.
struct OnboardingView: View {
    @Bindable var service: OnboardingService
    @State private var animateContent = false

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            progressBar

            Spacer()

            // Page content
            pageContent
                .id(service.currentPageIndex)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))

            Spacer()

            // Page dots
            pageDots

            // Action buttons
            actionButtons
                .padding(.bottom, 20)
        }
        .padding()
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                animateContent = true
            }
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 4)

                Capsule()
                    .fill(service.currentPage.accentColor)
                    .frame(
                        width: geometry.size.width * service.progress,
                        height: 4
                    )
                    .animation(.easeInOut(duration: 0.3), value: service.progress)
            }
        }
        .frame(height: 4)
        .padding(.top, 12)
        .accessibilityLabel("Onboarding progress")
        .accessibilityValue(
            "Page \(service.currentPageIndex + 1) of \(service.pages.count)"
        )
    }

    // MARK: - Page Content

    private var pageContent: some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: service.currentPage.systemImage)
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(service.currentPage.accentColor)
                .symbolEffect(.bounce, value: service.currentPageIndex)
                .frame(height: 100)
                .accessibilityHidden(true)

            // Title
            Text(service.currentPage.title)
                .font(.largeTitle.weight(.bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)

            // Subtitle
            Text(service.currentPage.subtitle)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
        }
        .padding(.horizontal)
    }

    // MARK: - Page Dots

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<service.pages.count, id: \.self) { index in
                Circle()
                    .fill(
                        index == service.currentPageIndex
                            ? service.currentPage.accentColor
                            : Color.secondary.opacity(0.3)
                    )
                    .frame(
                        width: index == service.currentPageIndex ? 10 : 8,
                        height: index == service.currentPageIndex ? 10 : 8
                    )
                    .animation(.easeInOut(duration: 0.2), value: service.currentPageIndex)
                    .accessibilityHidden(true)
            }
        }
        .padding(.bottom, 24)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            if service.isLastPage {
                // Get Started button on last page
                Button {
                    withAnimation {
                        service.completeOnboarding()
                    }
                } label: {
                    Text("Get Started")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            service.currentPage.accentColor,
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                }
                .accessibilityLabel("Get started with Dequeue")
            } else {
                // Continue button
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        service.nextPage()
                    }
                } label: {
                    Text("Continue")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            service.currentPage.accentColor,
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                }
                .accessibilityLabel(
                    "Continue to page \(service.currentPageIndex + 2)"
                )
            }

            // Skip / Back row
            HStack {
                if !service.isFirstPage {
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            service.previousPage()
                        }
                    } label: {
                        Text("Back")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Go back to previous page")
                }

                Spacer()

                if !service.isLastPage {
                    Button {
                        withAnimation {
                            service.completeOnboarding()
                        }
                    } label: {
                        Text("Skip")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Skip onboarding")
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

/// Gesture wrapper that adds swipe support to the onboarding view.
struct OnboardingSwipeWrapper: View {
    @Bindable var service: OnboardingService

    var body: some View {
        OnboardingView(service: service)
            .gesture(
                DragGesture(minimumDistance: 50)
                    .onEnded { value in
                        if value.translation.width < -50 {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                service.nextPage()
                            }
                        } else if value.translation.width > 50 {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                service.previousPage()
                            }
                        }
                    }
            )
    }
}
