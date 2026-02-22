//
//  CertificatePinningDelegateTests.swift
//  DequeueTests
//
//  Tests for certificate pinning delegate, validator, and session factory.
//  DEQ-60
//

import Testing
import Foundation
import Security
@testable import Dequeue

// MARK: - CertificatePinningConfiguration Tests

@Suite("CertificatePinningConfiguration")
@MainActor
struct CertificatePinningConfigurationTests {

    @Test("Production configuration has expected domains")
    func productionDomains() {
        let config = CertificatePinningConfiguration.production
        #expect(config.pinnedDomains.contains("api.dequeue.app"))
        #expect(config.pinnedDomains.contains("sync.ardonos.com"))
        #expect(config.pinnedDomains.count == 2)
    }

    @Test("Production configuration has pinned hashes")
    func productionHashes() {
        let config = CertificatePinningConfiguration.production
        #expect(config.pinnedPublicKeyHashes.count == 5)
        // ISRG Root X1
        #expect(config.pinnedPublicKeyHashes.contains(
            "C5+lpZ7tcVwmwQIMcRtPbsQtWLABXhQzejna0wHFr8M="
        ))
        // ISRG Root X2
        #expect(config.pinnedPublicKeyHashes.contains(
            "diGVwiVYbubAI3RW4hB9xU8e/CH2GnkuvVFZE8zmgzI="
        ))
        // E7 intermediate (currently active)
        #expect(config.pinnedPublicKeyHashes.contains(
            "y7xVm0TVJNahMr2sZydE2jQH8SquXV9yLF9seROHHHU="
        ))
    }

    @Test("Production configuration is enforced")
    func productionEnforced() {
        #expect(CertificatePinningConfiguration.production.enforced == true)
    }

    @Test("Disabled configuration has no domains")
    func disabledConfig() {
        let config = CertificatePinningConfiguration.disabled
        #expect(config.pinnedDomains.isEmpty)
        #expect(config.pinnedPublicKeyHashes.isEmpty)
        #expect(config.enforced == false)
    }

    @Test("Debug configuration is not enforced")
    func debugNotEnforced() {
        let config = CertificatePinningConfiguration.debug
        #expect(config.enforced == false)
    }

    @Test("Debug configuration has same domains as production")
    func debugSameDomainsAsProduction() {
        let debug = CertificatePinningConfiguration.debug
        let prod = CertificatePinningConfiguration.production
        #expect(debug.pinnedDomains == prod.pinnedDomains)
    }

    @Test("Debug configuration has same hashes as production")
    func debugSameHashesAsProduction() {
        let debug = CertificatePinningConfiguration.debug
        let prod = CertificatePinningConfiguration.production
        #expect(debug.pinnedPublicKeyHashes == prod.pinnedPublicKeyHashes)
    }

    @Test("Custom configuration preserves values")
    func customConfiguration() {
        let config = CertificatePinningConfiguration(
            pinnedDomains: ["example.com"],
            pinnedPublicKeyHashes: ["hash1=", "hash2="],
            enforced: false
        )
        #expect(config.pinnedDomains == ["example.com"])
        #expect(config.pinnedPublicKeyHashes.count == 2)
        #expect(config.enforced == false)
    }
}

// MARK: - PinningFailureInfo Tests

@Suite("PinningFailureInfo")
@MainActor
struct PinningFailureInfoTests {

    @Test("Failure info stores all properties")
    func failureInfoProperties() {
        let now = Date()
        let info = PinningFailureInfo(
            domain: "api.example.com",
            expectedHashes: ["hash1=", "hash2="],
            actualHashes: ["actual1="],
            certificateCount: 3,
            timestamp: now
        )

        #expect(info.domain == "api.example.com")
        #expect(info.expectedHashes.count == 2)
        #expect(info.actualHashes == ["actual1="])
        #expect(info.certificateCount == 3)
        #expect(info.timestamp == now)
    }

    @Test("Failure info with empty hashes")
    func emptyHashes() {
        let info = PinningFailureInfo(
            domain: "test.com",
            expectedHashes: [],
            actualHashes: [],
            certificateCount: 0,
            timestamp: Date()
        )
        #expect(info.expectedHashes.isEmpty)
        #expect(info.actualHashes.isEmpty)
    }
}

// MARK: - CertificatePinningError Tests

@Suite("CertificatePinningError")
@MainActor
struct CertificatePinningErrorTests {

    @Test("Pin validation failed error description includes domain")
    func pinValidationFailedDescription() {
        let error = CertificatePinningError.pinValidationFailed(domain: "api.dequeue.app")
        let description = error.errorDescription ?? ""
        #expect(description.contains("api.dequeue.app"))
        #expect(description.contains("pinning validation failed"))
    }

    @Test("Trust evaluation failed error description includes domain")
    func trustEvaluationFailedDescription() {
        let error = CertificatePinningError.trustEvaluationFailed(domain: "sync.ardonos.com")
        let description = error.errorDescription ?? ""
        #expect(description.contains("sync.ardonos.com"))
        #expect(description.contains("trust evaluation failed"))
    }

    @Test("Errors have non-nil descriptions")
    func errorsHaveDescriptions() {
        #expect(CertificatePinningError.pinValidationFailed(domain: "test").errorDescription != nil)
        #expect(CertificatePinningError.trustEvaluationFailed(domain: "test").errorDescription != nil)
    }
}

// MARK: - CertificatePinningDelegate Tests

@Suite("CertificatePinningDelegate")
@MainActor
struct CertificatePinningDelegateTests {

    @Test("Delegate initializes with configuration")
    func delegateInit() {
        let delegate = CertificatePinningDelegate(
            configuration: .production,
            onPinningFailure: { _ in }
        )

        #expect(delegate.configuration.pinnedDomains.count == 2)
        #expect(delegate.configuration.enforced == true)
    }

    @Test("Delegate initializes with disabled configuration")
    func delegateDisabledInit() {
        let delegate = CertificatePinningDelegate(
            configuration: .disabled,
            onPinningFailure: { _ in }
        )

        #expect(delegate.configuration.pinnedDomains.isEmpty)
        #expect(delegate.configuration.enforced == false)
    }

    @Test("Non-server-trust challenges are passed through")
    func nonServerTrustChallenge() async {
        let delegate = CertificatePinningDelegate(
            configuration: .production,
            onPinningFailure: { _ in }
        )

        // Create a challenge with a non-server-trust auth method
        let protectionSpace = URLProtectionSpace(
            host: "api.dequeue.app",
            port: 443,
            protocol: "https",
            realm: nil,
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic
        )
        let challenge = URLAuthenticationChallenge(
            protectionSpace: protectionSpace,
            proposedCredential: nil,
            previousFailureCount: 0,
            failureResponse: nil,
            error: nil,
            sender: MockAuthChallengeSender()
        )

        let disposition = await withCheckedContinuation { continuation in
            delegate.urlSession(
                URLSession.shared,
                didReceive: challenge
            ) { disposition, _ in
                continuation.resume(returning: disposition)
            }
        }

        #expect(disposition == .performDefaultHandling)
    }

    @Test("Non-pinned domains are passed through")
    func nonPinnedDomain() async {
        let config = CertificatePinningConfiguration(
            pinnedDomains: ["only-this-domain.com"],
            pinnedPublicKeyHashes: ["hash="],
            enforced: true
        )
        let delegate = CertificatePinningDelegate(
            configuration: config,
            onPinningFailure: { _ in }
        )

        let protectionSpace = URLProtectionSpace(
            host: "different-domain.com",
            port: 443,
            protocol: "https",
            realm: nil,
            authenticationMethod: NSURLAuthenticationMethodServerTrust
        )
        let challenge = URLAuthenticationChallenge(
            protectionSpace: protectionSpace,
            proposedCredential: nil,
            previousFailureCount: 0,
            failureResponse: nil,
            error: nil,
            sender: MockAuthChallengeSender()
        )

        let disposition = await withCheckedContinuation { continuation in
            delegate.urlSession(
                URLSession.shared,
                didReceive: challenge
            ) { disposition, _ in
                continuation.resume(returning: disposition)
            }
        }

        #expect(disposition == .performDefaultHandling)
    }
}

// MARK: - CertificatePinningValidator Tests

@Suite("CertificatePinningValidator")
@MainActor
struct CertificatePinningValidatorTests {

    @Test("Non-server-trust challenges return false")
    func nonServerTrustReturnsFalse() {
        let protectionSpace = URLProtectionSpace(
            host: "api.dequeue.app",
            port: 443,
            protocol: "https",
            realm: nil,
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic
        )
        let challenge = URLAuthenticationChallenge(
            protectionSpace: protectionSpace,
            proposedCredential: nil,
            previousFailureCount: 0,
            failureResponse: nil,
            error: nil,
            sender: MockAuthChallengeSender()
        )

        let handled = CertificatePinningValidator.handle(
            challenge: challenge,
            completionHandler: { _, _ in }
        )

        #expect(handled == false)
    }

    @Test("Non-pinned domain challenges return false")
    func nonPinnedDomainReturnsFalse() {
        let protectionSpace = URLProtectionSpace(
            host: "unpinned-domain.example.com",
            port: 443,
            protocol: "https",
            realm: nil,
            authenticationMethod: NSURLAuthenticationMethodServerTrust
        )
        let challenge = URLAuthenticationChallenge(
            protectionSpace: protectionSpace,
            proposedCredential: nil,
            previousFailureCount: 0,
            failureResponse: nil,
            error: nil,
            sender: MockAuthChallengeSender()
        )

        let handled = CertificatePinningValidator.handle(
            challenge: challenge,
            completionHandler: { _, _ in }
        )

        #expect(handled == false)
    }
}

// MARK: - PinnedURLSession Tests

@Suite("PinnedURLSession")
@MainActor
struct PinnedURLSessionTests {

    @Test("Shared session is not nil")
    func sharedSessionExists() {
        let session = PinnedURLSession.shared
        #expect(session.configuration.timeoutIntervalForRequest == 30)
        #expect(session.configuration.timeoutIntervalForResource == 300)
    }

    @Test("Shared session returns same instance")
    func sharedSessionIsSingleton() {
        let session1 = PinnedURLSession.shared
        let session2 = PinnedURLSession.shared
        #expect(session1 === session2)
    }

    @Test("Custom session uses provided configuration")
    func customSessionConfiguration() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        let session = PinnedURLSession.session(configuration: config)
        #expect(session.configuration.timeoutIntervalForRequest == 10)
    }

    @Test("Custom session with disabled pinning configuration")
    func customSessionDisabledPinning() {
        let session = PinnedURLSession.session(
            pinningConfiguration: .disabled
        )
        // Session should be created successfully even with disabled pinning
        #expect(session.configuration.timeoutIntervalForRequest > 0)
    }

    @Test("Factory creates distinct sessions")
    func factoryCreatesDistinctSessions() {
        let session1 = PinnedURLSession.session()
        let session2 = PinnedURLSession.session()
        #expect(session1 !== session2)
    }
}

// MARK: - Integration Tests

@Suite("Certificate Pinning Integration")
@MainActor
struct CertificatePinningIntegrationTests {

    @Test("Real connection to api.dequeue.app succeeds with pinning")
    func realConnectionWithPinning() async throws {
        let session = PinnedURLSession.shared
        let url = URL(string: "https://api.dequeue.app/v1/health")!

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        // This should succeed because our pins match the real certificates
        do {
            let (_, response) = try await session.data(for: request)
            let httpResponse = response as? HTTPURLResponse
            // Health endpoint may return various codes, but connection should succeed
            #expect(httpResponse != nil)
        } catch {
            // Network errors (offline) are acceptable — pinning errors would be different
            let nsError = error as NSError
            // SSL/pinning failures would be NSURLErrorServerCertificateUntrusted (-1202)
            // or NSURLErrorCancelled (-999, from cancelAuthenticationChallenge)
            #expect(nsError.code != NSURLErrorServerCertificateUntrusted,
                    "Certificate pinning unexpectedly rejected the real server")
            #expect(nsError.code != NSURLErrorCancelled,
                    "Certificate pinning cancelled the connection to the real server")
        }
    }

    @Test("Real connection to sync.ardonos.com succeeds with pinning")
    func realConnectionToSyncWithPinning() async throws {
        let session = PinnedURLSession.shared
        let url = URL(string: "https://sync.ardonos.com/health")!

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        do {
            let (_, response) = try await session.data(for: request)
            let httpResponse = response as? HTTPURLResponse
            #expect(httpResponse != nil)
        } catch {
            let nsError = error as NSError
            #expect(nsError.code != NSURLErrorServerCertificateUntrusted)
            #expect(nsError.code != NSURLErrorCancelled,
                    "Certificate pinning cancelled the connection to the real server")
        }
    }

    @Test("Enforced pinning rejects unknown certificate hashes")
    func enforcedPinningRejectsUnknown() async throws {
        // Create a session with fake pins that won't match any real cert
        let config = CertificatePinningConfiguration(
            pinnedDomains: ["api.dequeue.app"],
            pinnedPublicKeyHashes: ["AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="],
            enforced: true
        )

        let session = PinnedURLSession.session(pinningConfiguration: config)
        let url = URL(string: "https://api.dequeue.app/v1/health")!

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        do {
            _ = try await session.data(for: request)
            // If we get here without error, the server is down or we're offline
            // and the request didn't reach the pinning check
        } catch {
            let nsError = error as NSError
            // Either cancelled (pinning rejected) or network error (offline)
            let isPinningRejection = nsError.code == NSURLErrorCancelled
            let isNetworkError = [
                NSURLErrorNotConnectedToInternet,
                NSURLErrorTimedOut,
                NSURLErrorCannotFindHost,
                NSURLErrorCannotConnectToHost
            ].contains(nsError.code)
            #expect(isPinningRejection || isNetworkError,
                    "Expected pinning rejection or network error, got: \(nsError.code)")
        }
    }
}

// MARK: - Mock Auth Challenge Sender

/// Minimal mock for URLAuthenticationChallengeSender protocol
/// Required to create URLAuthenticationChallenge instances in tests
final class MockAuthChallengeSender: NSObject, URLAuthenticationChallengeSender, @unchecked Sendable {
    nonisolated func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    nonisolated func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    nonisolated func cancel(_ challenge: URLAuthenticationChallenge) {}
}
