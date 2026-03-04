//
//  CertificatePinningDelegate.swift
//  Dequeue
//
//  URLSession delegate that validates server certificates against pinned public keys.
//  Protects against MITM attacks by ensuring API connections use expected certificates.
//  DEQ-60
//
//  Note: This entire file uses explicit nonisolated annotations because the Dequeue target
//  uses SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor. Certificate pinning must be nonisolated
//  since URLSession delegates are called on background threads.
//

import Foundation
import CommonCrypto
import Security
import os.log

// MARK: - Certificate Pinning Configuration

/// Configuration for certificate pinning, defining which domains and pins to enforce.
nonisolated struct CertificatePinningConfiguration: Sendable {
    /// Domains that require certificate pinning validation
    let pinnedDomains: Set<String>

    /// SHA-256 hashes of trusted public keys (base64-encoded).
    /// Includes intermediate CA and root CA pins for Let's Encrypt chain.
    /// We pin to CA keys (not leaf) because leaf certificates rotate every 90 days.
    let pinnedPublicKeyHashes: Set<String>

    /// Whether pinning is enforced. When false, mismatches are logged but connections proceed.
    /// This acts as an emergency kill switch — can be toggled via remote config.
    let enforced: Bool
}

extension CertificatePinningConfiguration {
    /// Default configuration with production pins.
    ///
    /// Hashes are standard SubjectPublicKeyInfo (SPKI) SHA-256 pins, compatible with
    /// openssl and TrustKit. Verified against live servers on 2026-03-04 (DEQ-249).
    ///
    /// We pin to intermediate CA keys (E5/E6/E7) rather than leaf certificates because
    /// Let's Encrypt leaf certs rotate every 90 days. The ISRG root pins are included
    /// as a fallback in case the root appears in the trust chain on some iOS versions.
    ///
    /// To verify these hashes:
    ///   echo | openssl s_client -connect api.dequeue.app:443 -showcerts 2>/dev/null | \
    ///     openssl x509 -pubkey -noout | openssl pkey -pubin -outform DER | \
    ///     openssl dgst -sha256 -binary | base64
    nonisolated static let production = CertificatePinningConfiguration(
        pinnedDomains: [
            "api.dequeue.app",
            "sync.ardonos.com"
        ],
        pinnedPublicKeyHashes: [
            "C5+lpZ7tcVwmwQIMcRtPbsQtWLABXhQzejna0wHFr8M=", // ISRG Root X1 (RSA 4096) — Let's Encrypt root
            "diGVwiVYbubAI3RW4hB9xU8e/CH2GnkuvVFZE8zmgzI=", // ISRG Root X2 (EC P-384) — Let's Encrypt ECDSA root
            "NYbU7PBwV4y9J67c4guWTki8FJ+uudrXL0a4V4aRcrg=", // Let's Encrypt E5 intermediate (EC P-384)
            "0Bbh/jEZSKymTy3kTOhsmlHKBB32EDu1KojrP3YfV9c=", // Let's Encrypt E6 intermediate (EC P-384)
            "y7xVm0TVJNahMr2sZydE2jQH8SquXV9yLF9seROHHHU="  // Let's Encrypt E7 intermediate (EC P-384, active)
        ],
        enforced: true
    )

    /// Disabled configuration for testing — allows all connections
    nonisolated static let disabled = CertificatePinningConfiguration(
        pinnedDomains: [],
        pinnedPublicKeyHashes: [],
        enforced: false
    )

    /// Debug configuration — same pins as production but report-only (non-enforced)
    nonisolated static let debug = CertificatePinningConfiguration(
        pinnedDomains: CertificatePinningConfiguration.production.pinnedDomains,
        pinnedPublicKeyHashes: CertificatePinningConfiguration.production.pinnedPublicKeyHashes,
        enforced: false
    )
}

// MARK: - Pinning Failure Info

/// Information about a certificate pinning validation failure
nonisolated struct PinningFailureInfo: Sendable {
    let domain: String
    let expectedHashes: Set<String>
    let actualHashes: [String]
    let certificateCount: Int
    let timestamp: Date
}

// MARK: - Errors

/// Errors related to certificate pinning
nonisolated enum CertificatePinningError: LocalizedError, Sendable {
    case pinValidationFailed(domain: String)
    case trustEvaluationFailed(domain: String)

    nonisolated var errorDescription: String? {
        switch self {
        case .pinValidationFailed(let domain):
            return """
            Certificate pinning validation failed for \(domain). \
            The server's certificate chain did not contain any trusted public keys.
            """
        case .trustEvaluationFailed(let domain):
            return """
            TLS trust evaluation failed for \(domain). \
            The server's certificate may be invalid or expired.
            """
        }
    }
}

// MARK: - Certificate Pinning Delegate

/// URLSession delegate that enforces certificate pinning using public key hashing.
///
/// This delegate validates that server certificates in the TLS chain contain at least one
/// public key matching our pinned hashes. We pin to intermediate and root CA keys rather
/// than leaf certificates, because Let's Encrypt leaf certificates rotate every 90 days.
final class CertificatePinningDelegate: NSObject, URLSessionDelegate, Sendable {
    // nonisolated(unsafe) because Logger is thread-safe but not marked Sendable in current SDK
    nonisolated private static let pinLogger = Logger(
        subsystem: "com.dequeue", category: "CertificatePinning"
    )

    let configuration: CertificatePinningConfiguration
    let onPinningFailure: @Sendable (PinningFailureInfo) -> Void

    nonisolated init(
        configuration: CertificatePinningConfiguration,
        onPinningFailure: @escaping @Sendable (PinningFailureInfo) -> Void
    ) {
        self.configuration = configuration
        self.onPinningFailure = onPinningFailure
        super.init()
    }

    // MARK: - URLSessionDelegate

    nonisolated func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host

        guard configuration.pinnedDomains.contains(host) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let certCount = SecTrustGetCertificateCount(serverTrust)
        let (matched, actualHashes) = Self.validate(
            serverTrust: serverTrust,
            pinnedHashes: configuration.pinnedPublicKeyHashes
        )

        if matched {
            Self.pinLogger.debug("Certificate pinning validated for \(host)")
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            let failureInfo = PinningFailureInfo(
                domain: host,
                expectedHashes: configuration.pinnedPublicKeyHashes,
                actualHashes: actualHashes,
                certificateCount: certCount,
                timestamp: Date()
            )
            onPinningFailure(failureInfo)

            // DEQ-246: Log cert pinning results to Sentry for remote observability
            ErrorReportingService.logCertPinningResult(
                domain: host,
                matched: false,
                hashes: actualHashes
            )

            if configuration.enforced {
                Self.pinLogger.error("Certificate pinning FAILED for \(host) — connection rejected")
                completionHandler(.cancelAuthenticationChallenge, nil)
            } else {
                Self.pinLogger.warning(
                    "Certificate pinning mismatch for \(host) — allowing (not enforced)"
                )
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
            }
        }
    }

    // MARK: - Validation (nonisolated static)

    nonisolated private static func validate(
        serverTrust: SecTrust,
        pinnedHashes: Set<String>
    ) -> (matched: Bool, actualHashes: [String]) {
        var error: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &error) else {
            return (matched: false, actualHashes: [])
        }

        var actualHashes: [String] = []

        if let chain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate] {
            for certificate in chain {
                if let hash = extractPublicKeyHash(from: certificate) {
                    actualHashes.append(hash)
                    if pinnedHashes.contains(hash) {
                        return (matched: true, actualHashes: actualHashes)
                    }
                }
            }
        }

        return (matched: false, actualHashes: actualHashes)
    }

    nonisolated private static func extractPublicKeyHash(from certificate: SecCertificate) -> String? {
        guard let publicKey = SecCertificateCopyKey(certificate),
              let rawKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data?,
              let header = spkiHeader(for: publicKey) else {
            return nil
        }
        // Prepend the SPKI header so the hash matches standard SPKI pins (openssl/TrustKit/HPKP).
        // SecKeyCopyExternalRepresentation returns raw key bytes without the ASN.1 SPKI wrapper.
        return sha256(data: header + rawKeyData).base64EncodedString()
    }

    /// Returns the SubjectPublicKeyInfo (SPKI) header bytes for a given key.
    ///
    /// When prepended to the raw key bytes from `SecKeyCopyExternalRepresentation`, the result
    /// is the full SPKI DER encoding, whose SHA-256 hash matches standard certificate pins.
    ///
    /// Headers sourced from TrustKit and verified against live Let's Encrypt certificate chains.
    nonisolated private static func spkiHeader(for key: SecKey) -> Data? {
        guard let attributes = SecKeyCopyAttributes(key) as? [CFString: Any],
              let keyType = attributes[kSecAttrKeyType] as? String,
              let keySize = attributes[kSecAttrKeySizeInBits] as? Int else {
            return nil
        }
        let rsaType = kSecAttrKeyTypeRSA as String
        let ecType = kSecAttrKeyTypeEC as String
        switch (keyType, keySize) {
        case (rsaType, 2_048):
            return Data([
                0x30, 0x82, 0x01, 0x22, 0x30, 0x0d, 0x06, 0x09,
                0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01,
                0x01, 0x05, 0x00, 0x03, 0x82, 0x01, 0x0f, 0x00
            ])
        case (rsaType, 4_096):
            return Data([
                0x30, 0x82, 0x02, 0x22, 0x30, 0x0d, 0x06, 0x09,
                0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01,
                0x01, 0x05, 0x00, 0x03, 0x82, 0x02, 0x0f, 0x00
            ])
        case (ecType, 256):
            return Data([
                0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86,
                0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x08, 0x2a,
                0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03,
                0x42, 0x00
            ])
        case (ecType, 384):
            return Data([
                0x30, 0x76, 0x30, 0x10, 0x06, 0x07, 0x2a, 0x86,
                0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x05, 0x2b,
                0x81, 0x04, 0x00, 0x22, 0x03, 0x62, 0x00
            ])
        default:
            return nil
        }
    }

    nonisolated private static func sha256(data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }
}

// MARK: - Pinned URLSession Factory

/// Factory for creating URLSession instances with certificate pinning enabled.
///
/// Services should use `PinnedURLSession.shared` instead of `URLSession.shared`
/// for any connections to Dequeue API servers.
nonisolated enum PinnedURLSession {
    // nonisolated(unsafe) to allow lazy init from any context
    nonisolated private static let _shared: URLSession = makeSession()

    /// Shared URLSession with certificate pinning enabled for production domains.
    nonisolated static var shared: URLSession { _shared }

    /// Creates a custom URLSession with certificate pinning and the given configuration.
    nonisolated static func session(
        configuration: URLSessionConfiguration = .default,
        pinningConfiguration: CertificatePinningConfiguration? = nil
    ) -> URLSession {
        makeSession(sessionConfig: configuration, pinConfig: pinningConfiguration)
    }

    nonisolated private static func makeSession(
        sessionConfig: URLSessionConfiguration? = nil,
        pinConfig: CertificatePinningConfiguration? = nil
    ) -> URLSession {
        let config = sessionConfig ?? {
            let sessionConfiguration = URLSessionConfiguration.default
            sessionConfiguration.timeoutIntervalForRequest = 30
            sessionConfiguration.timeoutIntervalForResource = 300
            return sessionConfiguration
        }()

        let delegate = CertificatePinningDelegate(
            configuration: pinConfig ?? currentConfiguration(),
            onPinningFailure: { info in
                Task { @MainActor in
                    ErrorReportingService.capture(
                        error: CertificatePinningError.pinValidationFailed(domain: info.domain),
                        context: [
                            "domain": info.domain,
                            "actual_hashes": info.actualHashes.joined(separator: ", "),
                            "certificate_count": String(info.certificateCount)
                        ]
                    )
                }
            }
        )

        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    nonisolated private static func currentConfiguration() -> CertificatePinningConfiguration {
        #if DEBUG
        return .debug
        #else
        return .production
        #endif
    }
}

// MARK: - Certificate Pinning Validator (Composable)

/// Standalone validator for certificate pinning that can be used by any URLSession delegate.
///
/// Use this when you have a custom URLSessionDelegate that needs pinning but also
/// handles other delegate methods (e.g., progress tracking in UploadManager/DownloadManager).
///
/// All methods are nonisolated and safe to call from any URLSession delegate callback thread.
nonisolated enum CertificatePinningValidator {
    // nonisolated(unsafe) to avoid MainActor inference on static stored property
    nonisolated private static let config: CertificatePinningConfiguration = {
        #if DEBUG
        return .debug
        #else
        return .production
        #endif
    }()

    nonisolated private static let validatorLogger = Logger(
        subsystem: "com.dequeue", category: "CertificatePinning"
    )

    /// Handles a server trust authentication challenge with certificate pinning.
    /// Returns true if the challenge was handled (pinned domain), false if caller should handle.
    nonisolated static func handle(
        challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (
            URLSession.AuthChallengeDisposition, URLCredential?
        ) -> Void
    ) -> Bool {
        let host = challenge.protectionSpace.host

        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              config.pinnedDomains.contains(host),
              let serverTrust = challenge.protectionSpace.serverTrust else {
            return false
        }

        let certCount = SecTrustGetCertificateCount(serverTrust)
        let (matched, actualHashes) = validateTrust(serverTrust)

        if matched {
            validatorLogger.debug("Certificate pinning validated for \(host)")
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            let info = PinningFailureInfo(
                domain: host,
                expectedHashes: config.pinnedPublicKeyHashes,
                actualHashes: actualHashes,
                certificateCount: certCount,
                timestamp: Date()
            )

            Task { @MainActor in
                ErrorReportingService.capture(
                    error: CertificatePinningError.pinValidationFailed(domain: info.domain),
                    context: [
                        "domain": info.domain,
                        "actual_hashes": info.actualHashes.joined(separator: ", "),
                        "certificate_count": String(info.certificateCount)
                    ]
                )
            }

            if config.enforced {
                validatorLogger.error("Certificate pinning FAILED for \(host) — rejected")
                completionHandler(.cancelAuthenticationChallenge, nil)
            } else {
                validatorLogger.warning("Certificate pinning mismatch for \(host) — allowing")
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
            }
        }

        return true
    }

    nonisolated private static func validateTrust(
        _ serverTrust: SecTrust
    ) -> (matched: Bool, actualHashes: [String]) {
        var error: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &error) else {
            return (matched: false, actualHashes: [])
        }

        var actualHashes: [String] = []
        if let chain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate] {
            for certificate in chain {
                if let hash = extractHash(from: certificate) {
                    actualHashes.append(hash)
                    if config.pinnedPublicKeyHashes.contains(hash) {
                        return (matched: true, actualHashes: actualHashes)
                    }
                }
            }
        }
        return (matched: false, actualHashes: actualHashes)
    }

    nonisolated private static func extractHash(from certificate: SecCertificate) -> String? {
        guard let publicKey = SecCertificateCopyKey(certificate),
              let rawData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data?,
              let header = spkiHeader(for: publicKey) else {
            return nil
        }
        // Prepend SPKI header so hash matches standard SPKI pins (same fix as CertificatePinningDelegate).
        let spkiData = header + rawData
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        spkiData.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(spkiData.count), &hash)
        }
        return Data(hash).base64EncodedString()
    }

    /// Returns the SPKI header bytes to prepend to raw key data.
    /// Mirrors CertificatePinningDelegate.spkiHeader — keep in sync.
    nonisolated private static func spkiHeader(for key: SecKey) -> Data? {
        guard let attributes = SecKeyCopyAttributes(key) as? [CFString: Any],
              let keyType = attributes[kSecAttrKeyType] as? String,
              let keySize = attributes[kSecAttrKeySizeInBits] as? Int else {
            return nil
        }
        let rsaType = kSecAttrKeyTypeRSA as String
        let ecType = kSecAttrKeyTypeEC as String
        switch (keyType, keySize) {
        case (rsaType, 2_048):
            return Data([
                0x30, 0x82, 0x01, 0x22, 0x30, 0x0d, 0x06, 0x09,
                0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01,
                0x01, 0x05, 0x00, 0x03, 0x82, 0x01, 0x0f, 0x00
            ])
        case (rsaType, 4_096):
            return Data([
                0x30, 0x82, 0x02, 0x22, 0x30, 0x0d, 0x06, 0x09,
                0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01,
                0x01, 0x05, 0x00, 0x03, 0x82, 0x02, 0x0f, 0x00
            ])
        case (ecType, 256):
            return Data([
                0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86,
                0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x08, 0x2a,
                0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07, 0x03,
                0x42, 0x00
            ])
        case (ecType, 384):
            return Data([
                0x30, 0x76, 0x30, 0x10, 0x06, 0x07, 0x2a, 0x86,
                0x48, 0xce, 0x3d, 0x02, 0x01, 0x06, 0x05, 0x2b,
                0x81, 0x04, 0x00, 0x22, 0x03, 0x62, 0x00
            ])
        default:
            return nil
        }
    }
}
