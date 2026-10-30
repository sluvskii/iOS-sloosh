import Foundation

@main
struct MessengerSearchTests {
    static func main() {
        var count = 0
        func check(_ condition: Bool, _ description: String) {
            precondition(condition, description)
            count += 1
        }
        check(MessengerSearchQuery("").isEmpty, "Empty query")
        check(MessengerSearchQuery(" \n\t ").isEmpty, "Whitespace must not enter search mode")
        check(MessengerSearchQuery("  Анна \n").text == "Анна", "Trim both ends")
        check(MessengerSearchQuery(" @anna ") == MessengerSearchQuery("@anna"), "Equivalent queries share a task identity")
        check(MessengerSearchQuery("").matches(name: "Анна", tag: "@anna"), "Empty query shows conversations")
        check(MessengerSearchQuery("анНА").matches(name: "Анна Иванова", tag: "@other"), "Case-insensitive Cyrillic name")
        check(MessengerSearchQuery(" @ANNA ").matches(name: "Друг", tag: "@anna"), "Case-insensitive @tag with whitespace")
        check(MessengerSearchQuery("anna").matches(name: "Друг", tag: "@anna"), "Tag without @")
        check(MessengerSearchQuery("anna").matches(name: "Друг", tag: "anna"), "Stored tag without @")
        check(MessengerSearchQuery("смотрим").matches(name: "Друг", tag: "", message: "Смотрим фильм?"), "Message preview search")
        check(!MessengerSearchQuery("другой").matches(name: "Анна", tag: "@anna", message: "Привет"), "No match")
        check(!MessengerSearchQuery("@").matches(name: "Анна", tag: "@anna"), "Bare @ must not match all tags")
        check(!MessengerSearchQuery("!!!").matches(name: "Анна", tag: "@anna"), "Punctuation must not become an empty tag match")
        check(MessengerSearchQuery("!!!").matches(name: "Анна", tag: "@anna", message: "Привет!!!"), "Punctuation still searches literal message text")
        check(!MessengerSearchQuery("anna smith").matches(name: "Анна", tag: "@annasmith"), "Internal spaces are not silently erased")
        print("PASS: \(count) messenger search query cases")
    }
}
