import Foundation

func renderEscapes(in s: String) -> String {

    var rendered = ""
    rendered.reserveCapacity(s.count)
    var index = s.startIndex
    while let nextEscape = s[index...].firstIndex(of: "\\") {
        let charIndex = s.index(after: nextEscape)
        guard
            s[charIndex] == "u",
            s[s.index(after: charIndex)] == "{" else
        {
            rendered += s[index..<charIndex]
            index = charIndex
            continue
        }

        let digitStart = s.index(charIndex, offsetBy: 2)
        guard
            let digitEnd = s[digitStart...].firstIndex(of: "}"),
            s.distance(from: digitStart, to: digitEnd) <= 8,
            let value = Int(s[digitStart..<digitEnd], radix: 16),
            let scalar = Unicode.Scalar(value) else
        {
            rendered.append(contentsOf: s[index..<digitStart])
            index = digitStart
            continue
        }

        rendered.append(contentsOf: s[index..<nextEscape])
        rendered.append(Character(scalar))
        index = s.index(after: digitEnd)
    }

    rendered.append(contentsOf: s[index..<s.endIndex])
    return rendered
}

//MARK:- Script

let source = try! String(contentsOfFile: "input.txt")
let rendered = renderEscapes(in: source)
print(rendered)
