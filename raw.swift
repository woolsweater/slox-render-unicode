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

extension UTF8Buffer : Sequence {
    struct Iterator : IteratorProtocol {
        fileprivate var contents: UInt32

        mutating func next() -> UInt8? {
            guard self.contents > 0 else { return nil }
            defer { self.contents >>= 8 }
            return UInt8(exactly: self.contents & 0b1111)!
        }
    }

    func makeIterator() -> Iterator {
        return Iterator(contents: self.contents)
    }
}

@inline(__always)
func utf8LeadingByte(_ value: UInt32, sequenceCount: Int) -> CChar {

    let masked: UInt8
    switch sequenceCount {
        case 1:
            masked = UInt8(value)
        case 2:
            masked = UInt8((value & 0b1_1111) | 0b1100_0000)
        case 3:
            masked = UInt8((value & 0b1111) | 0b1110_0000)
        case 4:
            masked = UInt8((value & 0b0111) | 0b1111_000)
        default:
            fatalError("Illegal byte count")
    }

    return CChar(bitPattern: masked)
}

@inline(__always)
func utf8TrailingByte(_ value: UInt32) -> CChar {
    CChar(bitPattern: UInt8((value & 0b11_1111) | 0b1000_0000))
}

func asciiHexToUTF8<Chars : Collection>(_ chars: Chars) -> (Int, [CChar])
    where Chars.Element == CChar
{
    var point: UInt32 = 0
    var consumedCount = 0
    for (i, char) in chars.enumerated() {
        guard let value = char.asciiHexDigitValue else { break }
        consumedCount = i + 1
        point <<= 4
        point += UInt32(value)
    }

    guard point > 0 else {
        return (0, [])
    }

    if point < 0x80 {
        return (consumedCount, [utf8LeadingByte(point, sequenceCount: 1)])
    } else if point < 0x0800 {
        return (
            consumedCount,
            [
                utf8LeadingByte(point >> 6, sequenceCount: 2),
                utf8TrailingByte(point >> 0),
            ]
        )
    } else if point < 0x010000 {
        return (
            consumedCount,
            [
                utf8LeadingByte(point >> 12, sequenceCount: 3),
                utf8TrailingByte(point >> 6),
                utf8TrailingByte(point >> 0),
            ]
        )
    } else {
        return (
            consumedCount,
            [
                utf8LeadingByte(point >> 18, sequenceCount: 4),
                utf8TrailingByte(point >> 12),
                utf8TrailingByte(point >> 6),
                utf8TrailingByte(point >> 0),
            ]
        )
    }
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
