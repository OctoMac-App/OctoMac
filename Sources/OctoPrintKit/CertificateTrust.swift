import CryptoKit
import Foundation
import Security

/// A server certificate macOS didn't trust, as shown to the user before they decide.
public struct PresentedCertificate: Sendable, Hashable {
    public var host: String
    /// SHA-256 of the certificate, in lowercase hex.
    public var fingerprint: String
    public var subject: String?

    /// "AB:CD:EF:…", the way browsers show fingerprints.
    public var formattedFingerprint: String {
        stride(from: 0, to: fingerprint.count, by: 2).map { offset -> String in
            let start = fingerprint.index(fingerprint.startIndex, offsetBy: offset)
            return String(fingerprint[start..<fingerprint.index(start, offsetBy: 2)]).uppercased()
        }.joined(separator: ":")
    }
}

/// Lets a printer with a self-signed HTTPS certificate connect, once you've chosen to trust that exact certificate.
///
/// Certificates macOS already trusts are handled normally. Otherwise the connection is allowed only if the
/// certificate's SHA-256 fingerprint matches the one you trusted (pinning); anything else is refused and remembered
/// in `untrusted` so the app can ask.
public final class CertificateTrust: NSObject, URLSessionDelegate, @unchecked Sendable {
    public let pinnedFingerprint: String?
    private let lock = NSLock()
    private var lastUntrusted: PresentedCertificate?

    public init(pinnedFingerprint: String?) {
        self.pinnedFingerprint = pinnedFingerprint?.lowercased()
    }

    /// The most recent certificate that was refused, if any.
    public var untrusted: PresentedCertificate? {
        lock.withLock { lastUntrusted }
    }

    public func evaluate(_ challenge: URLAuthenticationChallenge) -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else { return (.performDefaultHandling, nil) }
        if SecTrustEvaluateWithError(trust, nil) { return (.performDefaultHandling, nil) }
        guard let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first else {
            return (.cancelAuthenticationChallenge, nil)
        }
        let fingerprint = SHA256.hash(data: SecCertificateCopyData(leaf) as Data).map { String(format: "%02x", $0) }.joined()
        if fingerprint == pinnedFingerprint {
            return (.useCredential, URLCredential(trust: trust))
        }
        let presented = PresentedCertificate(host: challenge.protectionSpace.host, fingerprint: fingerprint,
                                             subject: SecCertificateCopySubjectSummary(leaf) as String?)
        lock.withLock { lastUntrusted = presented }
        return (.cancelAuthenticationChallenge, nil)
    }

    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?)
    {
        evaluate(challenge)
    }

    /// A URL session for one printer that honours its trusted certificate.
    public static func session(pinnedFingerprint: String?, configuration: URLSessionConfiguration = .default) -> (URLSession, CertificateTrust) {
        let trust = CertificateTrust(pinnedFingerprint: pinnedFingerprint)
        return (URLSession(configuration: configuration, delegate: trust, delegateQueue: nil), trust)
    }

    /// Connects to `url` just to see its certificate, when macOS doesn't trust it. Returns nil for trusted
    /// certificates, plain HTTP, or when the server can't be reached at all.
    public static func untrustedCertificate(at url: URL) async -> PresentedCertificate? {
        guard url.scheme?.lowercased() == "https" else { return nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        let (session, trust) = Self.session(pinnedFingerprint: nil, configuration: configuration)
        defer { session.invalidateAndCancel() }
        _ = try? await session.data(from: url)
        return trust.untrusted
    }

    /// True for the errors macOS gives when it doesn't trust a server's certificate.
    public static func isCertificateError(_ error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        return [.serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
                .serverCertificateNotYetValid, .secureConnectionFailed, .cancelled].contains(error.code)
    }
}
