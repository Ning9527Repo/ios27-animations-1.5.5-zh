#import "NB27Compact.h"
#import "NB27CompactState.h"
#import "NB27ClockText.h"
#import "NB27Diagnostics.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <notify.h>
#include <float.h>
#include <math.h>

/* Model geometry only. No system view/layer is ever mutated. */
@interface NB27CompactWindow : UIWindow
@property(nonatomic) CGRect expectedScreen, expectedScene;
@end
@implementation NB27CompactWindow
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)pointInside:(CGPoint)p withEvent:(UIEvent *)e { (void)p; (void)e; return NO; }
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e { (void)p; (void)e; return nil; }
- (void)layoutSubviews {
    [super layoutSubviews];
    if (!CGRectEqualToRect(self.screen.bounds, self.expectedScreen) ||
        !CGRectEqualToRect(self.windowScene.coordinateSpace.bounds, self.expectedScene) ||
        self.windowScene.interfaceOrientation != UIInterfaceOrientationPortrait) self.hidden = YES;
}
@end
@interface NB27CompactWatch : NSObject
- (void)changed:(NSNotification *)note;
- (void)tick:(NSTimer *)timer;
@end
static NB27CompactState State;
static BOOL Requested, HaveAnchor;
static __weak UIWindowScene *Scene;
static UIScreen *Screen;
static CGRect ScreenBounds, SceneBounds, Bar, CacheBar, Line, SourceBounds;
static __weak UIView *Reference, *TimeItem;
static __weak UIView *TimeLabel; // Native status strings need not inherit UILabel.
static __weak UIWindow *SourceWindow;
static UIColor *Ink;
static NB27CompactWindow *Window;
static CALayer *Stroke;
static NSString *const CompactOpacityKey = @"com.ning.ios2627anims.compact.opacity";
static NSTimer *Timer;
static NB27CompactWatch *Watch;
static CFTimeInterval LastScan = -DBL_MAX;
static void CompactRefresh(void);
static void CompactObserve(void);
static void CompactScheduleExpiry(uintptr_t ticket);

static BOOL CompactRect(CGRect r) {
    return isfinite(r.origin.x) && isfinite(r.origin.y) &&
        isfinite(r.size.width) && isfinite(r.size.height) && r.size.width > 0 && r.size.height > 0;
}
static BOOL CompactSpringBoard(void) {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"];
}
static void CompactDiagnostic(NSString *reason) {
    static unsigned count;
    if (count < 4) {
        ++count;
        NB27Diagnostic(@"compact-anchor-scan", reason);
        NSLog(@"[NB27Compact] compact anchor unavailable: %@", reason);
    }
}
static void CompactClearAnchor(void) {
    HaveAnchor = NO; TimeItem = nil; TimeLabel = nil; SourceWindow = nil; Ink = nil;
    if (Window) Window.hidden = YES;
}
static void CompactDropWindow(void) {
    Window.hidden = YES; Window = nil; Stroke = nil;
}
static BOOL CompactAllowed(void) {
    BOOL allowed = Requested && CompactSpringBoard();
    NB27CompactStateEnable(&State, allowed);
    if (!allowed) {
        CompactClearAnchor(); CompactDropWindow(); [Timer invalidate]; Timer = nil;
    }
    return allowed;
}
/* Reject forwarding, extra arguments and ABI-unknown return types before messaging. */
static char CompactReturn(Method m) {
    if (!m || method_getNumberOfArguments(m) != 2) return 0;
    char a[8] = {0}, b[8] = {0}, r[8] = {0};
    method_getArgumentType(m, 0, a, sizeof(a)); method_getArgumentType(m, 1, b, sizeof(b));
    method_getReturnType(m, r, sizeof(r));
    return ((a[0] == '@' || a[0] == '#') && !a[1] && b[0] == ':' && !b[1] && !r[1]) ? r[0] : 0;
}
static BOOL CompactUnlocked(void) {
    Class cls = NSClassFromString(@"SBLockScreenManager");
    SEL shared = NSSelectorFromString(@"sharedInstance"), locked = NSSelectorFromString(@"isUILocked");
    if (!cls || CompactReturn(class_getClassMethod(cls, shared)) != '@') return NO;
    @try {
        id manager = ((id (*)(id, SEL))objc_msgSend)(cls, shared);
        if (!manager || ![manager isKindOfClass:cls]) return NO;
        char type = CompactReturn(class_getInstanceMethod(cls, locked));
        if (type == 'B') return !((bool (*)(id, SEL))objc_msgSend)(manager, locked);
        if (type == 'c') return !((signed char (*)(id, SEL))objc_msgSend)(manager, locked);
    } @catch (NSException *exception) { (void)exception; }
    return NO;
}
static BOOL CompactVisible(UIView *v) {
    UIWindow *w = v.window;
    for (unsigned depth = 0; v && depth < 16; ++depth, v = v.superview) {
        if (v.hidden || !isfinite(v.alpha) || v.alpha <= .01) return NO;
        if (v == w) return YES;
    }
    return NO;
}
static BOOL CompactReadBar(UIWindowScene *scene, CGRect *bar) {
    if (!scene || !bar) return NO;
    UIScreen *screen = scene.screen;
    if (screen != UIScreen.mainScreen ||
        scene.activationState != UISceneActivationStateForegroundActive ||
        scene.interfaceOrientation != UIInterfaceOrientationPortrait) return NO;
    CGRect sb = screen.coordinateSpace.bounds, cb = scene.coordinateSpace.bounds;
    if (!CompactRect(sb) || !CompactRect(cb) || sb.size.width >= sb.size.height ||
        !CGRectEqualToRect(sb, [scene.coordinateSpace convertRect:cb toCoordinateSpace:screen.coordinateSpace])) return NO;
    UIStatusBarManager *manager = scene.statusBarManager;
    CGRect frame = manager.statusBarFrame;
    if (!manager || manager.statusBarHidden || !CompactRect(frame) ||
        !CGRectContainsRect(sb, frame) || fabs(CGRectGetMinY(frame) - CGRectGetMinY(sb)) > .5 ||
        frame.size.height > sb.size.height * .15) return NO;
    *bar = frame;
    return YES;
}
static UIWindowScene *CompactActiveScene(UIWindowScene *preferred, CGRect *bar) {
    if (CompactReadBar(preferred, bar)) return preferred;
    UIWindowScene *cached = Scene;
    if (cached != preferred && CompactReadBar(cached, bar)) return cached;
    for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) {
        if (![candidate isKindOfClass:UIWindowScene.class] || candidate == preferred || candidate == cached) continue;
        if (CompactReadBar((UIWindowScene *)candidate, bar)) return (UIWindowScene *)candidate;
    }
    return nil;
}
static UIColor *CompactTextColor(UIView *view) {
    if ([view isKindOfClass:UILabel.class]) return ((UILabel *)view).textColor;
    Class cls = NSClassFromString(@"_UIStatusBarStringView");
    SEL selector = NSSelectorFromString(@"textColor");
    if (!cls || ![view isKindOfClass:cls] ||
        CompactReturn(class_getInstanceMethod([view class], selector)) != '@') return nil;
    @try {
        id value = ((id (*)(id, SEL))objc_msgSend)(view, selector);
        return [value isKindOfClass:UIColor.class] ? value : nil;
    } @catch (NSException *exception) { (void)exception; return nil; }
}
static BOOL CompactCapture(UIView *item, UIView *label) {
    UIWindow *w = item.window;
    if (!w || w == Window || w.screen != Screen || label.window != w ||
        !CompactVisible(item) || !CompactVisible(label)) return NO;
    UIView *ancestor = label;
    for (unsigned n = 0; ancestor && ancestor != item && n < 5; ++n) ancestor = ancestor.superview;
    if (ancestor != item) return NO;
    UIWindowScene *sourceScene = w.windowScene;
    if (sourceScene && (sourceScene.interfaceOrientation != UIInterfaceOrientationPortrait ||
        sourceScene.screen != Screen || !CGRectEqualToRect(sourceScene.coordinateSpace.bounds, SceneBounds))) return NO;
    CGRect textBounds = label.bounds;
    if ([label isKindOfClass:UILabel.class]) {
        UILabel *ui = (UILabel *)label;
        CGRect fit = CGRectIntersection(ui.bounds, [ui textRectForBounds:ui.bounds limitedToNumberOfLines:ui.numberOfLines]);
        if (CompactRect(fit)) textBounds = fit;
    }
    CGRect l = [label convertRect:textBounds toCoordinateSpace:Screen.coordinateSpace];
    CGRect i = item == label ? l : [item convertRect:item.bounds toCoordinateSpace:Screen.coordinateSpace];
    if (!CompactRect(i) || !CompactRect(l) ||
        !CGRectContainsRect(CGRectInset(Bar, -.5, -.5), i) ||
        !CGRectContainsRect(CGRectInset(i, -.5, -.5), l) ||
        l.size.width < l.size.height * .8 || i.size.width > ScreenBounds.size.width * .45) return NO;
    CGFloat lineY = fmax(CGRectGetMaxY(Bar) - 4, CGRectGetMaxY(l) + 1);
    CGFloat raisedLineY = NB27CompactRaisedLineY(CGRectGetMinY(Bar), CGRectGetMaxY(Bar),
        CGRectGetMaxY(l), lineY, 2, 6, 3, 2);
    if (!isfinite(raisedLineY)) return NO;
    CGRect line = CGRectMake(CGRectGetMinX(i), raisedLineY, i.size.width, 2);
    if (!CGRectContainsRect(Bar, line)) return NO;
    UIColor *color = [CompactTextColor(label) resolvedColorWithTraitCollection:label.traitCollection];
    if (!color || !color.CGColor) return NO;
    CGFloat alpha = CGColorGetAlpha(color.CGColor);
    if (!isfinite(alpha) || alpha <= 0 || alpha > 1) return NO;
    TimeItem = item; TimeLabel = label; SourceWindow = w;
    SourceBounds = sourceScene ? sourceScene.coordinateSpace.bounds : CGRectZero;
    Line = line; CacheBar = Bar; Ink = [color colorWithAlphaComponent:alpha * .55]; HaveAnchor = YES;
    return YES;
}
static BOOL CompactIsClockLabel(UIView *view);
static BOOL CompactLabels(UIView *v, UIView *item, unsigned depth, NSUInteger *budget) {
    if (!v || depth > 4 || !*budget) return NO;
    --*budget;
    if (v.hidden || v.alpha <= .01) return NO;
    Class nativeString = NSClassFromString(@"_UIStatusBarStringView");
    if (([v isKindOfClass:UILabel.class] || (nativeString && [v isKindOfClass:nativeString])) &&
        CompactIsClockLabel(v) && CompactCapture(item, v)) return YES;
    for (UIView *child in v.subviews) {
        if (!*budget) break;
        if (CompactLabels(child, item, depth + 1, budget)) return YES;
    }
    return NO;
}
static NSString *CompactStringValue(UIView *view) {
    if ([view isKindOfClass:UILabel.class]) {
        UILabel *label = (UILabel *)view;
        return label.text.length ? label.text : label.attributedText.string;
    }
    for (NSString *name in @[@"text", @"string", @"accessibilityLabel"]) {
        SEL selector = NSSelectorFromString(name);
        Method method = class_getInstanceMethod([view class], selector);
        if (CompactReturn(method) != '@') continue;
        @try {
            id value = ((id (*)(id, SEL))objc_msgSend)(view, selector);
            if ([value isKindOfClass:NSString.class]) return value;
            if ([value isKindOfClass:NSAttributedString.class]) return [value string];
        } @catch (NSException *exception) { (void)exception; }
    }
    return nil;
}
static BOOL CompactIsClockLabel(UIView *view) {
    Class nativeString = NSClassFromString(@"_UIStatusBarStringView");
    if (![view isKindOfClass:UILabel.class] && !(nativeString && [view isKindOfClass:nativeString])) return NO;
    // Keep the text fallback inside status-bar views, not other SpringBoard UI.
    BOOL belongsToStatusBar = NO;
    UIView *ancestor = view;
    for (unsigned n = 0; ancestor && n < 18; ++n, ancestor = ancestor.superview) {
        NSString *name = NSStringFromClass(object_getClass(ancestor));
        if ([name hasPrefix:@"_UIStatusBar"] || [name hasPrefix:@"UIStatusBar"] ||
            [name hasPrefix:@"SBStatusBar"] || [name hasPrefix:@"STStatusBar"]) {
            belongsToStatusBar = YES; break;
        }
    }
    if (!belongsToStatusBar) return NO;
    CGRect bounds = [view convertRect:view.bounds toCoordinateSpace:Screen.coordinateSpace];
    if (!CompactRect(bounds) || !CGRectContainsRect(CGRectInset(Bar, -.5, -.5), bounds)) return NO;
    BOOL rtl = view.effectiveUserInterfaceLayoutDirection == UIUserInterfaceLayoutDirectionRightToLeft;
    CGFloat x = CGRectGetMidX(bounds), mid = CGRectGetMidX(ScreenBounds);
    if (rtl ? x < mid : x > mid) return NO;
    NSString *text = CompactStringValue(view);
    if (!text.length || text.length > 256) return NO;
    return NB27ClockText(text.UTF8String, [text lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
}
static BOOL CompactFallbackTree(UIView *v, unsigned depth, NSUInteger *budget) {
    if (!v || depth > 16 || !*budget) return NO;
    --*budget;
    if (v.hidden || v.alpha <= .01) return NO;
    if (CompactIsClockLabel(v) && CompactCapture(v, v)) return YES;
    for (UIView *child in v.subviews) {
        if (!*budget) break;
        if (CompactFallbackTree(child, depth + 1, budget)) return YES;
    }
    return NO;
}
static BOOL CompactTree(UIView *v, Class cls, unsigned depth, NSUInteger *budget) {
    if (!v || depth > 12 || !*budget) return NO;
    --*budget;
    if (v.hidden || v.alpha <= .01) return NO;
    if (cls && [v isKindOfClass:cls] && CompactLabels(v, v, 0, budget)) return YES;
    for (UIView *child in v.subviews) {
        if (!*budget) break;
        if (CompactTree(child, cls, depth + 1, budget)) return YES;
    }
    return NO;
}
static BOOL CompactScan(void) {
    CFTimeInterval now = CACurrentMediaTime();
    if (now - LastScan < 2) return NO;
    LastScan = now;
    Class cls = NSClassFromString(@"_UIStatusBarTimeItemView");
    NSMutableArray<UIWindow *> *windows = [NSMutableArray new];
    unsigned scenes = 0;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if (++scenes > 8 || windows.count >= 24) break;
        if (![s isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *ws = (UIWindowScene *)s;
        if (ws.screen != Screen) continue;
        for (UIWindow *w in ws.windows) {
            if (windows.count >= 24) break;
            if (![windows containsObject:w]) [windows addObject:w];
        }
    }
    /* Legacy SpringBoard windows, still strictly this process. */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    for (UIWindow *w in UIApplication.sharedApplication.windows) {
        if (windows.count >= 24) break;
        if (![windows containsObject:w]) [windows addObject:w];
    }
#pragma clang diagnostic pop
    [windows sortUsingComparator:^NSComparisonResult(UIWindow *a, UIWindow *b) {
        if (a.windowLevel != b.windowLevel)
            return a.windowLevel > b.windowLevel ? NSOrderedAscending : NSOrderedDescending;
        CGFloat ay = CGRectGetMinY(a.frame), by = CGRectGetMinY(b.frame);
        if (ay != by) return ay < by ? NSOrderedAscending : NSOrderedDescending;
        return NSOrderedSame;
    }];
    NSUInteger budget = 2048;
    for (UIWindow *w in windows) {
        if (!budget) break;
        if (w == Window || [w isKindOfClass:NB27CompactWindow.class] || w.screen != Screen) continue;
        if (cls && CompactTree(w, cls, 0, &budget)) return YES;
    }
    /* iOS 17 SpringBoard may expose the time label without the older private
       _UIStatusBarTimeItemView wrapper. Match only an actual HH:mm text view
       geometrically contained in the live status-bar frame, never the banner. */
    budget = 4096;
    for (UIWindow *w in windows) {
        if (!budget) break;
        if (w == Window || [w isKindOfClass:NB27CompactWindow.class] || w.screen != Screen) continue;
        if (CompactFallbackTree(w, 0, &budget)) return YES;
    }
    if (!HaveAnchor) CompactDiagnostic(cls ? @"time-item class found, no visible valid clock label in bounded status windows" :
        @"time-item class absent, no visible valid HH:mm label in bounded status windows");
    return NO;
}
static BOOL CompactContext(UIView *card) {
    if (!CompactAllowed() || UIDevice.currentDevice.userInterfaceIdiom != UIUserInterfaceIdiomPhone) return NO;
    if (!CompactUnlocked()) {
        CompactDiagnostic(@"UI locked or lock state unavailable"); return NO;
    }
    CGRect bar = CGRectZero;
    UIWindowScene *scene = CompactActiveScene(card.window.windowScene ?: Reference.window.windowScene, &bar);
    if (!scene) {
        CompactClearAnchor(); CompactDiagnostic(@"no active portrait status bar"); return NO;
    }
    UIScreen *screen = scene.screen;
    CGRect sb = screen.coordinateSpace.bounds, cb = scene.coordinateSpace.bounds;
    if (Screen != screen || Scene != scene || !CGRectEqualToRect(sb, ScreenBounds) ||
        !CGRectEqualToRect(cb, SceneBounds)) {
        CompactDropWindow(); CompactClearAnchor(); LastScan = -DBL_MAX;
        Screen = screen; Scene = scene; ScreenBounds = sb; SceneBounds = cb;
    }
    Bar = bar;
    if (HaveAnchor && !CGRectEqualToRect(CacheBar, Bar)) CompactClearAnchor();
    UIWindow *source = SourceWindow;
    if (HaveAnchor && source && (source.screen != screen ||
        (source.windowScene && (!CGRectEqualToRect(source.windowScene.coordinateSpace.bounds, SourceBounds) ||
         source.windowScene.interfaceOrientation != UIInterfaceOrientationPortrait)))) CompactClearAnchor();
    if (HaveAnchor && (!TimeItem || !TimeLabel || !source ||
        !CompactCapture(TimeItem, TimeLabel))) CompactClearAnchor();
    if (!HaveAnchor) CompactScan();
    return HaveAnchor;
}
static float CompactFreezeOpacity(void) {
    if (!Stroke) return 0;
    float opacity = Stroke.presentationLayer ? ((CALayer *)Stroke.presentationLayer).opacity : Stroke.opacity;
    [Stroke removeAnimationForKey:CompactOpacityKey];
    [CATransaction begin]; [CATransaction setDisableActions:YES]; Stroke.opacity = opacity; [CATransaction commit];
    return opacity;
}
static void CompactSetOpacity(float opacity, NSTimeInterval duration) {
    if (!Stroke || !Window) return;
    float current = Stroke.presentationLayer ? ((CALayer *)Stroke.presentationLayer).opacity : Stroke.opacity;
    [Stroke removeAnimationForKey:CompactOpacityKey];
    opacity = fminf(1, fmaxf(0, opacity));
    [CATransaction begin]; [CATransaction setDisableActions:YES]; Stroke.opacity = opacity; [CATransaction commit];
    if (duration > 0) {
        CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"opacity"];
        animation.fromValue = @(current); animation.toValue = @(opacity); animation.duration = duration;
        animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
        [Stroke addAnimation:animation forKey:CompactOpacityKey];
    }
}
static BOOL CompactShow(void) {
    if (!Window) {
        Window = [[NB27CompactWindow alloc] initWithWindowScene:Scene];
        Window.frame = SceneBounds; Window.expectedScreen = ScreenBounds; Window.expectedScene = SceneBounds;
        Window.windowLevel = UIWindowLevelStatusBar + 1; Window.backgroundColor = UIColor.clearColor;
        Window.opaque = NO; Window.userInteractionEnabled = NO; Window.accessibilityElementsHidden = YES;
        UIViewController *root = [UIViewController new];
        root.view = [[UIView alloc] initWithFrame:Window.bounds];
        root.view.backgroundColor = UIColor.clearColor; root.view.opaque = NO;
        root.view.userInteractionEnabled = NO; root.view.accessibilityElementsHidden = YES;
        Window.rootViewController = root; Stroke = [CALayer layer]; Stroke.opacity = 0;
        Stroke.cornerRadius = 1; [root.view.layer addSublayer:Stroke];
    }
    CGRect local = [Window.rootViewController.view convertRect:Line fromCoordinateSpace:Screen.coordinateSpace];
    if (!CompactRect(local) || !CGRectContainsRect(Window.bounds, local)) { Window.hidden = YES; return NO; }
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    Stroke.frame = local; Stroke.backgroundColor = Ink.CGColor; [CATransaction commit];
    Window.hidden = NO; /* Never makeKey, never write any other window/root. */
    return YES;
}
static void CompactTimer(void) {
    BOOL need = State.enabled && (State.retained || State.pending || State.preview);
    if (!need) { [Timer invalidate]; Timer = nil; return; }
    if (!Timer) {
        Timer = [NSTimer timerWithTimeInterval:1 target:Watch selector:@selector(tick:) userInfo:nil repeats:YES];
        Timer.tolerance = .2; [NSRunLoop.mainRunLoop addTimer:Timer forMode:NSRunLoopCommonModes];
    }
}
static void CompactRefresh(void) {
    BOOL safe = State.enabled && CompactContext(nil);
    BOOL visible = safe && (State.retained || State.preview);
    if (visible && CompactShow()) {
        if (State.retained && !State.fading && !State.preview && !State.pendingHadRetained) CompactSetOpacity(1, 0);
    } else if (Window) {
        Window.hidden = YES;
    }
    CompactTimer();
}
static void CompactScheduleExpiry(uintptr_t ticket) {
    if (!NB27CompactStateScheduleExpiry(&State, ticket)) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!NB27CompactStateBeginFade(&State, ticket)) return;
        CompactRefresh();
        CompactSetOpacity(0, .30);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(.30 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (NB27CompactStateExpire(&State, ticket)) CompactRefresh();
        });
    });
}
@implementation NB27CompactWatch
- (void)changed:(NSNotification *)note {
    (void)note;
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self changed:nil]; }); return;
    }
    CompactClearAnchor();
    CompactAllowed(); /* Reduce Motion clears, even before the low-frequency tick. */
    CompactTimer();
}
- (void)tick:(NSTimer *)timer { (void)timer; CompactRefresh(); }
@end
static void CompactObserve(void) {
    if (Watch || !CompactSpringBoard()) return;
    Watch = [NB27CompactWatch new];
    // Event-driven hiding complements the low-frequency safety recheck. No
    // lock manager setter, system layer mutation, or private observer hook.
    static int lockToken = -1, displayToken = -1;
    notify_register_dispatch("com.apple.springboard.lockstate", &lockToken, dispatch_get_main_queue(),
        ^(int token) { (void)token; [Watch changed:nil]; });
    notify_register_dispatch("com.apple.iokit.hid.displayStatus", &displayToken, dispatch_get_main_queue(),
        ^(int token) { (void)token; [Watch changed:nil]; });
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    for (NSString *name in @[UIAccessibilityReduceMotionStatusDidChangeNotification,
        UIApplicationWillChangeStatusBarOrientationNotification, UIApplicationDidChangeStatusBarOrientationNotification,
        UIApplicationDidChangeStatusBarFrameNotification, UIScreenModeDidChangeNotification,
        UISceneWillDeactivateNotification, UISceneDidActivateNotification, UISceneDidDisconnectNotification])
        [NSNotificationCenter.defaultCenter addObserver:Watch selector:@selector(changed:) name:name object:nil];
#pragma clang diagnostic pop
}
void NB27CompactSetEnabled(BOOL enabled) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ NB27CompactSetEnabled(enabled); }); return; }
    Requested = enabled; CompactObserve(); CompactRefresh();
}
void NB27CompactNoteEntrance(UIView *card) {
    if (!NSThread.isMainThread || !card) return;
    Reference = card; CompactObserve();
    if (State.retained && !CompactContext(card) && Window) Window.hidden = YES;
}
NB27CompactAnchor NB27CompactPrepareTimeAnchor(UIView *reference) {
    NB27CompactAnchor anchor = {0};
    if (!NSThread.isMainThread) return anchor;
    CompactObserve();
    if (!CompactContext(reference)) return anchor;
    anchor.line = Line; anchor.screenBounds = ScreenBounds; anchor.sceneBounds = SceneBounds;
    anchor.capturedAt = CACurrentMediaTime(); anchor.valid = YES;
    return anchor;
}
BOOL NB27CompactOriginFromAnchor(UIView *card, NB27CompactAnchor anchor, CGPoint *center, CGSize *size) {
    if (!NSThread.isMainThread || !card || !center || !size || !card.superview || !card.window) return NO;
    if (!anchor.valid || !CompactRect(anchor.line) || !CompactAllowed() || !CompactUnlocked()) return NO;
    double age = CACurrentMediaTime() - anchor.capturedAt;
    if (!isfinite(age) || age < 0 || age > 1) return NO;
    UIWindowScene *scene = card.window.windowScene;
    UIScreen *screen = card.window.screen;
    if (!scene) return NO;
    UISceneActivationState activation = scene.activationState;
    if (screen != UIScreen.mainScreen || scene.screen != screen ||
        (activation != UISceneActivationStateForegroundActive && activation != UISceneActivationStateForegroundInactive) ||
        scene.interfaceOrientation != UIInterfaceOrientationPortrait ||
        !CGRectEqualToRect(scene.coordinateSpace.bounds, anchor.sceneBounds) ||
        !CGRectEqualToRect([scene.coordinateSpace convertRect:anchor.sceneBounds toCoordinateSpace:screen.coordinateSpace], anchor.screenBounds) ||
        !CGRectEqualToRect(screen.coordinateSpace.bounds, anchor.screenBounds)) return NO;
    UIView *parent = card.superview;
    if (card.layer.superlayer != parent.layer || !CompactRect(parent.bounds) || !CompactRect(card.bounds)) return NO;
    CGRect r = [parent convertRect:anchor.line fromCoordinateSpace:screen.coordinateSpace];
    CGPoint p = [parent convertPoint:CGPointMake(CGRectGetMidX(anchor.line), CGRectGetMidY(anchor.line))
                fromCoordinateSpace:screen.coordinateSpace];
    if (!CompactRect(r) || !isfinite(p.x) || !isfinite(p.y)) return NO;
    CGPoint back = [parent convertPoint:p toCoordinateSpace:screen.coordinateSpace];
    if (!isfinite(back.x) || !isfinite(back.y) || fabs(back.x - CGRectGetMidX(anchor.line)) > .5 ||
        fabs(back.y - CGRectGetMidY(anchor.line)) > .5) return NO;
    Reference = card; *center = p; *size = r.size; return YES;
}
NSUInteger NB27CompactBeginExit(BOOL supported) {
    if (!NSThread.isMainThread || !CompactAllowed()) return 0;
    CompactObserve();
    NSUInteger ticket = (NSUInteger)NB27CompactStateBegin(&State, supported);
    CompactTimer(); CompactRefresh(); return ticket;
}
void NB27CompactAnimateExit(NSUInteger ticket, double duration) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ NB27CompactAnimateExit(ticket, duration); }); return; }
    if (!ticket || !isfinite(duration) || duration <= 0 || !CompactAllowed()) return;
    float previousOpacity = State.retained ? CompactFreezeOpacity() : 0;
    if (!NB27CompactStateRevealStart(&State, (uintptr_t)ticket) || !CompactContext(nil) || !CompactShow()) return;
    if (!State.pendingHadRetained) {
        [CATransaction begin]; [CATransaction setDisableActions:YES]; Stroke.opacity = 0; [CATransaction commit];
    } else {
        [CATransaction begin]; [CATransaction setDisableActions:YES]; Stroke.opacity = previousOpacity; [CATransaction commit];
    }
    uint64_t generation = (uint64_t)ticket;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * .65 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!State.enabled || (State.pending != generation && State.retainedTicket != generation) || !State.preview) return;
        if (!CompactContext(nil) || !CompactShow()) return;
        CompactSetOpacity(1, duration * .35);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * .35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    if (!NB27CompactStateRevealComplete(&State, (uintptr_t)generation)) return;
    CompactRefresh();
    if (State.retained && State.retainedTicket == generation) CompactScheduleExpiry((uintptr_t)generation);
        });
    });
}
void NB27CompactFinishExit(NSUInteger ticket) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ NB27CompactFinishExit(ticket); }); return; }
    if (!CompactAllowed() || !NB27CompactStateFinish(&State, (uintptr_t)ticket)) return;
    CompactRefresh();
    if (!State.preview) CompactScheduleExpiry((uintptr_t)ticket);
}
void NB27CompactAbortExit(NSUInteger ticket) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ NB27CompactAbortExit(ticket); }); return; }
    if (!CompactAllowed() || !NB27CompactStateAbort(&State, (uintptr_t)ticket)) return;
    CompactRefresh();
    if (State.retained) {
        CompactSetOpacity(1, .15);
        CompactScheduleExpiry((uintptr_t)State.retainedTicket);
    }
    CompactTimer();
}
