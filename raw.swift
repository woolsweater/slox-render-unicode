import Foundation

enum ASCII {
    static let slash = Character("\\").asciiValue!
    static let upperU = Character("U").asciiValue!
    static let lowerU = Character("u").asciiValue!
    static let openBrace = Character("{").asciiValue!
    static let closeBrace = Character("}").asciiValue!
}

extension BinaryInteger {
    /**
     The numerical value of the ASCII hexadecimal digit
     encoded by this number. `nil` if this number is not
     the ASCII encoding of a hexadecimal digit.
     - remark: Uppercase and lowercase ASCII are supported.
     - example: 67 is the ASCII encoding for the letter 'C',
     whose value as a hexadecimal digit is 12.
     */
    var asciiHexDigitValue: Self? {
        switch self {
            // 0-9
            case 48...59:
                return self - 48
            // A-F
            case 65...70:
                return (self - 65) + 0xa
            // a-f
            case 97...102:
                return (self - 97) + 0xa
            default:
                return nil
        }
    }
}

struct UTF8Buffer {
    private let contents: UInt32
}

extension UTF8Buffer {
    init(_ codepoint: UInt32) {
        // Note: contents stored "reversed" for consumption as a Sequence
        if codepoint < 0x80 {
            self.contents = utf8LeadingByte(codepoint, sequenceCount: 1)
        } else if codepoint < 0x800 {
            self.contents =
                utf8LeadingByte(codepoint >> 6, sequenceCount: 2) |
                (utf8TrailingByte(codepoint) << 8)
        } else if codepoint < 0x1_0000 {
            self.contents =
                utf8LeadingByte(codepoint >> 12, sequenceCount: 3) |
                (utf8TrailingByte(codepoint >> 6) << 8) |
                (utf8TrailingByte(codepoint) << 16)
        } else {
            self.contents =
                utf8LeadingByte(codepoint >> 18, sequenceCount: 4) |
                (utf8TrailingByte(codepoint >> 12) << 8) |
                (utf8TrailingByte(codepoint >> 6) << 16) |
                (utf8TrailingByte(codepoint) << 24)
        }
    }
}

extension UTF8Buffer : Sequence {
    struct Iterator : IteratorProtocol {
        private var contents: UInt32

        init(contents: UInt32) {
            if contents == 0 {
                self.contents = 0xFF
            } else {
                self.contents = contents
            }
        }

        mutating func next() -> UInt8? {
            guard self.contents > 0 else { return nil }
            defer { self.contents >>= 8 }
            if self.contents == 0xFF {
                return 0
            } else {
                return UInt8(self.contents & 0xFF)
            }
        }
    }

    func makeIterator() -> Iterator {
        return Iterator(contents: self.contents)
    }
}

@inline(__always)
func utf8LeadingByte(_ value: UInt32, sequenceCount: Int) -> UInt32 {
    switch sequenceCount {
        case 1:
            return value
        case 2:
            return (value & 0b1_1111) | 0b1100_0000
        case 3:
            return (value & 0b1111) | 0b1110_0000
        case 4:
            return (value & 0b0111) | 0b1111_0000
        default:
            fatalError("Illegal byte count")
    }
}

@inline(__always)
func utf8TrailingByte(_ value: UInt32) -> UInt32 {
    (value & 0b11_1111) | 0b1000_0000
}

@inline(__always)
func asciiHexToUTF8<C : Collection>(_ chars: C) -> UTF8Buffer?
    where C.Element : BinaryInteger
{
    var codepoint: UInt32 = 0
    for char in chars {
        guard let value = char.asciiHexDigitValue else { return nil }
        codepoint <<= 4
        codepoint += UInt32(value)
    }

    return UTF8Buffer(codepoint)
}

extension UnsafePointer where Pointee == UInt8 {
    @inline(__always)
    func indexOfNul() -> Int {
        var pointer = self
        while pointer.pointee != 0x0 {
            pointer = pointer.successor()
        }
        return self.distance(to: pointer)
    }
}

func renderEscapes(in s: String) -> String {

   let processed: [UInt8] = s.withCString(encodedAs: UTF8.self) { (base) in
        let count = base.indexOfNul()
        guard count > 0 else { return [] }
        let buf = UnsafeBufferPointer(start: base, count: count)

        var result: [UInt8] = []
        result.reserveCapacity(count)

        var index = buf.startIndex
        while let nextEscape = buf[index...].firstIndex(of: ASCII.slash) {
            let charIndex = nextEscape + 1
            guard
                buf[charIndex] == ASCII.lowerU,
                buf[charIndex + 1] == ASCII.openBrace,
                buf[charIndex + 2].asciiHexDigitValue != nil else
            {
                result.append(contentsOf: buf[index...charIndex])
                index = charIndex
                continue
            }

            let digitStart = charIndex + 2
            // The highest codepoint is U+10FFFF, six hexadecimal digits,
            // but we allow leading zeroes, to a max total length of 8
            let digitEndLimit = min(count, digitStart + 8)
            let braceSearchRange = digitStart...digitEndLimit
            guard
                let digitEnd = buf[braceSearchRange].firstIndex(of: ASCII.closeBrace),
                let encoded = asciiHexToUTF8(buf[digitStart..<digitEnd]) else
            {
                // Invalid escape sequence; in real life we would signal an error
                result.append(contentsOf: buf[index..<digitStart])
                index = digitStart
                continue
            }

            result.append(contentsOf: buf[index..<nextEscape])
            result.append(contentsOf: encoded)
            index = digitEnd + 1    // Skip ending brace
        }

        result.append(contentsOf: buf[index...])
        return result
    }

    return String(bytes: processed, encoding: .utf8)!
}

//MARK:- Script

let source = try! String(contentsOfFile: "input.txt")
let rendered = renderEscapes(in: source)
print(rendered, terminator: "")
