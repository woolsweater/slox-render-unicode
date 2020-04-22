import Foundation

enum ASCII {
    static let slash = Character("\\").asciiValue!
    static let upperU = Character("U").asciiValue!
    static let lowerU = Character("u").asciiValue!
}

extension BinaryInteger {
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
func asciiHexToUTF8<C : Collection>(_ chars: C) -> (Int, UTF8Buffer)
    where C.Element : BinaryInteger
{
    var codepoint: UInt32 = 0
    var consumedCount = 0
    for (i, char) in chars.enumerated() {
        guard let value = char.asciiHexDigitValue else { break }
        consumedCount = i + 1
        codepoint <<= 4
        codepoint += UInt32(value)
    }

    return (consumedCount, UTF8Buffer(codepoint))
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
            guard [ASCII.upperU, ASCII.lowerU].contains(buf[charIndex]) else {
                result.append(contentsOf: buf[index..<charIndex + 1])
                index = charIndex + 1
                continue
            }

            let digitStart = charIndex + 1
            let (offset, encoded) = asciiHexToUTF8(buf[digitStart...])
            if offset > 0 {
                result.append(contentsOf: buf[index..<nextEscape])
                result.append(contentsOf: encoded)
            }
            else {
                result.append(contentsOf: buf[index..<digitStart])
            }

            index = digitStart + offset
        }

        result.append(contentsOf: buf[index...])
        return result
    }

    return String(bytes: processed, encoding: .utf8)!
}

//MARK:- Script

let source = try! String(contentsOfFile: "input.txt")
let rendered = renderEscapes(in: source)
print(rendered)
