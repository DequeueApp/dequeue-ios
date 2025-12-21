//
//  AuthView.swift
//  Dequeue
//
//  Main authentication view - handles sign in and sign up
//

import SwiftUI

struct AuthView: View {
    @Environment(\.authService) private var authService
    @State private var authMode: AuthMode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var verificationCode = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showVerification = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                // Logo/Header
                VStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.tint)

                    Text("Dequeue")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text(authMode == .signIn ? "Welcome back" : "Create your account")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 40)

                // Auth Form
                if showVerification {
                    verificationForm
                } else {
                    authForm
                }

                Spacer()

                // Toggle Auth Mode
                if !showVerification {
                    Button {
                        withAnimation {
                            authMode = authMode == .signIn ? .signUp : .signIn
                            errorMessage = nil
                        }
                    } label: {
                        Text(authMode == .signIn ? "Don't have an account? Sign up" : "Already have an account? Sign in")
                            .font(.footnote)
                    }
                    .padding(.bottom)
                }
            }
            .padding(.horizontal, 24)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Auth Form

    private var authForm: some View {
        VStack(spacing: 16) {
            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

            SecureField("Password", text: $password)
                .textContentType(authMode == .signIn ? .password : .newPassword)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task {
                    await performAuth()
                }
            } label: {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(authMode == .signIn ? "Sign In" : "Create Account")
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(email.isEmpty || password.isEmpty ? Color.gray : Color.accentColor)
            .foregroundStyle(.white)
            .cornerRadius(12)
            .disabled(email.isEmpty || password.isEmpty || isLoading)
        }
    }

    // MARK: - Verification Form

    private var verificationForm: some View {
        VStack(spacing: 16) {
            Text("Check your email")
                .font(.headline)

            Text("We sent a verification code to \(email)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("Verification Code", text: $verificationCode)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.title2)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task {
                    await verifyCode()
                }
            } label: {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Verify")
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(verificationCode.count < 6 ? Color.gray : Color.accentColor)
            .foregroundStyle(.white)
            .cornerRadius(12)
            .disabled(verificationCode.count < 6 || isLoading)

            Button("Back") {
                withAnimation {
                    showVerification = false
                    verificationCode = ""
                    errorMessage = nil
                }
            }
            .font(.footnote)
        }
    }

    // MARK: - Actions

    private func performAuth() async {
        isLoading = true
        errorMessage = nil

        do {
            if let clerkService = authService as? ClerkAuthService {
                if authMode == .signIn {
                    try await clerkService.signIn(email: email, password: password)
                } else {
                    try await clerkService.signUp(email: email, password: password)
                    withAnimation {
                        showVerification = true
                    }
                }
            } else {
                errorMessage = "Clerk SDK not configured. Add the ClerkSDK package to enable authentication."
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func verifyCode() async {
        isLoading = true
        errorMessage = nil

        do {
            if let clerkService = authService as? ClerkAuthService {
                try await clerkService.verifyEmail(code: verificationCode)
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

// MARK: - Auth Mode

enum AuthMode {
    case signIn
    case signUp
}

// MARK: - Environment Key

private struct AuthServiceKey: EnvironmentKey {
    static let defaultValue: any AuthServiceProtocol = ClerkAuthService()
}

extension EnvironmentValues {
    var authService: any AuthServiceProtocol {
        get { self[AuthServiceKey.self] }
        set { self[AuthServiceKey.self] = newValue }
    }
}

// MARK: - Preview

#Preview {
    AuthView()
}
