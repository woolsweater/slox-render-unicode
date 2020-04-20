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
        let digitEnd = s.index(digitStart, offsetBy: 4)
        guard
            let value = Int(s[digitStart..<digitEnd], radix: 16),
            let scalar = Unicode.Scalar(value) else
        {
            rendered.append(contentsOf: s[index..<digitEnd])
            index = digitEnd
            continue
        }

        rendered.append(contentsOf: s[index..<nextEscape])
        rendered.append(Character(scalar))
        index = digitEnd
    }

    rendered.append(contentsOf: s[index..<s.endIndex])
    return rendered
}

let s = #"\u2615 Caffe\u0300 corretto"#
print(renderEscapes(in: s))
