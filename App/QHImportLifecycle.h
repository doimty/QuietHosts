#ifndef QH_IMPORT_LIFECYCLE_H
#define QH_IMPORT_LIFECYCLE_H
#include <stdbool.h>
#include <stdint.h>
/* Main-thread-only model. A borrowed picker identity plus a generation prevents
 * old cancel/dismiss callbacks from ending a selected-file read or a new import.
 * This model does not mutate rules, storage or the controller's busy flag. */
typedef enum { QHImportIdle, QHImportPicking, QHImportReading } QHImportPhase;
typedef struct {
    uint64_t generation;
    const void *picker;
    QHImportPhase phase;
} QHImportLifecycle;
static inline uint64_t QHImportBegin(QHImportLifecycle *s, const void *picker) {
    if (!picker) {
        return 0;
    }
    if (++s->generation == 0) {
        ++s->generation;
    }
    s->picker = picker;
    s->phase = QHImportPicking;
    return s->generation;
}
static inline bool QHImportCancel(QHImportLifecycle *s, const void *picker) {
    if (!picker || s->phase != QHImportPicking || s->picker != picker) {
        return false;
    }
    s->picker = 0;
    s->phase = QHImportIdle;
    if (++s->generation == 0) {
        ++s->generation;
    }
    return true;
}
static inline uint64_t QHImportSelect(QHImportLifecycle *s, const void *picker) {
    if (!picker || s->phase != QHImportPicking || s->picker != picker) {
        return 0;
    }
    s->picker = 0;
    s->phase = QHImportReading;
    return s->generation;
}
static inline bool QHImportIsReading(const QHImportLifecycle *s, uint64_t generation) {
    return generation && s->phase == QHImportReading && s->generation == generation;
}
static inline bool QHImportFinishRead(QHImportLifecycle *s, uint64_t generation) {
    if (!QHImportIsReading(s, generation)) {
        return false;
    }
    s->phase = QHImportIdle;
    return true;
}
#endif
