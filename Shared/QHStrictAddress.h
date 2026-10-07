/* Adapted from NetShield2. Copyright (c) 2026 EolnMsuk.
 * SPDX-License-Identifier: MIT. See LICENSE and third-party notices. */
#ifndef QH_STRICT_ADDRESS_H
#define QH_STRICT_ADDRESS_H

#include <arpa/inet.h>
#include <stdbool.h>
#include <stddef.h>
#include <string.h>

// Darwin accepts leading-zero IPv4 and IPv6 %zones that musl rejects.
// Import and URL validation need a platform-independent, unambiguous grammar.
static inline bool QHStrictIPv4Text(const char *text) {
    for (unsigned int part = 0; part < 4; part++) {
        const char *start = text;
        unsigned int value = 0;
        while (*text >= '0' && *text <= '9') {
            if (text - start >= 3) {
                return false;
            }
            value = value * 10u + (unsigned int)(*text++ - '0');
        }
        if (text == start || value > 255u || (text - start > 1 && *start == '0')) {
            return false;
        }
        if (part == 3) {
            return *text == '\0';
        }
        if (*text++ != '.') {
            return false;
        }
    }
    return false;
}
static inline int QHStrictInetPton(int family, const char *text, void *address) {
    if (!text || !*text) {
        return 0;
    }
    if (family == AF_INET) {
        return QHStrictIPv4Text(text) ? inet_pton(family, text, address) : 0;
    }
    if (family != AF_INET6) {
        return 0;
    }
    for (const char *p = text; *p; p++) {
        if (!((*p >= '0' && *p <= '9') || (*p >= 'a' && *p <= 'f') || (*p >= 'A' && *p <= 'F') || *p == ':' ||
              *p == '.')) {
            return 0;
        }
    }
    if (strchr(text, '.')) {
        const char *tail = strrchr(text, ':');
        if (!tail || !QHStrictIPv4Text(tail + 1)) {
            return 0;
        }
    }
    return inet_pton(family, text, address);
}
#endif
