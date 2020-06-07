#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <ctype.h>
#include <stdbool.h>

/**
 * Open the file at the given path and read its entire contents
 * as a `NUL`-terminated string, transferring ownership of the result
 * to the caller. The size of the allocation -- including the `NUL`
 * -- is returned in `count`.
 *
 * Returns `NULL` if the read fails for any reason.
 */
static char * contents_of_file(const char * path, size_t * count)
{
    FILE * input_file = fopen(path, "r");
    if (!input_file) {
        *count = 0;
        return NULL;
    }

    if (0 != fseek(input_file, 0, SEEK_END)) {
        *count = 0;
        return NULL;
    }

    size_t length = ftell(input_file);
    if (0 != fseek(input_file, 0, SEEK_SET)) {
        *count = 0;
        return NULL;
    }

    char * source = malloc(length + 1);
    if (!source) {
        abort();
    }
    
    if (length != fread(source, sizeof(char), length, input_file)) {
        free(source);
        *count = 0;
        return NULL;
    }

    fclose(input_file);
    
    source[length] = '\0';
    *count = length + 1;
    return source;
}

/**
 * Copy the bytes between `src` and `end` into the buffer at `dest`,
 * then return `dest` advanced by the number of bytes copied.
 *
 * Precondition: `end` must be an address after `src` in the same
 * block of memory, and `dest` must be large enough to contain the
 * copied bytes. `dest` and the source allocation must not overlap.
 */
static char * append_contents(char * dest, const char * src, const char * end)
{
    size_t range = end - src;
    memcpy(dest, src, range);
    return dest + range;
}

static char * append_bytes(char * dest, const void * src, size_t count)
{
    memcpy(dest, src, count);
    return dest + count;
}

/**
 * Encode the value as needed for the first byte of a UTF-8
 * sequence of the given length.
 *
 * The encoding takes only the low `8 - sequence_count - 1`
 * bits from the input, then sets the top `sequence_count` bits.
 * (The high bits indicate the length of the sequence; they are always
 * followed by a single 0 bit; the lowest bits then contain the
 * "payload".)
 * A codepoint <= 255 is encoded directly as a single `uint8_t`.
 */
static uint8_t utf8_leading_byte(uint8_t value, size_t sequence_count)
{
    switch (sequence_count) {
        case 2:
            return (value & 0x1f) | 0xc0;
        case 3:
            return (value & 0x0f) | 0xe0;
        case 4:
            return (value & 0x07) | 0xf0;
        default:
            abort();
    }
}

/**
 * Encode the value as one of the bytes in position 2-4 of a UTF-8
 * sequence.
 *
 * The encoding takes the low 6 bits from the input,
 * then sets the top bit and unsets the second from the top.
 */
static uint8_t utf8_trailing_byte(uint32_t value)
{
    return (value & 0x3f) | 0x80;
}

/**
 * Transform the given value, which must be a valid Unicode codepoint,
 * into its UTF-8 encoding.
 *
 * Returns the UTF-8 code units, packed into a `uint32_t` such that
 * the leading byte is _physically_ the first byte (big-endian, in a sense);
 * the length of the UTF-8 sequence is returned indirectly in `encoded_length`.
 * If the value passed as `codepoint` is not a legal codepoint, returns
 * a `uint32_t` with all bits set (which is not a legal UTF-8 sequence).
 */
static uint32_t codepoint_to_utf8(uint32_t codepoint, size_t *encoded_length)
{
    uint32_t encoded = 0;
    if (codepoint < 0x80) {
        *encoded_length = 1;
        encoded = codepoint;
    } else if (codepoint < 0x800) {
        *encoded_length = 2;
        encoded = utf8_leading_byte(codepoint >> 6, *encoded_length) << 8 |
                  utf8_trailing_byte(codepoint);
    } else if (codepoint < 0x10000) {
        *encoded_length = 3;
        encoded = utf8_leading_byte(codepoint >> 12, *encoded_length) << 16 |
                  utf8_trailing_byte(codepoint >> 6) << 8 |
                  utf8_trailing_byte(codepoint);
    } else if (codepoint <= 0x10ffff) {
        *encoded_length = 4;
        encoded = utf8_leading_byte(codepoint >> 18, *encoded_length) << 24 |
                  utf8_trailing_byte(codepoint >> 12) << 16 |
                  utf8_trailing_byte(codepoint >> 6) << 8 |
                  utf8_trailing_byte(codepoint);
    } else {
        // Invalid codepoint
        *encoded_length = 0;
        return UINT32_MAX;
    }

    // Move leading code unit up to MSB
    encoded <<= (4 - *encoded_length) * 8;
    // Ensure leading code unit is physically first for memcpy'ing
    return htonl(encoded);
}

/**
 * Examine the input char; if it is a valid single-character escape,
 * put its encoded value into `encoded` and return `true`.
 * If not, return `false` and leave the contents of `encoded`
 * unspecified.
 */
bool encode_simple_escape(const char c, char * encoded)
{
    switch (c) {
        case 'n':
            *encoded = '\n';
            return true;
        case 'r':
            *encoded = '\r';
            return true;
        case 't':
            *encoded = '\t';
            return true;
        case '"':
            *encoded = '"';
            return true;
        case '\\':
            *encoded = '\\';
            return true;
        default:
            return false;
    }
}

/**
 * Examine the first three characters of the given string and return
 * `true` if they are the beginning of a Unicode escape -- a 'u'
 * followed by '{' followed by any hexadecimal digit.
 */
static bool is_unicode_escape(const char * s)
{
    return ('u' == s[0]) && ('{' == s[1]) && isxdigit(s[2]);
}

/**
 * Recognize Unicode escapes in the form \u{NNNNN} and encode the
 * represented codepoints into UTF-8. Also recognize and encode
 * selected single-character escapes.
 *
 * Returns a string owned by the caller, with all non-escape
 * characters untouched.
 */
static char * render_escapes(const char * source)
{
    size_t count = strlen(source);
    if (count <= 0) {
        char * result = malloc(1);
        *result = '\0';
        return result;
    }
    
    char * const result = malloc(count + 1);
    if (!result) {
        abort();
    }
    
    char * current_dest = result;
    const char * current_source = source;
    const char * next_escape = NULL;
    while ((next_escape = strchr(current_source, '\\'))) {
        const char * const escape_char = next_escape + 1;
        char simple_encoded;
        if (encode_simple_escape(*escape_char, &simple_encoded)) {
            current_dest = append_contents(current_dest,
                                           current_source,
                                           next_escape);
            current_dest = append_bytes(current_dest,
                                        &simple_encoded,
                                        1);
            current_source = escape_char + 1;
            continue;
        }
        
        if (!is_unicode_escape(escape_char)) {
            current_dest = append_contents(current_dest,
                                           current_source,
                                           escape_char);
            current_source = escape_char;
            continue;
        }
     
        const char * const digit_start = escape_char + 2;
        char * digit_end = NULL;
        const uint32_t codepoint = strtol(digit_start, &digit_end, 16);
        const size_t digit_count = digit_end - digit_start;
        // The highest codepoint is U+10FFFF, six hexadecimal digits,
        // but we allow leading zeroes, to a max total length of 8
        if ('}' != *digit_end || digit_count < 1 || digit_count > 8) {
            // Invalid escape sequence; in real life we would signal an error
            current_dest = append_contents(current_dest,
                                           current_source,
                                           digit_start);
            current_source = digit_start;
            continue;
        }

        size_t encoded_length = 0;
        const uint32_t encoded = codepoint_to_utf8(codepoint,
                                                   &encoded_length);
        if (UINT32_MAX == encoded) {
            // Invalid codepoint; in real life we would signal an error
            current_dest = append_contents(current_dest,
                                           current_source,
                                           digit_end);
            current_source = digit_end;
            continue;
        }
        
        current_dest = append_contents(current_dest,
                                       current_source,
                                       next_escape);                                      
        current_dest = append_bytes(current_dest,
                                    &encoded,
                                    encoded_length);
        current_source = digit_end + 1;
    }

    current_dest = append_contents(current_dest,
                                   current_source,
                                   (source + count));
    *current_dest = '\0';

    return result;
}

/**
 * Perform simple validation on the input by ensuring that the
 * first `NUL` byte is at the end (as given by `count`) and that
 * there are no bytes that are invalid as UTF-8.
 */
static bool is_utf8_cstring(const char * source, size_t count)
{
    const char * current = source;
    while ('\0' != *current++) {
        if (0xff == (uint8_t)*current || 0xfe == (uint8_t)*current) {
            return false;
        }
    }
    
    return (current - source) == count;
}

int main(int argc, char const *argv[])
{
    size_t count = 0;
    char * source = contents_of_file("input.txt", &count);
    if (!source) {
        return 1;
    }
    
    if (!is_utf8_cstring(source, count)) {
        return 2;
    }
    
    char * rendered = render_escapes(source);

    printf("%s", rendered);
    
    free(source);
    free(rendered);

    return 0;
}
