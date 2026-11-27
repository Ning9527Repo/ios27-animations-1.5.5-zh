#pragma once
#import <UIKit/UIKit.h>

/* SpringBoard only; default disabled. SetEnabled/Finish/Abort marshal to main
 * asynchronously if needed. Other APIs are main-thread only (NO/0 off-main).
 * No hooks or preference writes. Integrator must compile NB27Compact.m.
 * Begin only when Origin is supported; Finish only for a normal completed exit,
 * Abort for interruption. Tickets are single-use and newer Begin supersedes old.
 * NoteEntrance updates the reference only: it never clears a retained line.
 * Disabling the user preference clears retention; system safety gating only
 * hides retained content, which may reappear when safe. No unread-count logic.
 * Origin uses model geometry in card.superview, never presentation layers;
 * both output pointers must be non-NULL and remain untouched on failure. */
FOUNDATION_EXPORT void NB27CompactSetEnabled(BOOL enabled);
FOUNDATION_EXPORT void NB27CompactNoteEntrance(UIView *card);
typedef struct {
    CGRect line, screenBounds, sceneBounds;
    double capturedAt;
    BOOL valid;
} NB27CompactAnchor;
/* Capture screen geometry before native layout; convert only after it settles. */
FOUNDATION_EXPORT NB27CompactAnchor NB27CompactPrepareTimeAnchor(UIView *reference);
FOUNDATION_EXPORT BOOL NB27CompactOriginFromAnchor(UIView *card, NB27CompactAnchor anchor,
    CGPoint *centerInLayerParent, CGSize *lineSize);
FOUNDATION_EXPORT NSUInteger NB27CompactBeginExit(BOOL supported);
FOUNDATION_EXPORT void NB27CompactAnimateExit(NSUInteger ticket, double duration);
FOUNDATION_EXPORT void NB27CompactFinishExit(NSUInteger ticket);
FOUNDATION_EXPORT void NB27CompactAbortExit(NSUInteger ticket);
