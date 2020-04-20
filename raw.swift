import Foundation

extension Character {
    var cChar: CChar? {
        return self.asciiValue.flatMap(CChar.init(exactly:))
    }
}

extension CChar {
    static let asciiSlash = Character("\\").cChar!
    static let upperU = Character("U").cChar!
    static let lowerU = Character("u").cChar!

    var asciiHexDigitValue: Int8? {
        if 48...59 ~= self {
            return self - 48
        } else if 65...70 ~= self {
            return (self - 65) + 0xa
        } else if 97...102 ~= self {
            return (self - 97) + 0xa
        } else {
            return nil
        }
    }
}

struct UTF8Buffer {
    let contents: UInt32
}

extension UTF8Buffer {
    static let empty = UTF8Buffer(contents: 0)

    init(_ codepoint: UInt32) {
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
        fileprivate var contents: UInt32

        mutating func next() -> CChar? {
            guard self.contents > 0 else { return nil }
            defer { self.contents >>= 8 }
            return CChar(bitPattern: UInt8(self.contents & 0xFF))
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
            return (value & 0b0111) | 0b1111_000
        default:
            fatalError("Illegal byte count")
    }
}

@inline(__always)
func utf8TrailingByte(_ value: UInt32) -> UInt32 {
    (value & 0b11_1111) | 0b1000_0000
}

@inline(__always)
func asciiHexToUTF8<Chars : Collection>(_ chars: Chars) -> (Int, UTF8Buffer)
    where Chars.Element == CChar
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

func renderEscapes(in s: String) -> String {

   let processed: [Int8] = s.withCString {
        let count = s.utf8.count + 1
        let buf = UnsafeBufferPointer(start: $0, count: count)

        var result: [CChar] = []
        result.reserveCapacity(count)

        var index = buf.startIndex
        while let nextEscape = buf[index...].firstIndex(of: .asciiSlash) {
            let charIndex = nextEscape + 1
            guard [CChar.upperU, CChar.lowerU].contains(buf[charIndex]) else {
                result.append(contentsOf: buf[index..<charIndex + 1])
                index = charIndex + 1
                continue
            }

            let digitStart = charIndex + 1
            let (offset, bytes) = asciiHexToUTF8(buf[digitStart...])
            if offset > 0 {
                result.append(contentsOf: buf[index..<nextEscape])
                result.append(contentsOf: bytes)
                index = digitStart + offset
            }
            else {
                result.append(contentsOf: buf[index..<digitStart])
                index = digitStart
            }
        }

        result.append(contentsOf: buf[index...])
        return result
    }

    return String(cString: processed, encoding: .utf8)!
}

let s = #"\u2615 Caffe\u0300 corretto"#
print(renderEscapes(in: s))
