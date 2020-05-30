#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <assert.h>

/**
 * Open the file at the given path and read its entire contents,
 * transferring ownership of the result to the caller.
 * - returns: `NULL` if the read fails for any reason.
 */
static char * contents_of_file(const char * path)
{
    FILE * input_file = fopen(path, "r");
    if (!input_file) {
        return NULL;
    }

    if (0 != fseek(input_file, 0, SEEK_END)) {
        return NULL;
    }

    size_t length = ftell(input_file);
    if (0 != fseek(input_file, 0, SEEK_SET)) {
        return NULL;
    }

    char * source = malloc(length);
    if (length != fread(source, sizeof(char), length, input_file)) {
        free(source);
        return NULL;
    }

    fclose(input_file);
    return source;
}

/**
 * Copy the bytes between `src` and `end` into the buffer at `dest`,
 * then return `dest` advanced by the number of bytes copied.
 * - precondition: `end` must be an address after `src` in the same
 * block of memory, and `dest` must be large enough to contain the
 * copied bytes.
 */
static char * append_contents(char * dest, const char * src, const char * end)
{
    size_t range = end - src;
    memcpy(dest, src, range);
    return dest + range;
}

/**
 * Given a character that is an ASCII hexadecimal digit (decimal 0-9,
 * capital A-F, lowercase a-f), produce its numerical value.
 * If the character is not a hexadecimal digit, returns `UINT8_MAX`
 * - example: 'c' (ASCII encoding 67) interpreted as a hexadecimal
 * digit has the value 12.
 */
static uint8_t ascii_hex_digit_value(char c)
{
    if (48 <= c && c <= 59) {
        // Digits 0-9
        return c - 48;
    } else if (65 <= c && c <= 70) {
        // Digits A-F
        return (c - 65) + 0xa;
    } else if (97 <= c && c <= 102) {
        // Digits a-f
        return (c - 97) + 0xa;
    } else {
        return UINT8_MAX;
    }
}

/**
 * Encode the value as needed for the first byte of a UTF-8
 * sequence of the given length.
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
 */
static uint8_t utf8_trailing_byte(uint32_t value)
{
    return (value & 0x3f) | 0x80;
}

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
    } else if (codepoint <= 0x10FFFF) {
        *encoded_length = 4;
        encoded = utf8_leading_byte(codepoint >> 18, *encoded_length) << 24 |
                  utf8_trailing_byte(codepoint >> 12) << 16 |
                  utf8_trailing_byte(codepoint >> 6) << 8 |
                  utf8_trailing_byte(codepoint);
    } else {
        // Invalid codepoint
        abort();
    }

    encoded <<= (4 - *encoded_length) * 8;
    return htonl(encoded);
}

/**
 * Parse a sequence of hexadecimal digits to their numerical value.
 */
static uint32_t ascii_hex_to_utf8(const char * source, size_t count, size_t *encoded_length)
{
    uint32_t codepoint = 0;
    for (size_t i = 0; i < count; i++) {
        uint8_t value = ascii_hex_digit_value(source[i]);
        if (value > 0xf) {
            break;
        }
        codepoint <<= 4;
        codepoint += value;
    }

    return codepoint_to_utf8(codepoint, encoded_length);
}

/**
 * Recognize Unicode escapes in the form \u{NNNNN} and encode the
 * represented codepoints into UTF-8.
 * - returns: A string owned by the caller, with all non-escape
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
        const char * const brace_char = next_escape + 2;
        if ('u' != *escape_char || '{' != *brace_char) {
            current_dest = append_contents(current_dest,
                                           current_source,
                                           next_escape);
            current_source = next_escape;
            continue;
        }
     
        const char * const digit_start = brace_char + 1;
        const char * const digit_end = memchr(digit_start, '}', 9);
        if (!digit_end) {
            current_dest = append_contents(current_dest,
                                           current_source,
                                           digit_start);
            current_source = digit_start;
            continue;
        }

        size_t digit_count = digit_end - digit_start;
        size_t encoded_length = 0;
        //TODO: This doesn't account for what's between the braces
        // not being entirely hex digits
        const uint32_t encoded = ascii_hex_to_utf8(digit_start,
                                                   digit_count,
                                                   &encoded_length);
        current_dest = append_contents(current_dest,
                                       current_source,
                                       next_escape);
        memcpy(current_dest, &encoded, encoded_length);
        current_dest += encoded_length;
        current_source = (char *)digit_end + 1;
    }

    current_dest = append_contents(current_dest,
                                   current_source,
                                   (source + count));
    *current_dest = '\0';

    return result;
}

int main (int argc, char const *argv[])
{
    char * source = contents_of_file("input.txt");
    if (!source) {
        exit(1);
    }
    
    char * rendered = render_escapes(source);

    printf("%s", rendered);
    
    free(source);
    free(rendered);

    return 0;
}
