#import "Bridge.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <QuartzCore/QuartzCore.h>

static char kNGBindingKey, kNGClockReplayKey;
static NSHashTable<UISwitch *> *gNGBoundSwitches;
static NSHashTable<UISwitch *> *NGBoundSwitches(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{ gNGBoundSwitches = [NSHashTable weakObjectsHashTable]; });
    return gNGBoundSwitches;
}
static BOOL NGIsClock(void) {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.mobiletimer"];
}
#if NG_CLOCK_TRACE
static void NGClockTrace(UISwitch *source, UIView *overlay, NSString *event) {
    if (!NGIsClock()) return;
    NSMutableArray *ancestors = [NSMutableArray array];
    for (UIView *v = overlay.superview; v && ancestors.count < 8; v = v.superview) {
        if (v.layer.animationKeys.count) [ancestors addObject:@{ @"class": NSStringFromClass(v.class), @"keys": v.layer.animationKeys }];
    }
    NSLog(@"[TheseusClock] %@ native=%p overlay=%p on=%d nativeKeys=%@ overlayKeys=%@ ancestors=%@",
          event, source, overlay, source.isOn, source.layer.animationKeys, overlay.layer.animationKeys, ancestors);
}
#else
#define NGClockTrace(source, overlay, event) do {} while (0)
#endif
static void NGWithoutAnimation(void (^changes)(void)) {
    [UIView performWithoutAnimation:^{
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        @try { changes(); } @finally { [CATransaction commit]; }
    }];
}
static void NGScheduleSwitchSyncAfter(UISwitch *source, NSTimeInterval delay);

@interface NGSwitchBinding : NSObject
@property(nonatomic,weak) UISwitch *source;
@property(nonatomic,strong) UIView *overlay;
@property(nonatomic) CGFloat originalAlpha;
@property(nonatomic) BOOL originalAccessibility;
@property(nonatomic) BOOL forwarding;
@property(nonatomic) BOOL modifyingNative;
@property(nonatomic) BOOL syncScheduled;
@property(nonatomic) BOOL refreshing;
@property(nonatomic) BOOL enabledKnown;
@property(nonatomic) BOOL mirroredEnabled;
@property(nonatomic) NSUInteger clockResetVersion;
- (void)commit:(BOOL)value;
@end

// A replay ticket belongs to a table + logical index path, never to a
// reusable cell. The real native valueChanged is still delivered immediately.
@interface NGClockReplayTicket : NSObject
@property(nonatomic,copy) NSIndexPath *path;
@property(nonatomic) BOOL value;
@property(nonatomic) NSInteger rowCount;
@property(nonatomic) NSInteger sectionCount;
@property(nonatomic) CFTimeInterval expires;
@property(nonatomic,weak) NGSwitchBinding *lastBinding;
@property(nonatomic) NSUInteger lastResetVersion;
@property(nonatomic) BOOL scheduled;
@end
@implementation NGClockReplayTicket
@end

static UITableView *NGClockTableForSource(UISwitch *source, UITableViewCell **outCell) {
    UITableViewCell *cell = nil;
    for (UIView *v = source.superview; v; v = v.superview) {
        if (!cell && [v isKindOfClass:UITableViewCell.class]) cell = (UITableViewCell *)v;
        if (cell && [v isKindOfClass:UITableView.class]) {
            if (outCell) *outCell = cell;
            return (UITableView *)v;
        }
    }
    return nil;
}

static NGSwitchBinding *NGClockFindBinding(UIView *view) {
    if ([view isKindOfClass:UISwitch.class]) return objc_getAssociatedObject(view, &kNGBindingKey);
    for (UIView *child in view.subviews) {
        NGSwitchBinding *binding = NGClockFindBinding(child);
        if (binding) return binding;
    }
    return nil;
}

// Called after a cell has been configured and reset. UIKit may not have
// installed its new index path until the current layout transaction finishes.
void NGClockScheduleReplay(UITableView *table) {
    if (!NGIsClock() || !table || !NSThread.isMainThread) return;
    NGClockReplayTicket *ticket = objc_getAssociatedObject(table, &kNGClockReplayKey);
    if (!ticket) return;
    if (CACurrentMediaTime() > ticket.expires) {
        objc_setAssociatedObject(table, &kNGClockReplayKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    if (ticket.scheduled) return;
    ticket.scheduled = YES;
    __weak UITableView *weakTable = table;
    dispatch_async(dispatch_get_main_queue(), ^{
        UITableView *current = weakTable;
        if (!current || objc_getAssociatedObject(current, &kNGClockReplayKey) != ticket) return;
        ticket.scheduled = NO;
        if (CACurrentMediaTime() > ticket.expires || !current.window ||
            current.numberOfSections != ticket.sectionCount ||
            ticket.path.section >= current.numberOfSections ||
            [current numberOfRowsInSection:ticket.path.section] != ticket.rowCount ||
            ticket.path.row >= ticket.rowCount || current.editing) return;
        UITableViewCell *cell = [current cellForRowAtIndexPath:ticket.path];
        if (!cell.window || ![cell isKindOfClass:NSClassFromString(@"MTAAlarmTableViewCell")] ||
            ![current.indexPathsForVisibleRows containsObject:ticket.path] ||
            ![[current indexPathForCell:cell] isEqual:ticket.path]) return;
        NGSwitchBinding *binding = NGClockFindBinding(cell);
        UISwitch *source = binding.source;
        id<NGSwitchComponent> component = (id)binding.overlay;
        if (!binding || !source.window || !source.enabled || !source.userInteractionEnabled ||
            binding.overlay.hidden || !binding.overlay.window ||
            source.isOn != ticket.value || [component isOn] != ticket.value ||
            [component clockTouchActive]) return;
        // If the original animation survived, do nothing. Replay only after
        // an actual reset, or after UIKit installs a different cell at this row.
        if (ticket.lastBinding == binding && ticket.lastResetVersion == binding.clockResetVersion) return;
        ticket.lastBinding = binding;
        ticket.lastResetVersion = binding.clockResetVersion;
        NGClockTrace(source, binding.overlay, @"rowVisualReplay");
        [component replayClockTransition:ticket.value];
    });
}

static UITableView *NGClockBeginReplay(NGSwitchBinding *binding, BOOL value) {
    UITableViewCell *cell = nil;
    UITableView *table = NGClockTableForSource(binding.source, &cell);
    if (!table || ![cell isKindOfClass:NSClassFromString(@"MTAAlarmTableViewCell")]) return nil;
    // Supersede an older tap before validating the new ticket.
    objc_setAssociatedObject(table, &kNGClockReplayKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSIndexPath *path = [table indexPathForCell:cell];
    if (!path || table.editing || !table.window || path.section >= table.numberOfSections ||
        ![table.indexPathsForVisibleRows containsObject:path]) return nil;
    NGClockReplayTicket *ticket = [NGClockReplayTicket new];
    ticket.path = path;
    ticket.value = value;
    ticket.sectionCount = table.numberOfSections;
    ticket.rowCount = [table numberOfRowsInSection:path.section];
    ticket.expires = CACurrentMediaTime() + 0.65;
    ticket.lastBinding = binding;
    ticket.lastResetVersion = binding.clockResetVersion;
    objc_setAssociatedObject(table, &kNGClockReplayKey, ticket, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return table;
}

@implementation NGSwitchBinding
- (void)dealloc { [_overlay removeFromSuperview]; }
- (void)commit:(BOOL)value {
    UISwitch *source = self.source;
    if (!source || !source.enabled || !source.userInteractionEnabled || self.forwarding || self.overlay.hidden) return;
    if (source.isOn == value) return;
    NGClockTrace(source, self.overlay, @"userCommit");
    void (^commitNativeValue)(void) = ^{
        self.forwarding = YES;
        @try { [source setOn:value animated:NO]; }
        @finally { self.forwarding = NO; }
        [source sendActionsForControlEvents:UIControlEventValueChanged];
    };
    if (NGIsClock()) {
        UITableView *replayTable = NGClockBeginReplay(self, value);
        // Both directions can trigger host list updates during rapid tapping.
        BOOL animationsWereEnabled = [UIView areAnimationsEnabled];
        @try {
            [UIView setAnimationsEnabled:NO];
            NGWithoutAnimation(commitNativeValue);
        } @finally { [UIView setAnimationsEnabled:animationsWereEnabled]; }
        NGClockTrace(source, self.overlay, @"actionReturned");
        NGClockScheduleReplay(replayTable);
    } else {
        commitNativeValue();
    }
    // Reconcile any synchronous rejection or reconfiguration by the host.
    // Clock sync is immediate; other apps retain coalesced asynchronous sync.
    NGScheduleSwitchSync(source);
}
@end

static void NGApplySwitchState(UISwitch *source, NGSwitchBinding *binding) {
    if (binding.forwarding) return;
    id<NGSwitchComponent> component = (id)binding.overlay;
    NGWithoutAnimation(^{
        // UIKit's animated flag describes the native control, not a user gesture
        // on our overlay. A same-value refresh must be a strict no-op.
        BOOL displayed = [(id)component isOn];
        BOOL native = source.isOn;
        if (displayed != native) {
            NGClockTrace(source, binding.overlay, @"nativeValueChanged");
            [component setOn:native animated:NO];
            if (NGIsClock()) {
                binding.clockResetVersion++;
                NGClockScheduleReplay(NGClockTableForSource(source, NULL));
            }
        }
        BOOL enabled = source.enabled;
        if (!binding.enabledKnown || binding.mirroredEnabled != enabled) {
            SEL selector = NSSelectorFromString(@"setControlEnabled:");
            if ([binding.overlay respondsToSelector:selector])
                ((void(*)(id,SEL,BOOL))objc_msgSend)(binding.overlay,selector,enabled);
            binding.enabledKnown = YES;
            binding.mirroredEnabled = enabled;
        }
        NSString *label = source.accessibilityLabel;
        if (binding.overlay.accessibilityLabel != label && ![binding.overlay.accessibilityLabel isEqualToString:label])
            binding.overlay.accessibilityLabel = label;
        if (binding.overlay.alpha != binding.originalAlpha) binding.overlay.alpha = binding.originalAlpha;
        if (NGIsClock()) {
            // The sibling overlay owns its visuals; never let a native opacity
            // transition briefly reveal the underlying switch during a list update.
            if (source.layer.opacity != 0) source.layer.opacity = 0;
            if ([source.layer animationForKey:@"opacity"]) [source.layer removeAnimationForKey:@"opacity"];
        }
    });
}

static void NGScheduleSwitchSyncAfter(UISwitch *source, NSTimeInterval delay) {
    if (!NSThread.isMainThread) return;
    NGSwitchBinding *binding = objc_getAssociatedObject(source, &kNGBindingKey);
    if (!binding || binding.syncScheduled) return;
    binding.syncScheduled = YES;
    __weak UISwitch *weakSource = source;
    __weak NGSwitchBinding *weakBinding = binding;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UISwitch *current = weakSource;
        NGSwitchBinding *expected = weakBinding;
        if (!current || !expected || objc_getAssociatedObject(current, &kNGBindingKey) != expected) return;
        expected.syncScheduled = NO;
        if (expected.forwarding) { NGScheduleSwitchSync(current); return; }
        NGApplySwitchState(current, expected);
    });
}

void NGScheduleSwitchSync(UISwitch *source) {
    if (!NSThread.isMainThread) return;
    if (NGIsClock()) {
        // Clock reconfigures visible cells during the same layout transaction.
        // The native value must be reflected before the cell becomes visible.
        NGSwitchBinding *binding = objc_getAssociatedObject(source, &kNGBindingKey);
        if (binding && !binding.forwarding) NGApplySwitchState(source, binding);
        return;
    }
    NGScheduleSwitchSyncAfter(source, 0);
}

BOOL NGClockHasSwitchOverlay(UISwitch *source) {
    if (!NGIsClock()) return NO;
    NGSwitchBinding *binding = objc_getAssociatedObject(source,&kNGBindingKey);
    return binding.overlay.superview != nil;
}

void NGRemoveSwitch(UISwitch *source) {
    [NGBoundSwitches() removeObject:source];
    NGSwitchBinding *binding = objc_getAssociatedObject(source,&kNGBindingKey);
    if (!binding) return;
    NGWithoutAnimation(^{
        [binding.overlay removeFromSuperview];
        objc_setAssociatedObject(source,&kNGBindingKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        source.alpha = binding.originalAlpha;
        source.isAccessibilityElement = binding.originalAccessibility;
    });
}

void NGRemoveAllSwitches(void) {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ NGRemoveAllSwitches(); }); return; }
    for (UISwitch *source in NGBoundSwitches().allObjects) NGRemoveSwitch(source);
}

// UIKit can move a view without calling its layoutSubviews (for example,
// center-only changes in a reusable list). Keep the sibling's model geometry
// in sync without touching value, gesture, replay or renderer state.
static void NGApplySwitchGeometry(UISwitch *source, NGSwitchBinding *binding, UIView *parent) {
    CGSize size = CGSizeMake(63,28);
    CGPoint center = [source convertPoint:CGPointMake(CGRectGetMidX(source.bounds),CGRectGetMidY(source.bounds)) toView:parent];
    // convertPoint already includes the affine translation. The sibling will
    // apply that same translation through its transform; do not count it twice.
    // Keep Clock's proven geometry path exactly as before.
    if (!NGIsClock()) {
        center.x -= source.transform.tx;
        center.y -= source.transform.ty;
    }
    CGRect bounds = (CGRect){CGPointZero,size};
    if (!CGRectEqualToRect(binding.overlay.bounds, bounds)) binding.overlay.bounds = bounds;
    if (!CGPointEqualToPoint(binding.overlay.center, center)) binding.overlay.center = center;
    if (!CGAffineTransformEqualToTransform(binding.overlay.transform, source.transform)) binding.overlay.transform = source.transform;
    BOOL hidden = source.hidden || CGRectIsEmpty(source.bounds);
    if (binding.overlay.hidden != hidden) binding.overlay.hidden = hidden;
}

void NGSyncSwitchGeometry(UISwitch *source) {
    // Clock already has transaction-specific layout and replay handling.
    // Leave that proven path unchanged in this targeted fix.
    if (!NSThread.isMainThread || NGIsClock() || !NGSwitchFeatureEnabled()) return;
    NGSwitchBinding *binding = objc_getAssociatedObject(source, &kNGBindingKey);
    UIView *parent = source.superview;
    if (!binding || binding.refreshing || !parent || !source.window || binding.overlay.superview != parent) return;
    binding.refreshing = YES;
    @try {
        NGWithoutAnimation(^{ NGApplySwitchGeometry(source, binding, parent); });
    } @finally { binding.refreshing = NO; }
}

void NGRefreshSwitch(UISwitch *source) {
    if (!NSThread.isMainThread || ![source isKindOfClass:UISwitch.class]) return;
    if (!NGSwitchFeatureEnabled()) { NGRemoveSwitch(source); return; }
    if (!source.superview || !source.window || CGRectIsEmpty(source.bounds)) { NGRemoveSwitch(source); return; }
    NGSwitchBinding *binding = objc_getAssociatedObject(source,&kNGBindingKey);
    BOOL newlyBound = !binding;
    if (!binding) {
        if (!NGBundleResources()) return; // Do not hide a working native control if resources are missing.
        binding = [NGSwitchBinding new]; binding.source = source;
        binding.originalAlpha = source.alpha; binding.originalAccessibility = source.isAccessibilityElement;
        Class component = NSClassFromString(@"NGTheseusSwitch"); if (!component) return;
        binding.overlay = [[component alloc] initWithFrame:CGRectMake(0,0,63,28)];
        __weak NGSwitchBinding *weak = binding;
        [(id<NGSwitchComponent>)binding.overlay setOnChanged:^(BOOL value) { [weak commit:value]; }];
        binding.overlay.accessibilityIdentifier = @"NGSwitchOverlay";
        binding.overlay.clipsToBounds = NO;
        objc_setAssociatedObject(source,&kNGBindingKey,binding,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [NGBoundSwitches() addObject:source];
    }
    if (binding.refreshing) return;
    binding.refreshing = YES;
    UIView *parent = source.superview;
    BOOL parentChanged = binding.overlay.superview != parent;
    if (parentChanged && NGIsClock()) {
        binding.clockResetVersion++;
        [(id<NGSwitchComponent>)binding.overlay resetForClockReuse:source.isOn];
    }
    @try {
        NGWithoutAnimation(^{
        if (binding.overlay.superview != parent) { [binding.overlay removeFromSuperview]; [parent insertSubview:binding.overlay aboveSubview:source]; }
        // Preserve the original Theseus 63 x 28 track and Layout defaults.
        NGApplySwitchGeometry(source, binding, parent);
        if (binding.overlay.userInteractionEnabled != source.userInteractionEnabled) binding.overlay.userInteractionEnabled = source.userInteractionEnabled;
        binding.modifyingNative = YES;
        if (source.alpha != 0) source.alpha = 0;
        if (source.isAccessibilityElement) source.isAccessibilityElement = NO;
        binding.modifyingNative = NO;
        if (NGIsClock()) {
            if (source.layer.opacity != 0) source.layer.opacity = 0;
            if ([source.layer animationForKey:@"opacity"]) [source.layer removeAnimationForKey:@"opacity"];
            NGClockTrace(source, binding.overlay, @"layout");
        }
        });
    } @finally { binding.refreshing = NO; binding.modifyingNative = NO; }
    if (newlyBound || (NGIsClock() && parentChanged)) NGApplySwitchState(source, binding);
    else NGScheduleSwitchSync(source);
}

BOOL NGHandleSwitchAlpha(UISwitch *source, CGFloat alpha) {
    if (!NGSwitchFeatureEnabled()) return NO;
    NGSwitchBinding *binding = objc_getAssociatedObject(source,&kNGBindingKey);
    if (!binding || binding.modifyingNative) return NO;
    binding.originalAlpha = alpha;
    NGScheduleSwitchSync(source);
    return YES;
}

// UITableView may reuse the very same UISwitch, superview and binding for
// another alarm. Reset at cell lifecycle boundaries even if isOn is unchanged.
void NGClockResetAlarmCell(UIView *view) {
    if (!NGIsClock() || !NSThread.isMainThread || !view) return;
    if ([view isKindOfClass:UISwitch.class]) {
        UISwitch *source = (UISwitch *)view;
        NGSwitchBinding *binding = objc_getAssociatedObject(source, &kNGBindingKey);
        if (binding) {
            binding.clockResetVersion++;
            NGWithoutAnimation(^{
                [(id<NGSwitchComponent>)binding.overlay resetForClockReuse:source.isOn];
                NGClockTrace(source, binding.overlay, @"cellReuseReset");
            });
        }
        return;
    }
    for (UIView *child in [view.subviews copy]) NGClockResetAlarmCell(child);
}
