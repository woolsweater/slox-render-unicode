import Foundation

/**
 ASCII encoding values for various characters that we need
 to be able to handle.
 */
enum ASCII {
    static let lowerN = Character("n").asciiValue!
    static let lowerR = Character("r").asciiValue!
    static let lowerT = Character("t").asciiValue!
    static let lowerU = Character("u").asciiValue!
    static let slash = Character(#"\"#).asciiValue!
    static let doubleQuote = Character("\"").asciiValue!
    static let openBrace = Character("{").asciiValue!
    static let closeBrace = Character("}").asciiValue!
    
    static let newline = Character("\n").asciiValue!
    static let carriageReturn = Character("\r").asciiValue!
    static let tab = Character("\t").asciiValue!

    static func isHexDigit(_ char: UInt8) -> Bool {
        return char.asciiHexDigitValue != nil
    }
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

    /**
     Transform this value, which must be a valid Unicode codepoint, into
     its UTF-8 encoding.
     - returns: The UTF-8 code units, packed into a `UInt32` such that
     the leading byte is _physically_ the first byte (big-endian, in a sense);
     trailing bytes follow and unused bytes are 0. The length of the UTF-8
     sequence (the number of used bytes) is returned alongside.
     */
    func toUTF8() -> (UInt32, Int) {
        var contents: UInt32 = 0
        let length: Int
        if self < 0x80 {
            length = 1
            contents = self
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
            precondition(self <= 0x10ffff, "Invalid codepoint")
            length = 4
            contents =
                utf8LeadingByte(self >> 18, sequenceCount: length) << 24 |
                (utf8TrailingByte(self >> 12) << 16) |
                (utf8TrailingByte(self >> 6) << 8) |
                utf8TrailingByte(self)
        }
        
        // Slide code units so that the leading one is in the MSB
        contents <<= (4 - length) * 8
        // Ensure leading code unit is physically first for memcpy'ing
        return (contents.bigEndian, length)
    }
}

/**
 Encode the given value as the leading byte of a UTF-8 sequence
 of the given length.
 - remark: The encoding takes only the low `8 - sequenceCount - 1`
 bits from the input, then sets the top `sequenceCount` bits.
 (The high bits indicate the length of the sequence; they are always
 followed by a single 0 bit; the lowest bits then contain the "payload".)
 A codepoint <= 255 is encoded directly as a single `UInt8`.
 */
@inline(__always)
func utf8LeadingByte(_ value: UInt32, sequenceCount: Int) -> UInt32 {
    switch sequenceCount {
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

/**
 Encode the given value as one of the bytes in position 2-4
 of a UTF-8 sequence.
 - remark: The encoding takes the low 6 bits from the input,
 then sets the top bit and unsets the second from the top.
 */
@inline(__always)
func utf8TrailingByte(_ value: UInt32) -> UInt32 {
    (value & 0b11_1111) | 0b1000_0000
}

/**
 Parse the sequence of characters, which must all be (ASCII)
 hexadecimal digits, into its corresponding codepoint.
 - returns: `nil` if the sequence either has no hexadecimal characters
 or has more than 8, or if the resulting codepoint is above U+10FFFF.
 If the sequence is valid, returns the parsed value and a pointer
 to the character following the last parsed digit.
 */
func parseHexEscape(_ start: UnsafePointer<UInt8>) -> (UInt32, end: UnsafePointer<UInt8>)? {
    var codepoint: UInt32 = 0
    var current = start
    while let value = current.pointee.asciiHexDigitValue {
        codepoint <<= 4
        codepoint += UInt32(value)
        current += 1
    }
    
    // The highest codepoint is U+10FFFF, six hexadecimal digits,
    // but we allow leading zeroes, to a max total length of 8
    guard 1...8 ~= start.distance(to: current) else { return nil }
    guard codepoint <= 0x10ffff else { return nil }
    return (codepoint, current)
}

extension UnsafePointer where Pointee == UInt8 {
    
    /**
     Walk this C string to find the given byte.
     - returns: A pointer to the first instance of the
     given byte in the string, or `nil` if the byte
     was not found (a `NUL` byte was found first).
     - warning: If this pointer is not a proper C string
     (there is no terminating `NUL`), and the sought byte
     is not present, this has undefined behavior.
     - remark: Analogous to `strchr` in the C stdlib.
     */
    @inline(__always)
    func find(_ char: UInt8) -> UnsafePointer<UInt8>? {
        var pointer = self
        while pointer.pointee != char {
            if pointer.pointee == 0x0 {
                return nil
            }
            pointer = pointer.successor()
        }
        return pointer
    }
    
    /**
     Find the length of this C string.
     - warning: If this pointer is not a proper C string
     (there is no terminating `NUL`), this has undefined
     behavior.
     - remark: Analagous to `strlen` from the C stdlib.
     */
    @inline(__always)
    func cStringLength() -> Int {
        return self.find(0x0)! - self
    }
}

extension UnsafeMutablePointer where Pointee == UInt8 {

    /**
     Copy the contents of the region from `start` through `end` into
     `self`, then advance `self` by the number of bytes copied.
     - important:
        - `self` must point to an allocation big enough to hold the new
     bytes
        - `end` must be a location higher than `start`, in the
     same block of memory
        - that block must not overlap with the contents of `self`
     Behavior is undefined if any of these conditions do not hold.
     */
    mutating func appendContents(of start: UnsafePointer<UInt8>, upTo end: UnsafePointer<UInt8>) {
        precondition(end >= start, "Cannot copy region of negative size")
        let range = end - start
        memcpy(self, start, range)
        self += range
    }
}

/**
 If the byte represents one of our recognized escape
 characters, return the UTF-8 encoding of the sequence;
 otherwise return `nil`.
 */
func encodeSimpleEscape(_ char: UInt8) -> UInt8? {
    switch char {
        case ASCII.lowerN:
            return ASCII.newline
        case ASCII.lowerR:
            return ASCII.carriageReturn
        case ASCII.lowerT:
            return ASCII.tab
        case ASCII.doubleQuote:
            return ASCII.doubleQuote
        case ASCII.slash:
            return ASCII.slash
        default:
            return nil
    }
}

/**
 Working with the input string as UTF-8 data, use Swift pointer APIs to
 recognize and process escape sequences into their corresponding UTF-8
 encoding. The result is then re-wrapped into a Swift `String`.
 - remark: This is a slightly "rawer" version of the raw.swift script,
 a bit closer to the C implemetation.
 It does not have the `UTF8Buffer : Sequence` convience and uses direct
 pointer arithmetic instead of buffer pointer slicing and indexing.
 */
func renderEscapes(in s: String) -> String {

    let processed: UnsafeMutableBufferPointer<UInt8> = s.withCString(encodedAs: UTF8.self) { (base) in
        let count = base.cStringLength()

        let result = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: count)
        var currentDest = result.baseAddress!

        var currentSource = base
        while let nextEscape = currentSource.find(ASCII.slash) {
            let escapeChar = nextEscape + 1
            if let encoded = encodeSimpleEscape(escapeChar.pointee) {
                currentDest.appendContents(of: currentSource, upTo: nextEscape)
                _ = withUnsafePointer(to: encoded) {
                    memcpy(currentDest, UnsafeRawPointer($0), 1)
                }
                currentDest += 1
                currentSource = escapeChar + 1
                continue
            }
            
            let braceChar = nextEscape + 2
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
    // See the perf-cliff branch for an interesting question on the `String.init` choice
    return String(cString: processed.baseAddress!)
}

//MARK:- Script

let source = try! String(contentsOfFile: "input.txt")
let rendered = renderEscapes(in: source)
print(rendered, terminator: "")
