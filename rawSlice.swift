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

extension UInt32 {
    func toUTF8() -> (UInt32, Int) {
        var contents: UInt32
        let length: Int
        if self < 0x80 {
            length = 1
            contents = utf8LeadingByte(self, sequenceCount: length)
        } else if self < 0x800 {
            length = 2
            contents =
                utf8LeadingByte(self >> 6, sequenceCount: length) << 8 |
                utf8TrailingByte(self)
        } else if self < 0x1_0000 {
            length = 3
            contents =
                utf8LeadingByte(self >> 12, sequenceCount: length) << 16 |
                (utf8TrailingByte(self >> 6) << 8) |
                utf8TrailingByte(self)
        } else {
            precondition(self <= 0x10FFFF, "Invalid codepoint")
            length = 4
            contents =
                utf8LeadingByte(self >> 18, sequenceCount: length) << 24 |
                (utf8TrailingByte(self >> 12) << 16) |
                (utf8TrailingByte(self >> 6) << 8) |
                utf8TrailingByte(self)
        }
        
        contents <<= (4 - length) * 8
        return (contents.bigEndian, length)
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
func asciiHexToUTF8(_ chars: UnsafePointer<UInt8>, _ count: Int) -> (UInt32, Int) {
    var codepoint: UInt32 = 0
    for i in 0..<count {
        guard let value = chars[i].asciiHexDigitValue else { break }
        codepoint <<= 4
        codepoint += UInt32(value)
    }

    return codepoint.toUTF8()
}

extension UnsafePointer where Pointee == UInt8 {
    @inline(__always)
    func memChr(_ char: UInt8, limit: Int = .max) -> UnsafePointer<UInt8>? {
        var pointer = self
        while pointer.pointee != char {
            if pointer - self > limit {
                return nil
            }
            pointer = pointer.successor()
        }
        return pointer
    }
    
    @inline(__always)
    func strChr(_ char: UInt8) -> UnsafePointer<UInt8>? {
        var pointer = self
        while pointer.pointee != char {
            if pointer.pointee == 0x0 {
                return nil
            }
            pointer = pointer.successor()
        }
        return pointer
    }
    
    @inline(__always)
    func strLen() -> Int {
        return self.strChr(0x0)! - self
    }
}

extension UnsafeMutablePointer where Pointee == UInt8 {
    mutating func appendContents(of start: UnsafePointer<UInt8>, upTo end: UnsafePointer<UInt8>) {
        let range = end - start
        memcpy(self, start, range)
        self += range
    }
}

func renderEscapes(in s: String) -> String {

    let processed: Slice<UnsafeMutableBufferPointer<UInt8>> = s.withCString(encodedAs: UTF8.self) { (base) in
        let count = base.strLen()

        let result = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: count)
        var currentDest = result.baseAddress!

        var currentSource = base
        while let nextEscape = currentSource.strChr(ASCII.slash) {
            let escapeChar = nextEscape + 1
            let braceChar = nextEscape + 2
            guard
                escapeChar.pointee == ASCII.lowerU,
                braceChar.pointee == ASCII.openBrace else
            {
                currentDest.appendContents(of: currentSource, upTo: nextEscape)
                currentSource = nextEscape
                continue
            }

            let digitStart = braceChar + 1
            guard let digitEnd = digitStart.memChr(ASCII.closeBrace, limit: 9) else {
                currentDest.appendContents(of: currentSource, upTo: digitStart)
                currentSource = digitStart
                continue
            }

            //TODO: This doesn't account for what's between the braces
            // not being entirely hex digits
            let digitCount = digitEnd - digitStart
            let (encoded, encodedLength) = asciiHexToUTF8(digitStart, digitCount)
            currentDest.appendContents(of: currentSource, upTo: nextEscape)
            _ = withUnsafePointer(to: encoded) {
                memcpy(currentDest, UnsafeRawPointer($0), encodedLength)
            }
            currentDest += encodedLength
            currentSource = digitEnd + 1    // Skip ending brace
        }

        currentDest.appendContents(of: currentSource, upTo: base + count)
        currentDest[0] = 0x0
        
        let resultEnd = currentDest - result.baseAddress!
        return result[..<resultEnd]
    }

    defer { processed.base.deallocate() }
    return String(bytes: processed, encoding: .utf8)!
}

//MARK:- Script

let source = try! String(contentsOfFile: "input.txt")
let rendered = renderEscapes(in: source)
print(rendered, terminator: "")
