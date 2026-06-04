import Foundation

let text = "494595//hls/1234/master.m3u8"
let base64 = text.data(using: .utf8)!.base64EncodedString()
let map: [Character: Character] = [
    "A": "D", "B": "l", "C": "C", "D": "h", "E": "E", "F": "X", "G": "i", "H": "t", "I": "L", "J": "O",
    "K": "N", "L": "Y", "M": "R", "N": "k", "O": "F", "P": "j", "Q": "A", "R": "s", "S": "n", "T": "B",
    "U": "b", "V": "y", "W": "m", "X": "W", "Y": "z", "Z": "S", "a": "H", "b": "M", "c": "q", "d": "K",
    "e": "P", "f": "g", "g": "Q", "h": "Z", "i": "p", "j": "v", "k": "w", "l": "e", "m": "r", "n": "o",
    "o": "f", "p": "J", "q": "T", "r": "V", "s": "d", "t": "I", "u": "u", "v": "U", "w": "c", "x": "x",
    "y": "a", "z": "G"
]
var result = ""
for char in base64 {
    if let mapped = map[char] { result.append(mapped) }
    else { result.append(char) }
}
print(result)
