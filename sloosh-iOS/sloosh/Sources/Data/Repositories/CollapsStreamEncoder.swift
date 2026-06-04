import Foundation

enum CollapsStreamEncoder {
    static let marker = "/x-en-x/"

    static func encodeUri(_ urlString: String) -> String {
        guard !urlString.isEmpty, !urlString.contains(marker), let url = URL(string: urlString) else {
            return urlString
        }

        let n = Int(round(Date().timeIntervalSince1970 / 3600.0))
        var absolutePath = url.path
        if !absolutePath.hasPrefix("/") { absolutePath = "/" + absolutePath }
        let query = url.query.map { "?\($0)" } ?? ""
        let payload = "\(n)\(absolutePath)\(query)"

        guard let payloadData = payload.data(using: .utf8) else {
            return urlString
        }

        let base64 = payloadData.base64EncodedString()
        let encodedBase64 = applyCharacterMapping(to: base64)

        let scheme = url.scheme ?? "https"
        let host = url.host ?? ""
        let portPart = url.port.map { ":\($0)" } ?? ""

        var newUri = "\(scheme)://\(host)\(portPart)\(marker)\(encodedBase64)"

        if urlString.contains(".vtt") {
            newUri += "#.vtt"
        } else if urlString.contains(".mpd") {
            newUri += "#.mpd"
        } else {
            newUri += "#.m3u8"
        }

        return newUri
    }

    private static func applyCharacterMapping(to base64: String) -> String {
        let map: [Character: Character] = [
            "A": "D", "B": "l", "C": "C", "D": "h", "E": "E", "F": "X", "G": "i", "H": "t", "I": "L", "J": "O",
            "K": "N", "L": "Y", "M": "R", "N": "k", "O": "F", "P": "j", "Q": "A", "R": "s", "S": "n", "T": "B",
            "U": "b", "V": "y", "W": "m", "X": "W", "Y": "z", "Z": "S", "a": "H", "b": "M", "c": "q", "d": "K",
            "e": "P", "f": "g", "g": "Q", "h": "Z", "i": "p", "j": "v", "k": "w", "l": "e", "m": "r", "n": "o",
            "o": "f", "p": "J", "q": "T", "r": "V", "s": "d", "t": "I", "u": "u", "v": "U", "w": "c", "x": "x",
            "y": "a", "z": "G"
        ]

        var result = ""
        result.reserveCapacity(base64.count)

        for char in base64 {
            if let mapped = map[char] {
                result.append(mapped)
            } else {
                result.append(char)
            }
        }

        return result
    }
}
