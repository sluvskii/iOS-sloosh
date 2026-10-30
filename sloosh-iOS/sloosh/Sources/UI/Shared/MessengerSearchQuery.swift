import Foundation

/// Shared query semantics for the conversation list and the new-message picker.
struct MessengerSearchQuery: Equatable {
    let text: String
    var isEmpty: Bool { text.isEmpty }

    init(_ raw: String) {
        text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func matches(name: String, tag: String, message: String = "") -> Bool {
        if isEmpty { return true }
        let tagQuery = text.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        return name.localizedCaseInsensitiveContains(text)
            || message.localizedCaseInsensitiveContains(text)
            || (!tagQuery.isEmpty && tag.localizedCaseInsensitiveContains(tagQuery))
    }
}
