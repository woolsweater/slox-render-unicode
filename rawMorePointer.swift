import Foundation

enum ASCII {
    static let slash = Character("\\").asciiValue!
    static let upperU = Character("U").asciiValue!
    static let lowerU = Character("u").asciiValue!
    static let openBrace = Character("{").asciiValue!
    static let closeBrace = Character("}").asciiValue!

    static func isHexDigit(_ char: UInt8) -> Bool {
        return isxdigit(Int32(char)) != 0
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

func parseHexEscape(_ start: UnsafePointer<UInt8>) -> (UInt32, end: UnsafePointer<UInt8>)? {
    // The highest codepoint is U+10FFFF, six hexadecimal digits,
    // but we allow leading zeroes, to a max total length of 8
    let maxEscapeDigitLength = 8
    var end: UnsafeMutablePointer<UInt8>? = UnsafeMutablePointer(mutating: start)
    let parsed = start.withMemoryRebound(to: Int8.self, capacity: maxEscapeDigitLength) {
        (start) in
        withUnsafeMutablePointer(to: &end) {
            // Rebinding the inner pointer prevents having to rebind through a raw pointer
            // (and picking an arbitrary capacity) when returning the final result
            $0.withMemoryRebound(to: UnsafeMutablePointer<Int8>?.self, capacity: maxEscapeDigitLength + 1) {
                (endPtr) in
                UInt32(strtol(start, endPtr, 16))
            }
        }
    }
    
    guard 1...maxEscapeDigitLength ~= start.distance(to: end!) else { return nil }
    
    return (parsed, UnsafePointer(end!))
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

    let processed: UnsafeMutableBufferPointer<UInt8> = s.withCString(encodedAs: UTF8.self) { (base) in
        let count = base.strLen()

        let result = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: count)
        var currentDest = result.baseAddress!

        var currentSource = base
        while let nextEscape = currentSource.strChr(ASCII.slash) {
            let escapeChar = nextEscape + 1
            let braceChar = escapeChar + 1
            let digitStart = braceChar + 1
            guard
                escapeChar.pointee == ASCII.lowerU,
                braceChar.pointee == ASCII.openBrace,
                ASCII.isHexDigit(digitStart.pointee) else
            {
                currentDest.appendContents(of: currentSource, upTo: nextEscape)
                currentSource = nextEscape
                continue
            }

            guard
                let (codepoint, digitEnd) = parseHexEscape(digitStart),
                digitEnd.pointee == ASCII.closeBrace else
            {
                // Invalid escape sequence; in real life we would signal an error
                currentDest.appendContents(of: currentSource, upTo: digitStart)
                currentSource = digitStart
                continue
            }

            let (encoded, encodedLength) = codepoint.toUTF8()
            currentDest.appendContents(of: currentSource, upTo: nextEscape)
            _ = withUnsafePointer(to: encoded) {
                memcpy(currentDest, UnsafeRawPointer($0), encodedLength)
            }
            currentDest += encodedLength
            currentSource = digitEnd + 1    // Skip ending brace
        }

        currentDest.appendContents(of: currentSource, upTo: base + count)
        currentDest[0] = 0x0
        
        return result
    }

    defer { processed.deallocate() }
    return String(cString: processed.baseAddress!)
}

//MARK:- Script

let source = try! String(contentsOfFile: "input.txt")
let rendered = renderEscapes(in: source)
print(rendered, terminator: "")
