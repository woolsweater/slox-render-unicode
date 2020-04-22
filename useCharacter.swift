import Foundation

func renderEscapes(in s: String) -> String {

    var rendered = ""
    rendered.reserveCapacity(s.count)
    var index = s.startIndex
    while let nextEscape = s[index...].firstIndex(of: "\\") {
        let charIndex = s.index(after: nextEscape)
        guard ["U", "u"].contains(s[charIndex]) else {
            rendered += s[index..<charIndex]
            index = charIndex
            continue
        }

        let digitStart = s.index(after: charIndex)
        guard
            // Simplification for testing: all escapes must be followed by space
            let digitEnd = s[digitStart...].firstIndex(of: " "),
            let value = Int(s[digitStart..<digitEnd], radix: 16),
            let scalar = Unicode.Scalar(value) else
        {
            rendered.append(contentsOf: s[index..<digitStart])
            index = digitStart
            continue
        }

        rendered.append(contentsOf: s[index..<nextEscape])
        rendered.append(Character(scalar))
        index = digitEnd
    }

    rendered.append(contentsOf: s[index..<s.endIndex])
    return rendered
}

//MARK:- Script

let source = try! String(contentsOfFile: "input.txt")
let rendered = renderEscapes(in: source)
print(rendered)
