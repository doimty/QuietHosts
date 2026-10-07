#ifndef QH_PARSER_H
#define QH_PARSER_H
#include <stdbool.h>
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
#define QHParserMaximumBytes (16u * 1024u * 1024u)
typedef enum {
    QHParseOK = 0,
    QHParseTooLarge,
    QHParseInvalidEncoding,
    QHParseConsumerStopped,
    QHParseInvalidAllowlist
} QHParseStatus;
typedef struct {
    size_t lines, ignoredLines, redirectLines, invalidLines, invalidNames;
    size_t localNames, acceptedNames, unsupported, firstRejectedLine;
} QHParserStats;
typedef bool (*QHDomainConsumer)(const char *domain, void *context);
/* Allocation-free synchronous parser. Fully validates UTF-8 before callbacks;
 * input remains untouched. Domain storage is borrowed, valid only in callback.
 * CR/LF/CRLF physical lines, no phantom EOF line. Emits duplicates; caller owns
 * deduplication and rollback after ANY failure. Strict allowlist accepts only
 * one exact bare name per line; firstRejectedLine identifies whole-list failure.
 * acceptedNames includes a callback which returns false. Unsupported counts
 * tokens (or whole rejected syntax lines); invalidLines/names are disjoint.
 */
QHParseStatus QHParserParse(const unsigned char *bytes, size_t length, bool allowlist,
                            QHDomainConsumer consumer, void *context, QHParserStats *stats);
/* ASCII hostname grammar, >=2 labels, at least one ASCII letter, one final dot
 * removed. A-label/punycode spellings accepted syntactically, no IDNA conversion.
 * Local metadata is checked separately. output needs 254 bytes. */
bool QHCanonicalDomain(const unsigned char *bytes, size_t length, char output[254]);
bool QHLocalDomain(const char *domain);
#ifdef __cplusplus
}
#endif
#endif
