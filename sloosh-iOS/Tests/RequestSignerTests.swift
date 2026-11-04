import Foundation
import CryptoKit

@main
struct RequestSignerTests {
    static func main() {
        print("Running RequestSignerTests...")

        var testCount = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            testCount += 1
        }

        let secret = "sloosh_hmac_sec_2026_9f4b1e8a3c20"
        let timestamp: Int64 = 1730737000
        let nonce = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
        let method = "GET"
        let path = "/api/v1/movies/trending"

        let message = "\(method):\(path):\(timestamp):\(nonce)"
        let key = SymmetricKey(data: Data(secret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: key)
        let signatureHex = signature.map { String(format: "%02hhx", $0) }.joined()

        check(signatureHex.count == 64, "HMAC-SHA256 hex must be 64 characters long")
        check(signatureHex.rangeOfCharacter(from: CharacterSet(charactersIn: "0123456789abcdef").inverted) == nil, "Signature must be valid hex")

        // Test with RequestSigner
        var request = URLRequest(url: URL(string: "https://api.sloosh.workers.dev/api/v1/movies/trending")!)
        RequestSigner.shared.sign(request: &request, path: "/api/v1/movies/trending", method: "GET")

        let headerTimestamp = request.value(forHTTPHeaderField: "X-Sloosh-Timestamp")
        let headerNonce = request.value(forHTTPHeaderField: "X-Sloosh-Nonce")
        let headerSignature = request.value(forHTTPHeaderField: "X-Sloosh-Signature")

        check(headerTimestamp != nil && !headerTimestamp!.isEmpty, "X-Sloosh-Timestamp must be set")
        check(headerNonce != nil && !headerNonce!.isEmpty, "X-Sloosh-Nonce must be set")
        check(headerSignature != nil && headerSignature!.count == 64, "X-Sloosh-Signature must be 64-char hex")

        let parsedTimestamp = Int64(headerTimestamp!)
        check(parsedTimestamp != nil && parsedTimestamp! > 1700000000, "Timestamp must be a valid epoch seconds")

        print("✓ All \(testCount) RequestSignerTests passed successfully! 🎉")
    }
}
