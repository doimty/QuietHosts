#include "../App/QHImportLifecycle.h"
#include <assert.h>
#include <stdio.h>
int main(void) {
    QHImportLifecycle s = {0};
    int first, second;
    uint64_t a = QHImportBegin(&s, &first);
    assert(a && s.phase == QHImportPicking);
    assert(QHImportCancel(&s, &first));
    assert(s.phase == QHImportIdle);
    assert(!QHImportCancel(&s, &first)); // duplicate button + gesture callback
    assert(!QHImportSelect(&s, &first)); // cancelled picker delivers a stale URL
    uint64_t b = QHImportBegin(&s, &second);
    assert(b != a);
    assert(!QHImportCancel(&s, &first));
    assert(s.phase == QHImportPicking);
    assert(!QHImportSelect(&s, &first));
    uint64_t selected = QHImportSelect(&s, &second);
    assert(selected == b);
    assert(QHImportIsReading(&s, b));
    assert(!QHImportCancel(&s, &second)); // automatic selected-picker dismissal
    assert(!QHImportSelect(&s, &second)); // callback can be consumed only once
    assert(!QHImportFinishRead(&s, a));
    assert(QHImportIsReading(&s, b));
    assert(QHImportFinishRead(&s, b));
    assert(s.phase == QHImportIdle);
    assert(!QHImportFinishRead(&s, b));
    uint64_t c = QHImportBegin(&s, &first);
    assert(c != b);
    assert(!QHImportCancel(&s, &second));
    assert(QHImportCancel(&s, &first));
    s.generation = UINT64_MAX;
    assert(QHImportBegin(&s, &first) != 0);
    assert(QHImportCancel(&s, &first));
    puts("Import lifecycle: swipe/button cancel, stale/duplicate callbacks, selected read and retry PASS");
    return 0;
}
