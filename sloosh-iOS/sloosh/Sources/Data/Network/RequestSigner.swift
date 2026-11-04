import Foundation
import CryptoKit

/// Dynamic request signer for sloosh API.
/// Computes HMAC-SHA256 signature with UTC timestamp and single-use UUID nonce,
/// preventing URL scraping and replay attacks.
public final class RequestSigner: Sendable {
    public static let shared = RequestSigner()

    // Default HMAC secret matches backend; injected dynamically during CI or overridden via remote config
    private static let hmacSecret: String = "sloosh_hmac_sec_2026_9f4b1e8a3c20"

    private init() {}

    /// Signs an outgoing URLRequest by adding X-Sloosh-Timestamp, X-Sloosh-Nonce, and X-Sloosh-Signature headers.
    public func sign(request: inout URLRequest, path: String, method: String) {
        let timestamp = Int64(Date().timeIntervalSince1970)
        let nonce = UUID().uuidString

        let normalizedMethod = method.uppercased()
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        let message = "\(normalizedMethod):\(normalizedPath):\(timestamp):\(nonce)"

        let key = SymmetricKey(data: Data(Self.hmacSecret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        let signatureHex = signature.map { String(format: "%02hhx", $0) }.joined()

        request.setValue(String(timestamp), forHTTPHeaderField: "X-Sloosh-Timestamp")
        request.setValue(nonce, forHTTPHeaderField: "X-Sloosh-Nonce")
        request.setValue(signatureHex, forHTTPHeaderField: "X-Sloosh-Signature")
    }
}
