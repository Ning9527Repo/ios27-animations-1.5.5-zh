#import "Bridge.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <QuartzCore/QuartzCore.h>
#import <stdatomic.h>

typedef void (*NGHookFunction)(Class, SEL, IMP, IMP *);
static NGHookFunction gNGHook;
// Preference key: LiquidSwitchEnabled; absent/unreadable updates retain this cache.
static _Atomic(BOOL) gNGSwitchFeatureEnabled = NO;
static NSString *const kNGSwitchChanged = @"com.bazik1337.ios2627anims/changed";

BOOL NGSwitchFeatureEnabled(void) {
    return atomic_load_explicit(&gNGSwitchFeatureEnabled, memory_order_acquire);
}

// Configuration is loaded through the same shared, authorized snapshot in every App.
// Only a validated explicit OFF may remove existing overlays.
static BOOL gNGHasValidSwitchConfiguration = NO;

static void NGVisitSwitches(UIView *view) {
    if ([view isKindOfClass:UISwitch.class]) NGRefreshSwitch((UISwitch *)view);
    for (UIView *child in [view.subviews copy]) NGVisitSwitches(child);
}

static void NGRefreshVisibleSwitches(void) {
    UIApplication *app = UIApplication.sharedApplication;
    for (UIScene *scene in app.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows)
            if (!window.hidden) NGVisitSwitches(window);
    }
}

static void NGApplySwitchFeaturePreference(void) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ NGApplySwitchFeaturePreference(); });
        return;
    }
    BOOL enabled = NO;
    if (!NGLoadSwitchFeaturePreference(&enabled)) return;
    BOOL wasKnown = gNGHasValidSwitchConfiguration;
    gNGHasValidSwitchConfiguration = YES;
    BOOL old = atomic_exchange_explicit(&gNGSwitchFeatureEnabled, enabled, memory_order_acq_rel);
    if (wasKnown && old == enabled) return;
    if (!enabled) { NGRemoveAllSwitches(); return; }
    NGRefreshVisibleSwitches();
}

static void NGRecoverSwitchConfiguration(void) {
    NGPublishSwitchPreferenceIfTrusted();
    NGApplySwitchFeaturePreference();
    if (NGSwitchFeatureEnabled()) NGRefreshVisibleSwitches();
}

static void NGSwitchPreferenceChanged(__unused CFNotificationCenterRef center, __unused void *observer,
                                      __unused CFStringRef name, __unused const void *object,
                                      __unused CFDictionaryRef userInfo) {
    NGApplySwitchFeaturePreference();
}
static void (*gSWLayout)(id,SEL), (*gSWWindow)(id,SEL), (*gSWParent)(id,SEL);
static void (*gSWOn)(id,SEL,BOOL), (*gSWEnabled)(id,SEL,BOOL), (*gSWHidden)(id,SEL,BOOL);
static void (*gSWAlpha)(id,SEL,CGFloat), (*gSWInteraction)(id,SEL,BOOL);
static void (*gSWOnAnimated)(id,SEL,BOOL,BOOL);

static void (*gSWFrame)(id,SEL,CGRect), (*gSWBounds)(id,SEL,CGRect);
static void (*gSWCenter)(id,SEL,CGPoint);
static void (*gSWTransform)(id,SEL,CGAffineTransform);

static void NGSwitchFrame(UISwitch *s, SEL c, CGRect v) { if (gSWFrame) gSWFrame(s,c,v); if (NGSwitchFeatureEnabled()) NGSyncSwitchGeometry(s); else NGRemoveSwitch(s); }
static void NGSwitchBounds(UISwitch *s, SEL c, CGRect v) { if (gSWBounds) gSWBounds(s,c,v); if (NGSwitchFeatureEnabled()) NGSyncSwitchGeometry(s); else NGRemoveSwitch(s); }
static void NGSwitchCenter(UISwitch *s, SEL c, CGPoint v) { if (gSWCenter) gSWCenter(s,c,v); if (NGSwitchFeatureEnabled()) NGSyncSwitchGeometry(s); else NGRemoveSwitch(s); }
static void NGSwitchTransform(UISwitch *s, SEL c, CGAffineTransform v) { if (gSWTransform) gSWTransform(s,c,v); if (NGSwitchFeatureEnabled()) NGSyncSwitchGeometry(s); else NGRemoveSwitch(s); }

static void NGSwitchLayout(UISwitch *s,SEL c) { if (gSWLayout) gSWLayout(s,c); if (NGSwitchFeatureEnabled()) NGRefreshSwitch(s); else NGRemoveSwitch(s); }
static void NGSwitchWindow(UISwitch *s,SEL c) { if (gSWWindow) gSWWindow(s,c); if (NGSwitchFeatureEnabled()) NGRefreshSwitch(s); else NGRemoveSwitch(s); }
static void NGSwitchParent(UISwitch *s,SEL c) { if (gSWParent) gSWParent(s,c); if (NGSwitchFeatureEnabled()) NGRefreshSwitch(s); else NGRemoveSwitch(s); }
static void NGClockNativeWithoutAnimation(void (^changes)(void)) {
    [UIView performWithoutAnimation:^{
        [CATransaction begin]; [CATransaction setDisableActions:YES];
        @try { changes(); } @finally { [CATransaction commit]; }
    }];
}
static void NGSwitchOn(UISwitch *s,SEL c,BOOL v) {
    if (!NGSwitchFeatureEnabled()) { if (gSWOn) gSWOn(s,c,v); return; }
    if (gSWOn) {
        if (NGClockHasSwitchOverlay(s)) NGClockNativeWithoutAnimation(^{ gSWOn(s,c,v); });
        else gSWOn(s,c,v);
    }
    NGScheduleSwitchSync(s);
}
static void NGSwitchOnAnimated(UISwitch *s,SEL c,BOOL v,BOOL a) {
    if (!NGSwitchFeatureEnabled()) { if (gSWOnAnimated) gSWOnAnimated(s,c,v,a); return; }
    if (gSWOnAnimated) {
        if (NGClockHasSwitchOverlay(s)) NGClockNativeWithoutAnimation(^{ gSWOnAnimated(s,c,v,NO); });
        else gSWOnAnimated(s,c,v,a);
    }
    NGScheduleSwitchSync(s);
}
static void NGHookSwitchEnabled(UISwitch *s,SEL c,BOOL v) { if (gSWEnabled) gSWEnabled(s,c,v); if (NGSwitchFeatureEnabled()) NGScheduleSwitchSync(s); else NGRemoveSwitch(s); }
static void NGSwitchHidden(UISwitch *s,SEL c,BOOL v) { if (gSWHidden) gSWHidden(s,c,v); if (NGSwitchFeatureEnabled()) NGRefreshSwitch(s); else NGRemoveSwitch(s); }
static void NGSwitchAlpha(UISwitch *s,SEL c,CGFloat v) {
    if (!NGSwitchFeatureEnabled()) { if (gSWAlpha) gSWAlpha(s,c,v); NGRemoveSwitch(s); return; }
    BOOL replaced=NGHandleSwitchAlpha(s,v);
    if (!gSWAlpha) return;
    if (replaced && [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.mobiletimer"]) {
        NGClockNativeWithoutAnimation(^{
            gSWAlpha(s,c,0);
            if ([s.layer animationForKey:@"opacity"]) [s.layer removeAnimationForKey:@"opacity"];
        });
    } else { gSWAlpha(s,c,replaced?0:v); }
}
static void NGSwitchInteraction(UISwitch *s,SEL c,BOOL v) { if (gSWInteraction) gSWInteraction(s,c,v); if (NGSwitchFeatureEnabled()) NGRefreshSwitch(s); else NGRemoveSwitch(s); }

// Only Clock's alarm data source and cell are hooked. These standard UIKit
// selectors are present in the supplied trace's configuration call stack.
static void (*gAlarmPrepareForReuse)(id,SEL);
static UITableViewCell *(*gAlarmCellForRow)(id,SEL,UITableView *,NSIndexPath *);
static void NGAlarmPrepareForReuse(UITableViewCell *cell, SEL sel) {
    NGClockResetAlarmCell(cell);
    if (gAlarmPrepareForReuse) gAlarmPrepareForReuse(cell,sel);
}
static UITableViewCell *NGAlarmCellForRow(id controller, SEL sel, UITableView *table, NSIndexPath *path) {
    UITableViewCell *cell = gAlarmCellForRow(controller,sel,table,path);
    // Configuration is complete. Snap to the authoritative value before
    // returning the cell to UIKit, regardless of its previous row/value.
    NGClockResetAlarmCell(cell);
    NGClockScheduleReplay(table);
    return cell;
}

static void NGInstallMethod(Class cls, SEL sel, IMP replacement, IMP *original) {
    if (!cls || !gNGHook || !replacement || !original || *original) return;
    Method method = class_getInstanceMethod(cls,sel); if (!method) return;
    // Materialize inherited methods on this class instead of mutating UIView.
    class_addMethod(cls,sel,method_getImplementation(method),method_getTypeEncoding(method));
    gNGHook(cls,sel,replacement,original);
}

static void NGInstallClockReuseHooks(void) {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.mobiletimer"]) return;
    NGInstallMethod(NSClassFromString(@"MTAAlarmTableViewCell"), @selector(prepareForReuse),
                    (IMP)NGAlarmPrepareForReuse, (IMP *)&gAlarmPrepareForReuse);
    NGInstallMethod(NSClassFromString(@"MTAAlarmTableViewController"), @selector(tableView:cellForRowAtIndexPath:),
                    (IMP)NGAlarmCellForRow, (IMP *)&gAlarmCellForRow);
}

#ifndef NG_TESTING
__attribute__((constructor)) static void NGInitialize(void) {
    if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.Preferences"] ||
        [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.bazik1337.ios2627anims.prefs"]) return;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, NGSwitchPreferenceChanged,
                                        (__bridge CFStringRef)kNGSwitchChanged, NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
        gNGHook = (NGHookFunction)dlsym(RTLD_DEFAULT,"MSHookMessageEx");
        if (!gNGHook) {
            for (NSString *path in @[@"/usr/lib/libsubstrate.dylib",@"/var/jb/usr/lib/libsubstrate.dylib"]) {
                void *handle=dlopen(path.UTF8String,RTLD_NOW|RTLD_LOCAL);
                if (handle) gNGHook=(NGHookFunction)dlsym(handle,"MSHookMessageEx");
                if (gNGHook) break;
            }
        }
        Class sw = UISwitch.class;
        NGInstallMethod(sw,@selector(layoutSubviews),(IMP)NGSwitchLayout,(IMP *)&gSWLayout);
        NGInstallMethod(sw,@selector(didMoveToWindow),(IMP)NGSwitchWindow,(IMP *)&gSWWindow);
        NGInstallMethod(sw,@selector(didMoveToSuperview),(IMP)NGSwitchParent,(IMP *)&gSWParent);
        NGInstallMethod(sw,@selector(setOn:),(IMP)NGSwitchOn,(IMP *)&gSWOn);
        NGInstallMethod(sw,@selector(setOn:animated:),(IMP)NGSwitchOnAnimated,(IMP *)&gSWOnAnimated);
        NGInstallMethod(sw,@selector(setEnabled:),(IMP)NGHookSwitchEnabled,(IMP *)&gSWEnabled);
        NGInstallMethod(sw,@selector(setHidden:),(IMP)NGSwitchHidden,(IMP *)&gSWHidden);
        NGInstallMethod(sw,@selector(setAlpha:),(IMP)NGSwitchAlpha,(IMP *)&gSWAlpha);
        NGInstallMethod(sw,@selector(setUserInteractionEnabled:),(IMP)NGSwitchInteraction,(IMP *)&gSWInteraction);
        // Install only on UISwitch and outside Clock; no global UIView hook or polling.
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.mobiletimer"]) {
            NGInstallMethod(sw,@selector(setFrame:),(IMP)NGSwitchFrame,(IMP *)&gSWFrame);
            NGInstallMethod(sw,@selector(setBounds:),(IMP)NGSwitchBounds,(IMP *)&gSWBounds);
            NGInstallMethod(sw,@selector(setCenter:),(IMP)NGSwitchCenter,(IMP *)&gSWCenter);
            NGInstallMethod(sw,@selector(setTransform:),(IMP)NGSwitchTransform,(IMP *)&gSWTransform);
        }
        NGInstallClockReuseHooks();
        // Retry once the main application has completed loading its classes.
        if ([NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.mobiletimer"])
            dispatch_async(dispatch_get_main_queue(), ^{ NGInstallClockReuseHooks(); });
        dispatch_async(dispatch_get_main_queue(), ^{
            NSUInteger installed = !!gSWLayout + !!gSWWindow + !!gSWParent + !!gSWOn + !!gSWOnAnimated +
                !!gSWEnabled + !!gSWHidden + !!gSWAlpha + !!gSWInteraction + !!gSWFrame + !!gSWBounds +
                !!gSWCenter + !!gSWTransform + !!gAlarmPrepareForReuse + !!gAlarmCellForRow;
            NGSwitchFeatureDiagnostic(@"hooks-installed", [NSString stringWithFormat:@"slots=%lu engine=%d",
                (unsigned long)installed, gNGHook != NULL]);
            NGRecoverSwitchConfiguration();
            for (NSString *name in @[UIApplicationDidFinishLaunchingNotification, UIApplicationDidBecomeActiveNotification]) {
                [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
                    usingBlock:^(__unused NSNotification *notification) { NGRecoverSwitchConfiguration(); }];
            }
            // Bounded startup recovery for a publisher/sandyd that starts after this App.
            for (NSNumber *delay in @[@0.5, @2, @5]) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                    if (!gNGHasValidSwitchConfiguration) NGRecoverSwitchConfiguration();
                });
            }
        });
    });
}
#endif
