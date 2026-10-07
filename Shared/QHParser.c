/* Adapted from NetShield2. Copyright (c) 2026 EolnMsuk.
 * SPDX-License-Identifier: MIT. See LICENSE and third-party notices. */
#include "QHParser.h"
#include "QHStrictAddress.h"
#include <stdint.h>
#include <string.h>

/* Reject non-shortest forms, surrogates, out-of-range scalars and controls.
 * Non-ASCII UTF-8 is permitted in comments, but never in address/name fields. */
static bool ValidEncoding(const unsigned char *bytes, size_t length, size_t *badOffset) {
    size_t i = 0;
    while (i < length) {
        *badOffset = i;
        uint32_t scalar = bytes[i++];
        if (scalar < 0x80) {
            if ((scalar < 0x20 && scalar != '\t' && scalar != '\n' && scalar != '\r') || scalar == 0x7f) {
                return false;
            }
            continue;
        }
        size_t remaining;
        uint32_t minimum;
        if (scalar >= 0xc2 && scalar <= 0xdf) {
            remaining = 1;
            minimum = 0x80;
            scalar &= 0x1f;
        } else if (scalar >= 0xe0 && scalar <= 0xef) {
            remaining = 2;
            minimum = 0x800;
            scalar &= 0x0f;
        } else if (scalar >= 0xf0 && scalar <= 0xf4) {
            remaining = 3;
            minimum = 0x10000;
            scalar &= 0x07;
        } else {
            return false;
        }
        if (remaining > length - i) {
            return false;
        }
        while (remaining-- != 0) {
            unsigned char next = bytes[i++];
            if ((next & 0xc0) != 0x80) {
                return false;
            }
            scalar = (scalar << 6) | (next & 0x3f);
        }
        if (scalar < minimum || scalar > 0x10ffff || (scalar >= 0xd800 && scalar <= 0xdfff) ||
            scalar <= 0x9f) {
            return false;
        }
    }
    return true;
}

static bool Space(unsigned char byte) {
    return byte == ' ' || byte == '\t';
}

/* -1 invalid, 0 redirect, 1 block. Compare bytes, not IPv6 spellings. */
static int AddressKind(const unsigned char *bytes, size_t length) {
    char text[INET6_ADDRSTRLEN];
    unsigned char address[16];
    if (length == 0 || length >= sizeof(text)) {
        return -1;
    }
    memcpy(text, bytes, length);
    text[length] = '\0';
    if (QHStrictInetPton(AF_INET, text, address) == 1) {
        return (address[0] == 0 && address[1] == 0 && address[2] == 0 && address[3] == 0) ||
               (address[0] == 127 && address[1] == 0 && address[2] == 0 && address[3] == 1);
    }
    if (QHStrictInetPton(AF_INET6, text, address) == 1) {
        for (size_t i = 0; i < 15; i++) {
            if (address[i] != 0) {
                return 0;
            }
        }
        return address[15] <= 1;
    }
    return -1;
}

bool QHCanonicalDomain(const unsigned char *bytes, size_t length, char output[254]) {
    if (length != 0 && bytes[length - 1] == '.') {
        length--;
    }
    if (length == 0 || length > 253) {
        return false;
    }
    size_t label = 0;
    bool letter = false;
    for (size_t i = 0; i < length; i++) {
        unsigned char c = bytes[i];
        if (c >= 'A' && c <= 'Z') {
            c = (unsigned char)(c + ('a' - 'A'));
        }
        if (c == '.') {
            if (label == 0 || output[i - 1] == '-') {
                return false;
            }
            label = 0;
        } else {
            bool alpha = c >= 'a' && c <= 'z';
            if ((!alpha && !(c >= '0' && c <= '9') && c != '-') || (label == 0 && c == '-') || ++label > 63) {
                return false;
            }
            letter = letter || alpha;
        }
        output[i] = (char)c;
    }
    if (memchr(bytes, '.', length) == NULL || !letter || label == 0 || output[length - 1] == '-') {
        return false;
    }
    output[length] = '\0';
    return true;
}

bool QHLocalDomain(const char *name) {
    static const char *const names[] = {"localhost", "localhost.localdomain", "ip6-localhost", "ip6-loopback",
                                        "broadcasthost", "ip6-allnodes", "ip6-allrouters",
                                        /* Conventional /etc/hosts IPv6 network/multicast metadata aliases. */
                                        "ip6-localnet", "ip6-mcastprefix", "ip6-allhosts"};
    for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); i++) {
        if (strcmp(name, names[i]) == 0) {
            return true;
        }
    }
    size_t length = strlen(name);
    return length > 10 && strcmp(name + length - 10, ".localhost") == 0;
}

/* Recognize only exact Surge DOMAIN records in a block source. Untagged
 * rule-set records and explicit REJECT/REJECT-DROP are accepted; DIRECT,
 * proxy policies, extra options and non-exact forms are never reinterpreted.
 * Return 0=other syntax, 1=domain span, -1=unsupported DOMAIN action/options. */
static bool EqualASCII(const unsigned char *p, size_t n, const char *word) {
    if (n != strlen(word)) {
        return false;
    }
    for (size_t i = 0; i < n; i++) {
        unsigned char c = p[i];
        if (c >= 'a' && c <= 'z') {
            c = (unsigned char)(c - ('a' - 'A'));
        }
        if (c != (unsigned char)word[i]) {
            return false;
        }
    }
    return true;
}
static int SurgeExactDomain(const unsigned char *p, size_t n, const unsigned char **name, size_t *length) {
    size_t comma = 0;
    while (comma < n && p[comma] != ',') {
        comma++;
    }
    if (comma == n) {
        return 0;
    }
    size_t typeEnd = comma;
    while (typeEnd && Space(p[typeEnd - 1])) {
        typeEnd--;
    }
    if (!EqualASCII(p, typeEnd, "DOMAIN")) {
        return 0;
    }
    size_t start = comma + 1, end = start;
    while (end < n && p[end] != ',') {
        end++;
    }
    size_t next = end;
    while (start < end && Space(p[start])) {
        start++;
    }
    while (end > start && Space(p[end - 1])) {
        end--;
    }
    if (next < n) {
        size_t actionStart = next + 1, actionEnd = n;
        while (actionStart < actionEnd && Space(p[actionStart])) {
            actionStart++;
        }
        while (actionEnd > actionStart && Space(p[actionEnd - 1])) {
            actionEnd--;
        }
        if (!EqualASCII(p + actionStart, actionEnd - actionStart, "REJECT") &&
            !EqualASCII(p + actionStart, actionEnd - actionStart, "REJECT-DROP")) {
            return -1;
        }
    }
    *name = p + start;
    *length = end - start;
    return 1;
}

static bool Unsupported(const unsigned char *p, size_t n) {
    static const char *const keywords[] = {"DOMAIN",  "DOMAIN-SUFFIX", "DOMAIN-KEYWORD",
                                           "IP-CIDR", "IP-CIDR6",      "IPCIDR"};
    size_t first = 0;
    while (first < n && !Space(p[first]) && p[first] != ',') {
        first++;
    }
    for (size_t k = 0; k < sizeof(keywords) / sizeof(keywords[0]); k++) {
        if (strlen(keywords[k]) != first) {
            continue;
        }
        size_t i = 0;
        for (; i < first; i++) {
            unsigned char c = p[i];
            if (c >= 'a' && c <= 'z') {
                c = (unsigned char)(c - 32);
            }
            if (c != (unsigned char)keywords[k][i]) {
                break;
            }
        }
        if (i == first) {
            return true;
        }
    }
    for (size_t i = 0; i < n; i++) {
        if (strchr("/*,|^=?[]!@;", p[i]) != NULL) {
            return true;
        }
    }
    return false;
}
/* Recognize local single labels too, without relaxing the public grammar. */
static bool LocalToken(const unsigned char *p, size_t n) {
    char text[254];
    if (n && p[n - 1] == '.') {
        n--;
    }
    if (!n || n > 253) {
        return false;
    }
    for (size_t i = 0; i < n; i++) {
        if (p[i] >= 128) {
            return false;
        }
        text[i] = (char)(p[i] >= 'A' && p[i] <= 'Z' ? p[i] + 32 : p[i]);
    }
    text[n] = 0;
    return QHLocalDomain(text);
}
static bool EmitName(const unsigned char *p, size_t n, QHDomainConsumer consumer, void *context,
                     QHParserStats *stats) {
    char domain[254];
    if (Unsupported(p, n)) {
        stats->unsupported++;
    } else if (LocalToken(p, n)) {
        stats->localNames++;
    } else if (!QHCanonicalDomain(p, n, domain)) {
        stats->invalidNames++;
    } else {
        if (!consumer) {
            return false;
        }
        stats->acceptedNames++;
        if (!consumer(domain, context)) {
            stats->firstRejectedLine = stats->lines;
            return false;
        }
        return true;
    }
    if (!stats->firstRejectedLine) {
        stats->firstRejectedLine = stats->lines;
    }
    return true;
}
QHParseStatus QHParserParse(const unsigned char *bytes, size_t length, bool allowlist,
                            QHDomainConsumer consumer, void *context, QHParserStats *stats) {
    QHParserStats discarded;
    if (!stats) {
        stats = &discarded;
    }
    memset(stats, 0, sizeof(*stats));
    if (length > QHParserMaximumBytes) {
        return QHParseTooLarge;
    }
    if (!bytes && length) {
        return QHParseInvalidEncoding;
    }
    size_t badOffset = 0;
    if (!ValidEncoding(bytes, length, &badOffset)) {
        stats->firstRejectedLine = 1;
        for (size_t i = 0; i < badOffset; i++) {
            if (bytes[i] == '\r') {
                stats->firstRejectedLine++;
                if (i + 1 < badOffset && bytes[i + 1] == '\n') {
                    i++;
                }
            } else if (bytes[i] == '\n') {
                stats->firstRejectedLine++;
            }
        }
        return QHParseInvalidEncoding;
    }
    size_t cursor = length >= 3 && memcmp(bytes, "\xef\xbb\xbf", 3) == 0 ? 3 : 0;
    while (cursor < length) {
        size_t start = cursor;
        while (cursor < length && bytes[cursor] != '\r' && bytes[cursor] != '\n') {
            cursor++;
        }
        size_t end = cursor;
        if (cursor < length) {
            unsigned char nl = bytes[cursor++];
            if (nl == '\r' && cursor < length && bytes[cursor] == '\n') {
                cursor++;
            }
        }
        stats->lines++;
        for (size_t i = start; i < end; i++) {
            if (bytes[i] == '#') {
                end = i;
                break;
            }
        }
        while (start < end && Space(bytes[start])) {
            start++;
        }
        while (end > start && Space(bytes[end - 1])) {
            end--;
        }
        if (start == end) {
            stats->ignoredLines++;
            continue;
        }
        if (!allowlist) {
            const unsigned char *domain = NULL;
            size_t domainLength = 0;
            int surge = SurgeExactDomain(bytes + start, end - start, &domain, &domainLength);
            if (surge < 0) {
                stats->unsupported++;
                if (!stats->firstRejectedLine) {
                    stats->firstRejectedLine = stats->lines;
                }
                continue;
            }
            if (surge > 0) {
                if (!EmitName(domain, domainLength, consumer, context, stats)) {
                    return QHParseConsumerStopped;
                }
                continue;
            }
        }
        size_t tokenEnd = start;
        while (tokenEnd < end && !Space(bytes[tokenEnd])) {
            tokenEnd++;
        }
        size_t names = tokenEnd;
        while (names < end && Space(bytes[names])) {
            names++;
        }
        int kind = AddressKind(bytes + start, tokenEnd - start);
        if (allowlist) {
            if (names < end || kind >= 0) {
                if (Unsupported(bytes + start, end - start)) {
                    stats->unsupported++;
                } else {
                    stats->invalidLines++;
                }
                stats->firstRejectedLine = stats->lines;
                return QHParseInvalidAllowlist;
            }
            if (!EmitName(bytes + start, tokenEnd - start, consumer, context, stats)) {
                return QHParseConsumerStopped;
            }
            if (stats->firstRejectedLine) {
                return QHParseInvalidAllowlist;
            }
            continue;
        }
        if (kind >= 0 && names < end) {
            if (kind == 0) {
                stats->redirectLines++;
                continue;
            }
            while (names < end) {
                size_t next = names;
                while (next < end && !Space(bytes[next])) {
                    next++;
                }
                if (!EmitName(bytes + names, next - names, consumer, context, stats)) {
                    return QHParseConsumerStopped;
                }
                names = next;
                while (names < end && Space(bytes[names])) {
                    names++;
                }
            }
        } else if (kind < 0 && names == end) {
            if (!EmitName(bytes + start, tokenEnd - start, consumer, context, stats)) {
                return QHParseConsumerStopped;
            }
        } else {
            if (Unsupported(bytes + start, end - start)) {
                stats->unsupported++;
            } else {
                stats->invalidLines++;
            }
            if (!stats->firstRejectedLine) {
                stats->firstRejectedLine = stats->lines;
            }
        }
    }
    return QHParseOK;
}
