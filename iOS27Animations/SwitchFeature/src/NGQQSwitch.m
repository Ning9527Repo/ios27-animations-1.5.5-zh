#import "Bridge.h"
#import <UIKit/UIGestureRecognizerSubclass.h>
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

BOOL NGIsQQSwitchHost(void) {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.tencent.mqq"];
}

@protocol NGQQVisual <NSObject>
@property(nonatomic,copy) BOOL (^ownerIsCurrent)(void);
- (void)setNativeValue:(BOOL)value;
- (void)beginNativeTouch:(CGPoint)point;
- (void)moveNativeTouch:(CGPoint)point;
- (void)endNativeTouch:(BOOL)value cancelled:(BOOL)cancelled;
- (void)cancelNativeVisual;
@end

@interface NGQQSavedLayer : NSObject
@property(nonatomic,weak) CALayer *layer;
@property(nonatomic,strong) CALayer *originalMask;
@property(nonatomic,strong) CALayer *mask;
@end
@implementation NGQQSavedLayer @end

@class NGQQBinding;
// A passive observer never recognizes/prevents/cancels a native gesture.
@interface NGQQTouchObserver : UIGestureRecognizer
@property(nonatomic,weak) NGQQBinding *binding;
@end
@interface NGQQBinding : NSObject
@property(nonatomic,weak) UISwitch *source;
@property(nonatomic,strong) UIView<NGQQVisual> *visual;
@property(nonatomic,strong) NGQQTouchObserver *observer;
@property(nonatomic,strong) NSMutableArray<NGQQSavedLayer *> *layers;
@property(nonatomic,weak) UIView *parent;
@property(nonatomic,weak) UIView *cell;
@property(nonatomic,weak) UIView *list;
@property(nonatomic,copy) NSIndexPath *path;
@property(nonatomic) BOOL clips;
@property(nonatomic) BOOL refreshing;
@property(nonatomic) BOOL touching;
@property(nonatomic) BOOL ending;
@property(nonatomic) NSUInteger generation;
- (BOOL)ownerIsCurrent;
- (void)begin:(CGPoint)point;
- (void)move:(CGPoint)point;
- (void)finish:(BOOL)cancelled;
- (void)valueChanged:(UISwitch *)source;
@end
static char kNGQQBinding;
static NSHashTable<UISwitch *> *NGQQSources(void) {
    static NSHashTable *sources; static dispatch_once_t once;
    dispatch_once(&once, ^{ sources = [NSHashTable weakObjectsHashTable]; });
    return sources;
}
static void NGQQIdentity(UISwitch *source, UIView **cellOut, UIView **listOut, NSIndexPath **pathOut) {
    UIView *cell = nil, *list = nil; NSIndexPath *path = nil;
    for (UIView *view = source.superview; view; view = view.superview) {
        if (!cell && ([view isKindOfClass:UITableViewCell.class] || [view isKindOfClass:UICollectionViewCell.class])) cell = view;
        if ([view isKindOfClass:UITableView.class] && [cell isKindOfClass:UITableViewCell.class]) {
            list = view; path = [(UITableView *)view indexPathForCell:(id)cell]; break;
        }
        if ([view isKindOfClass:UICollectionView.class] && [cell isKindOfClass:UICollectionViewCell.class]) {
            list = view; path = [(UICollectionView *)view indexPathForCell:(id)cell]; break;
        }
    }
    if (cellOut) *cellOut = cell; if (listOut) *listOut = list; if (pathOut) *pathOut = path;
}
static BOOL NGQQVisible(UISwitch *source) {
    if (!source.window || !source.enabled || !source.userInteractionEnabled) return NO;
    for (UIView *view = source; view; view = view.superview)
        if (view.hidden || view.alpha <= 0.01) return NO;
    return YES;
}
static void NGQQSuppressNative(NGQQBinding *binding) {
    UISwitch *source = binding.source;
    for (NGQQSavedLayer *saved in [binding.layers copy]) {
        if (!saved.layer || saved.layer.superlayer != source.layer) {
            if (saved.layer.mask == saved.mask) saved.layer.mask = saved.originalMask;
            [binding.layers removeObject:saved];
        }
    }
    for (CALayer *layer in [source.layer.sublayers copy]) {
        if (layer == binding.visual.layer) continue;
        NGQQSavedLayer *saved = nil;
        for (NGQQSavedLayer *item in binding.layers) if (item.layer == layer) { saved = item; break; }
        if (!saved) {
            saved = [NGQQSavedLayer new]; saved.layer = layer; saved.mask = [CALayer layer];
            [binding.layers addObject:saved];
        }
        if (layer.mask != saved.mask) { saved.originalMask = layer.mask; layer.mask = saved.mask; }
    }
}
@implementation NGQQBinding
- (BOOL)ownerIsCurrent {
    UISwitch *source = self.source;
    if (!source || objc_getAssociatedObject(source, &kNGQQBinding) != self ||
        self.visual.superview != source || self.parent != source.superview || !NGQQVisible(source)) return NO;
    UIView *cell = nil, *list = nil; NSIndexPath *path = nil;
    NGQQIdentity(source, &cell, &list, &path);
    return cell == self.cell && list == self.list && (path == self.path || [path isEqual:self.path]);
}
- (void)begin:(CGPoint)point {
    if (![self ownerIsCurrent]) return;
    // One finger interaction can animate only its native owner.
    for (UISwitch *other in NGQQSources().allObjects) {
        NGQQBinding *binding = objc_getAssociatedObject(other, &kNGQQBinding);
        if (binding != self) {
            binding.generation++; binding.touching = NO; binding.ending = NO;
            [binding.visual cancelNativeVisual];
            [binding.visual setNativeValue:other.isOn];
        }
    }
    self.touching = YES; self.ending = NO; self.generation++;
    [self.visual setNativeValue:self.source.isOn];
    [self.visual beginNativeTouch:[self.source convertPoint:point toView:self.visual]];
}
- (void)move:(CGPoint)point {
    if (!self.touching || ![self ownerIsCurrent]) return;
    [self.visual moveNativeTouch:[self.source convertPoint:point toView:self.visual]];
}
- (void)finish:(BOOL)cancelled {
    if (!self.touching) return;
    self.touching = NO; self.ending = YES;
    NSUInteger generation = self.generation;
    // Native UISwitch and QQ callbacks finish first. Never invert/set/send a value.
    __weak NGQQBinding *weak = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        NGQQBinding *binding = weak;
        if (!binding || binding.generation != generation) return;
        binding.ending = NO;
        if (![binding ownerIsCurrent]) { [binding.visual cancelNativeVisual]; return; }
        [binding.visual endNativeTouch:binding.source.isOn cancelled:cancelled];
    });
}
- (void)valueChanged:(UISwitch *)source {
    if (source != self.source || ![self ownerIsCurrent]) return;
    if (!self.touching && !self.ending) [self.visual setNativeValue:source.isOn];
}
- (void)dealloc { [_visual removeFromSuperview]; }
@end

@implementation NGQQTouchObserver
- (BOOL)canPreventGestureRecognizer:(__unused UIGestureRecognizer *)other { return NO; }
- (BOOL)canBePreventedByGestureRecognizer:(__unused UIGestureRecognizer *)other { return NO; }
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(__unused UIEvent *)event {
    if (touches.count != 1) { [self.binding finish:YES]; self.state = UIGestureRecognizerStateFailed; return; }
    [self.binding begin:[touches.anyObject locationInView:self.view]];
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(__unused UIEvent *)event {
    [self.binding move:[touches.anyObject locationInView:self.view]];
}
- (void)touchesEnded:(__unused NSSet<UITouch *> *)touches withEvent:(__unused UIEvent *)event {
    [self.binding finish:NO]; self.state = UIGestureRecognizerStateFailed;
}
- (void)touchesCancelled:(__unused NSSet<UITouch *> *)touches withEvent:(__unused UIEvent *)event {
    [self.binding finish:YES]; self.state = UIGestureRecognizerStateFailed;
}
@end

void NGQQRemoveSwitch(UISwitch *source) {
    NGQQBinding *binding = objc_getAssociatedObject(source, &kNGQQBinding);
    if (!binding || binding.refreshing) return;
    binding.refreshing = YES; binding.generation++; binding.touching = NO; binding.ending = NO;
    [binding.visual cancelNativeVisual];
    [source removeTarget:binding action:@selector(valueChanged:) forControlEvents:UIControlEventValueChanged];
    [source removeGestureRecognizer:binding.observer];
    [binding.visual removeFromSuperview];
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    for (NGQQSavedLayer *saved in binding.layers)
        if (saved.layer.mask == saved.mask) saved.layer.mask = saved.originalMask;
    if (!source.clipsToBounds) source.clipsToBounds = binding.clips;
    [CATransaction commit];
    [NGQQSources() removeObject:source];
    objc_setAssociatedObject(source, &kNGQQBinding, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
void NGQQRemoveAllSwitches(void) {
    for (UISwitch *source in NGQQSources().allObjects) NGQQRemoveSwitch(source);
}
void NGQQRefreshSwitch(UISwitch *source) {
    if (!NGIsQQSwitchHost() || !NSThread.isMainThread) return;
    if (!NGSwitchFeatureEnabled() || !source.superview || !source.window || CGRectIsEmpty(source.bounds)) {
        NGQQRemoveSwitch(source); return;
    }
    NGQQBinding *binding = objc_getAssociatedObject(source, &kNGQQBinding);
    if (binding.refreshing) return;
    if (!binding) {
        if (!NGBundleResources()) return;
        Class cls = NSClassFromString(@"NGQQTheseusSwitch"); if (!cls) return;
        binding = [NGQQBinding new]; binding.source = source;
        binding.clips = source.clipsToBounds; binding.layers = [NSMutableArray array];
        binding.visual = [[cls alloc] initWithFrame:CGRectMake(0,0,63,28)];
        if (!binding.visual) return;
        binding.visual.userInteractionEnabled = NO;
        binding.visual.accessibilityElementsHidden = YES;
        __weak NGQQBinding *weak = binding;
        binding.visual.ownerIsCurrent = ^BOOL { return [weak ownerIsCurrent]; };
        binding.observer = [[NGQQTouchObserver alloc] initWithTarget:nil action:NULL];
        binding.observer.binding = binding;
        binding.observer.cancelsTouchesInView = NO;
        binding.observer.delaysTouchesBegan = NO; binding.observer.delaysTouchesEnded = NO;
        objc_setAssociatedObject(source, &kNGQQBinding, binding, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [NGQQSources() addObject:source];
        [source addGestureRecognizer:binding.observer];
        [source addTarget:binding action:@selector(valueChanged:) forControlEvents:UIControlEventValueChanged];
    }
    UIView *cell = nil, *list = nil; NSIndexPath *path = nil;
    NGQQIdentity(source, &cell, &list, &path);
    BOOL identityChanged = binding.parent != source.superview || binding.cell != cell || binding.list != list ||
                          !(path == binding.path || [path isEqual:binding.path]);
    if (identityChanged) {
        binding.generation++; binding.touching = NO; binding.ending = NO;
        [binding.visual cancelNativeVisual];
        binding.parent = source.superview; binding.cell = cell; binding.list = list; binding.path = path;
    }
    binding.refreshing = YES;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    @try {
        if (binding.visual.superview != source) [source addSubview:binding.visual];
        [source bringSubviewToFront:binding.visual];
        source.clipsToBounds = NO;
        binding.visual.transform = CGAffineTransformIdentity;
        binding.visual.bounds = CGRectMake(0,0,63,28);
        binding.visual.center = CGPointMake(CGRectGetMidX(source.bounds),CGRectGetMidY(source.bounds));
        binding.visual.hidden = source.hidden || CGRectIsEmpty(source.bounds);
        NGQQSuppressNative(binding);
    } @finally { [CATransaction commit]; binding.refreshing = NO; }
    if (!NGQQVisible(source)) {
        binding.generation++; binding.touching = NO; binding.ending = NO;
        [binding.visual cancelNativeVisual];
    }
    if (!binding.touching && !binding.ending) [binding.visual setNativeValue:source.isOn];
}
void NGQQSyncSwitch(UISwitch *source) {
    if (!NSThread.isMainThread) return;
    NGQQBinding *binding = objc_getAssociatedObject(source, &kNGQQBinding);
    if (binding.refreshing) return;
    NGQQRefreshSwitch(source);
}
