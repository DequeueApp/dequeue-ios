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
    @State private var twoFactorCode = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showVerification = false
    @State private var show2FA = false

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
                if show2FA {
                    twoFactorForm
                } else if showVerification {
                    verificationForm
                } else {
                    authForm
                }

                Spacer()

                // Toggle Auth Mode
                if !showVerification && !show2FA {
                    Button {
                        withAnimation {
                            authMode = authMode == .signIn ? .signUp : .signIn
                            errorMessage = nil
                        }
                    } label: {
                        Text(authMode == .signIn ?
                             "Don't have an account? Sign up" :
                             "Already have an account? Sign in")
                            .font(.footnote)
                    }
                    .padding(.bottom)
                }
            }
            .padding(.horizontal, 24)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    // MARK: - Auth Form

    private var authForm: some View {
        VStack(spacing: 16) {
            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                #if os(iOS)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                #endif
                .autocorrectionDisabled()
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                .accessibilityIdentifier("emailField")

            SecureField("Password", text: $password)
                .textContentType(authMode == .signIn ? .password : .newPassword)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                .accessibilityIdentifier("passwordField")

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
                HStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text(authMode == .signIn ? "Sign In" : "Create Account")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
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
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .multilineTextAlignment(.center)
                .font(.title2)
                .padding()
                .background(Color.gray.opacity(0.1))
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

    // MARK: - Two-Factor Form

    private var twoFactorForm: some View {
        VStack(spacing: 16) {
            Text("Device Verification")
                .font(.headline)

            Text("This is your first login on this device. Check your email for a verification code.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            TextField("Verification Code", text: $twoFactorCode)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
                .multilineTextAlignment(.center)
                .font(.title2)
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task {
                    await verify2FA()
                }
            } label: {
                HStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("Verify Code")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .disabled(twoFactorCode.count < 6 || isLoading)

            Button("Back") {
                withAnimation {
                    show2FA = false
                    twoFactorCode = ""
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
            guard let clerkService = authService as? ClerkAuthService else {
                errorMessage = "Authentication service not available"
                isLoading = false
                return
            }

            if authMode == .signIn {
                try await clerkService.signIn(email: email, password: password)
            } else {
                try await clerkService.signUp(email: email, password: password)
                withAnimation {
                    showVerification = true
                }
            }
        } catch let error as AuthError where error == .twoFactorRequired {
            // Show 2FA form
            withAnimation {
                show2FA = true
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
            guard let clerkService = authService as? ClerkAuthService else {
                errorMessage = "Authentication service not available"
                isLoading = false
                return
            }
            try await clerkService.verifyEmail(code: verificationCode)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func verify2FA() async {
        isLoading = true
        errorMessage = nil

        do {
            guard let clerkService = authService as? ClerkAuthService else {
                errorMessage = "Authentication service not available"
                isLoading = false
                return
            }
            try await clerkService.verify2FACode(code: twoFactorCode)
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
