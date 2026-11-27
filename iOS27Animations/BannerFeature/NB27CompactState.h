#pragma once
#include <stdbool.h>
#include <stdint.h>

typedef struct {
    uintptr_t generation, pending, previewTicket, retainedTicket, previousRetainedTicket;
    bool enabled, preview, revealComplete, retained, fading, retainedTimerPending, pendingHadRetained;
} NB27CompactState;
static inline void NB27CompactStateEnable(NB27CompactState *s, bool enabled) {
    s->enabled = enabled;
    if (!enabled) {
        s->pending = 0; s->preview = false; s->previewTicket = 0; s->revealComplete = false;
        s->retained = false; s->retainedTicket = 0; s->fading = false;
        s->retainedTimerPending = false; s->pendingHadRetained = false; s->previousRetainedTicket = 0;
    }
}
static inline uintptr_t NB27CompactStateBegin(NB27CompactState *s, bool supported) {
    bool carry = s->retained || (s->pending && s->preview);
    uintptr_t previous = s->pending && s->preview ? s->pending : s->retainedTicket;
    s->pending = 0; s->preview = false; s->previewTicket = 0; s->revealComplete = false; s->fading = false;
    s->pendingHadRetained = false; s->previousRetainedTicket = 0;
    if (carry) { s->retained = true; s->retainedTicket = previous; s->retainedTimerPending = false; }
    if (!s->enabled || !supported || s->generation == UINTPTR_MAX) return 0;
    s->pendingHadRetained = carry; s->previousRetainedTicket = carry ? previous : 0;
    s->pending = ++s->generation;
    if (carry) {
        s->retainedTicket = s->pending; s->retainedTimerPending = false;
        s->preview = true; s->previewTicket = s->pending;
    }
    return s->pending;
}
static inline double NB27CompactStateReveal(double progress) {
    if (progress <= 0.65) return 0;
    if (progress >= 1) return 1;
    double t = (progress - 0.65) / 0.35;
    return t * t * (3.0 - 2.0 * t);
}
static inline bool NB27CompactStateRevealStart(NB27CompactState *s, uintptr_t ticket) {
    if (!s->enabled || !ticket ||
        (ticket != s->pending && !(s->retained && ticket == s->retainedTicket))) return false;
    s->preview = true; s->previewTicket = ticket; s->revealComplete = false;
    if (s->pending != ticket) s->retainedTimerPending = false;
    return true;
}
static inline bool NB27CompactStateRevealComplete(NB27CompactState *s, uintptr_t ticket) {
    if (!s->preview || !ticket || ticket != s->previewTicket) return false;
    s->revealComplete = true;
    if (s->pending != ticket) { s->preview = false; s->previewTicket = 0; }
    return true;
}
static inline bool NB27CompactStateFinish(NB27CompactState *s, uintptr_t ticket) {
    if (!s->enabled || !ticket || ticket != s->pending) return false;
    s->pending = 0; s->fading = false; s->retained = true; s->retainedTicket = ticket;
    s->retainedTimerPending = false; s->pendingHadRetained = false;
    if (s->revealComplete) { s->preview = false; s->previewTicket = 0; }
    return true;
}
static inline bool NB27CompactStateScheduleExpiry(NB27CompactState *s, uintptr_t ticket) {
    if (!s->enabled || !s->retained || s->retainedTimerPending || !ticket || ticket != s->retainedTicket) return false;
    s->retainedTimerPending = true; return true;
}
static inline bool NB27CompactStateBeginFade(NB27CompactState *s, uintptr_t ticket) {
    if (!s->enabled || !s->retained || !s->retainedTimerPending || s->fading || !ticket || ticket != s->retainedTicket) return false;
    s->fading = true; return true;
}
static inline bool NB27CompactStateExpire(NB27CompactState *s, uintptr_t ticket) {
    if (!s->enabled || !s->retained || !ticket || ticket != s->retainedTicket) return false;
    s->retained = false; s->retainedTicket = 0; s->fading = false; s->retainedTimerPending = false;
    return true;
}
static inline bool NB27CompactStateAbort(NB27CompactState *s, uintptr_t ticket) {
    if (!s->enabled || !ticket || ticket != s->pending) return false;
    s->pending = 0; s->preview = false; s->previewTicket = 0; s->revealComplete = false; s->fading = false;
    s->retained = s->pendingHadRetained;
    s->retainedTicket = s->pendingHadRetained ? s->previousRetainedTicket : 0;
    s->pendingHadRetained = false; s->previousRetainedTicket = 0; s->retainedTimerPending = false;
    return true;
}
