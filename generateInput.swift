import Foundation

// "Lexicon" to use for generating the dummy text
let words = [
    "lorem", "ipsum", "dolor", "sit", "amet",
    "it", "was", "the", "best", "of", "times", "worst",
    "past", "is", "a", "foreign", "country",
    "call", "me", "ishmael",
    "frog", "blast", "vent", "core",
    "phosphoglyceraldehyde", "supercalifragilisticexpialidocious",
    "antidisestablishmentarianism"
]

/**
 Create a Unicode escape of the form \uNNNNNNNN for a random code point and
 with a random amount of initial 0 padding.
 */
func randomUnicodeEscape() -> String {
    let point: UInt32
    if Bool.random() {
        // Start at printable ASCII chars
        point = UInt32.random(in: 0x20...0xD7FF)
    } else {
        point = UInt32.random(in: 0xE000...0x10FFF)
    }
    return String(format: #"\u{%*0x}"#, Int.random(in: 2...8), point)
}

/**
 Create a string made up of random choices from the `words` list,
 separated by spaces.
 */
func randomSegment() -> String {
    let length = Int.random(in: 1...10)
    let choices = (0..<length).map({ _ in words.randomElement()! })
    return choices.joined(separator: " ")
}

//TODO: Render the text from Swift, too, so that the ouput can be compared
var output = randomSegment()
let segmentCount = Int(ProcessInfo.processInfo.arguments[1])!
for _ in 0..<segmentCount {
    output += " \(randomSegment()) \(randomUnicodeEscape())"
}

print(output)
