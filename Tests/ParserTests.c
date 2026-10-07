#include "../Shared/QHParser.h"
#include "../Shared/QHStrictAddress.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    size_t count;
    char names[16][254];
    bool stop;
} Sink;
static bool consume(const char *name, void *context) {
    Sink *s = context;
    if (s->count < 16) {
        strcpy(s->names[s->count], name);
    }
    s->count++;
    return !s->stop;
}
static QHParserStats parse(const char *text, Sink *sink) {
    QHParserStats stats;
    assert(QHParserParse((const unsigned char *)text, strlen(text), false, consume, sink, &stats) ==
           QHParseOK);
    return stats;
}
static void encoding(void) {
    const unsigned char bad[][8] = {{0},
                                    {0xc0, 0xaf},
                                    {0xed, 0xa0, 0x80},
                                    {0xf4, 0x90, 0x80, 0x80},
                                    {0x80},
                                    {0xe2, 0x82},
                                    {0xc2, 0x85},
                                    {0x7f},
                                    {0x01},
                                    {0xf5, 0x80, 0x80, 0x80}};
    const size_t sizes[] = {1, 2, 3, 4, 1, 2, 2, 1, 1, 4};
    for (size_t i = 0; i < sizeof(sizes) / sizeof(*sizes); i++) {
        unsigned char input[32] = "valid.example\n#";
        const size_t prefix = strlen((const char *)input);
        memcpy(input + prefix, bad[i], sizes[i]);
        Sink sink = {0};
        QHParserStats stats;
        assert(QHParserParse(input, prefix + sizes[i], false, consume, &sink, &stats) ==
               QHParseInvalidEncoding);
        assert(sink.count == 0 && stats.acceptedNames == 0 && stats.lines == 0);
        assert(stats.firstRejectedLine == 2);
    }
    Sink sink = {0};
    QHParserStats stats = parse("\xef\xbb\xbf# 中文\r\nEXAMPLE.COM.\rfoo.example\n", &sink);
    assert(stats.lines == 3 && stats.ignoredLines == 1 && sink.count == 2);
    assert(!strcmp(sink.names[0], "example.com"));
}
static void grammar(void) {
    Sink sink = {0};
    QHParserStats stats =
        parse("0.0.0.0 A.Example b.example\r\n127.0.0.1 c.example\n:: d.example\n"
              "0:0:0:0:0:0:0:1 E.Example.\nfoo.example\n0.0.0.0 localhost ip6-localhost "
              "localhost.localdomain a.localhost\n"
              "8.8.8.8 redirect.example\n::ffff:127.0.0.1 redirect.example\n"
              "00.0.0.0 bad.example\n127.1 bad.example\n::1%lo0 bad.example\n"
              "DOMAIN,ad.example\nDOMAIN-SUFFIX,example.com\nDOMAIN-KEYWORD,ad\nIP-CIDR,1.2.3.0/24\n"
              "https://url.example/path\n*.wild.example\n||ad.example^\n"
              "0.0.0.0 valid.example /path.example bad_name.example\n"
              "1.2.3.4\nsingle\n-bad.example\nbad-.example\na..example\na.example..\n中文.example\n"
              "a.example b.example\n0.0.0.0\nwww.exact.example\nxn--fiqs8s.example\n",
              &sink);
    assert(sink.count == 9 && stats.acceptedNames == 9);
    assert(stats.localNames == 4 && stats.redirectLines == 2);
    assert(stats.invalidLines == 6 && stats.invalidNames == 7 && stats.unsupported == 8);
    assert(!strcmp(sink.names[7], "www.exact.example"));
    assert(!strcmp(sink.names[8], "xn--fiqs8s.example"));
    sink = (Sink){0};
    stats = parse("DOMAIN-SUFFIX example.com\ndomain-keyword ad\nIPCIDR 1.2.3.0/24\n", &sink);
    assert(stats.unsupported == 3 && stats.invalidLines == 0 && sink.count == 0);
    char out[254], text[256];
    memset(text, 'a', 63);
    strcpy(text + 63, ".example");
    assert(QHCanonicalDomain((unsigned char *)text, strlen(text), out));
    memmove(text + 64, text + 63, 9);
    text[63] = 'a';
    assert(!QHCanonicalDomain((unsigned char *)text, strlen(text), out));
    size_t pos = 0;
    for (int label = 0; label < 4; label++) {
        size_t n = label == 3 ? 61 : 63;
        memset(text + pos, 'a', n);
        pos += n;
        if (label < 3) {
            text[pos++] = '.';
        }
    }
    assert(pos == 253 && QHCanonicalDomain((unsigned char *)text, pos, out));
    text[pos++] = '.';
    assert(QHCanonicalDomain((unsigned char *)text, pos, out));
    text[pos - 1] = 'a';
    assert(!QHCanonicalDomain((unsigned char *)text, pos, out));
    unsigned char address[16];
    assert(!QHStrictInetPton(AF_INET, "01.2.3.4", address));
    assert(!QHStrictInetPton(AF_INET6, "::ffff:01.2.3.4", address));
    assert(!QHStrictInetPton(AF_INET6, "::1%en0", address));
}
static void allowlist(void) {
    const char *invalid[] = {"0.0.0.0 a.example", "127.0.0.1",        "https://a.example",
                             "*.a.example",       "DOMAIN,a.example", "single",
                             "localhost",         "a.localhost",      "a.example b.example",
                             "a..example",        "1.2.3.4"};
    for (size_t i = 0; i < sizeof(invalid) / sizeof(*invalid); i++) {
        char text[256];
        snprintf(text, sizeof(text), "# comment\nvalid.example\n%s\n", invalid[i]);
        Sink sink = {0};
        QHParserStats stats;
        assert(QHParserParse((unsigned char *)text, strlen(text), true, consume, &sink, &stats) ==
               QHParseInvalidAllowlist);
        assert(stats.firstRejectedLine == 3 && sink.count == 1);
    }
    const char *text = "# 中文\n\n A.Example. # exact\nwww.a.example\n";
    Sink sink = {0};
    QHParserStats stats;
    assert(QHParserParse((const unsigned char *)text, strlen(text), true, consume, &sink, &stats) ==
           QHParseOK);
    assert(sink.count == 2 && !strcmp(sink.names[0], "a.example"));
}
static void bounds(void) {
    unsigned char *input = malloc(QHParserMaximumBytes + 1u);
    assert(input);
    memset(input, ' ', QHParserMaximumBytes + 1u);
    input[0] = '#';
    Sink sink = {0};
    QHParserStats stats;
    assert(QHParserParse(input, QHParserMaximumBytes, false, consume, &sink, &stats) == QHParseOK);
    assert(stats.lines == 1);
    assert(QHParserParse(input, QHParserMaximumBytes + 1u, false, consume, &sink, &stats) == QHParseTooLarge);
    assert(stats.lines == 0);
    input[QHParserMaximumBytes - 1] = 0;
    assert(QHParserParse(input, QHParserMaximumBytes, false, consume, &sink, &stats) ==
           QHParseInvalidEncoding);
    free(input);
    sink.stop = true;
    assert(QHParserParse((const unsigned char *)"a.example\nb.example", 19, false, consume, &sink, &stats) ==
           QHParseConsumerStopped);
    assert(sink.count == 1 && stats.acceptedNames == 1);
    assert(QHParserParse(NULL, 0, false, consume, &sink, &stats) == QHParseOK);
    assert(QHParserParse(NULL, 1, false, consume, &sink, &stats) == QHParseInvalidEncoding);
    const unsigned char immutable[] = "0.0.0.0 a.example b.example\r\n";
    unsigned char copy[sizeof(immutable)];
    memcpy(copy, immutable, sizeof(copy));
    sink = (Sink){0};
    assert(QHParserParse(copy, sizeof(copy) - 1, false, consume, &sink, &stats) == QHParseOK);
    assert(!memcmp(copy, immutable, sizeof(copy)));
}
int main(void) {
    encoding();
    grammar();
    allowlist();
    bounds();
    puts("ParserTests: PASS (encoding, grammar, allowlist, limits, immutability)");
    return 0;
}
