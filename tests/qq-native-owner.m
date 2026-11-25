#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dispatch/dispatch.h>

// macOS host substitutes only. Real UIKit and physical touches are not tested here.
@interface UIView : NSObject
@property(nonatomic,strong) CALayer *layer;
@property(nonatomic,weak) UIView *superview;
@property(nonatomic,strong) id window;
@property(nonatomic,strong) NSMutableArray<UIView *> *children;
@property(nonatomic) BOOL hidden, userInteractionEnabled, clipsToBounds, accessibilityElementsHidden;
@property(nonatomic) CGFloat alpha;
@property(nonatomic) CGRect bounds;
@property(nonatomic) CGPoint center;
@property(nonatomic) CGAffineTransform transform;
- (instancetype)initWithFrame:(CGRect)frame;
- (CGPoint)convertPoint:(CGPoint)point toView:(UIView *)view;
- (void)addSubview:(UIView *)view;
- (void)bringSubviewToFront:(UIView *)view;
- (void)removeFromSuperview;
- (void)addGestureRecognizer:(id)gesture;
- (void)removeGestureRecognizer:(id)gesture;
@end
@implementation UIView
- (instancetype)init { if ((self=[super init])) { _layer=[CALayer layer]; _alpha=1; _userInteractionEnabled=YES; _children=[NSMutableArray array]; _transform=CGAffineTransformIdentity; } return self; }
- (instancetype)initWithFrame:(CGRect)frame { if ((self=[self init])) _bounds=(CGRect){CGPointZero,frame.size}; return self; }
- (CGPoint)convertPoint:(CGPoint)point toView:(UIView *)view { (void)view; return point; }
- (void)addSubview:(UIView *)view { [view removeFromSuperview]; [_children addObject:view]; view.superview=self; [self.layer addSublayer:view.layer]; }
- (void)bringSubviewToFront:(UIView *)view { [_children removeObjectIdenticalTo:view]; [_children addObject:view]; }
- (void)removeFromSuperview { [self.superview.children removeObjectIdenticalTo:self]; self.superview=nil; [self.layer removeFromSuperlayer]; }
- (void)addGestureRecognizer:(id)gesture { (void)gesture; }
- (void)removeGestureRecognizer:(id)gesture { (void)gesture; }
@end
@interface UITableViewCell : UIView @end
@implementation UITableViewCell @end
@interface UICollectionViewCell : UIView @end
@implementation UICollectionViewCell @end
@interface UITableView : UIView
@property(nonatomic,strong) NSIndexPath *fixturePath;
- (NSIndexPath *)indexPathForCell:(UITableViewCell *)cell;
@end
@implementation UITableView
- (NSIndexPath *)indexPathForCell:(UITableViewCell *)cell { (void)cell; return self.fixturePath; }
@end
@interface UICollectionView : UIView
- (NSIndexPath *)indexPathForCell:(UICollectionViewCell *)cell;
@end
@implementation UICollectionView
- (NSIndexPath *)indexPathForCell:(UICollectionViewCell *)cell { (void)cell; return nil; }
@end
@interface UIGestureRecognizer : NSObject
@property(nonatomic) BOOL cancelsTouchesInView, delaysTouchesBegan, delaysTouchesEnded;
- (instancetype)initWithTarget:(id)target action:(SEL)action;
@end
@implementation UIGestureRecognizer
- (instancetype)initWithTarget:(id)target action:(SEL)action { (void)target; (void)action; return [super init]; }
@end
@interface UISwitch : UIView
@property(nonatomic,getter=isOn) BOOL on;
@property(nonatomic,getter=isEnabled) BOOL enabled;
@property(nonatomic) NSUInteger nativeEvents;
@property(nonatomic,weak) id eventTarget;
@property(nonatomic) SEL eventSelector;
- (void)addTarget:(id)target action:(SEL)action forControlEvents:(NSUInteger)events;
- (void)removeTarget:(id)target action:(SEL)action forControlEvents:(NSUInteger)events;
- (void)simulateNativeValue:(BOOL)value;
@end
@implementation UISwitch
- (instancetype)init { if ((self=[super init])) { _enabled=YES; self.bounds=CGRectMake(5,8,51,31); self.window=[NSObject new]; self.clipsToBounds=YES; } return self; }
- (void)addTarget:(id)target action:(SEL)action forControlEvents:(NSUInteger)events { (void)events; self.eventTarget=target; self.eventSelector=action; }
- (void)removeTarget:(id)target action:(SEL)action forControlEvents:(NSUInteger)events { (void)action; (void)events; if (self.eventTarget==target) self.eventTarget=nil; }
- (void)simulateNativeValue:(BOOL)value { self.on=value; self.nativeEvents++; if(self.eventTarget) ((void(*)(id,SEL,id))objc_msgSend)(self.eventTarget,self.eventSelector,self); }
@end
static const NSUInteger UIControlEventValueChanged=1;
static BOOL featureEnabled=YES;
static BOOL NGSwitchFeatureEnabled(void) { return featureEnabled; }
static NSBundle *NGBundleResources(void) { return NSBundle.mainBundle; }
/* PRODUCTION_QQ */

@interface NGQQTheseusSwitch : UIView <NGQQVisual>
@property(nonatomic,copy) BOOL (^ownerIsCurrent)(void);
@property(nonatomic) BOOL displayed;
@property(nonatomic) NSUInteger begins, moves, ends, cancels;
@end
@implementation NGQQTheseusSwitch
- (void)setNativeValue:(BOOL)value { self.displayed=value; }
- (void)beginNativeTouch:(CGPoint)point { (void)point; self.begins++; }
- (void)moveNativeTouch:(CGPoint)point { (void)point; self.moves++; }
- (void)endNativeTouch:(BOOL)value cancelled:(BOOL)cancelled { (void)cancelled; self.displayed=value; self.ends++; }
- (void)cancelNativeVisual { self.cancels++; }
@end
static NSUInteger checks;
#define REQUIRE(x) do { checks++; if(!(x)){ NSLog(@"FAIL line %d: %s",__LINE__,#x);abort();} }while(0)
static NGQQTheseusSwitch *visual(NGQQBinding *binding) { return (id)binding.visual; }
static void pump(void) {
    __block BOOL drained=NO;
    dispatch_async(dispatch_get_main_queue(), ^{ drained=YES; });
    NSDate *limit=[NSDate dateWithTimeIntervalSinceNow:1.0];
    while (!drained && limit.timeIntervalSinceNow>0) CFRunLoopRunInMode(kCFRunLoopDefaultMode,0.005,false);
    REQUIRE(drained);
}
int main(void) { @autoreleasepool {
    UITableView *table=[UITableView new]; table.fixturePath=[NSIndexPath indexPathWithIndex:3];
    UITableViewCell *row=[UITableViewCell new]; [table addSubview:row];
    NSMutableArray<UISwitch *> *sources=[NSMutableArray array];
    NSMutableArray<NGQQBinding *> *bindings=[NSMutableArray array];
    for(int i=0;i<4;i++) {
        UISwitch *source=[UISwitch new]; [row addSubview:source];
        NGQQRefreshSwitch(source);
        NGQQBinding *binding=objc_getAssociatedObject(source,&kNGQQBinding);
        REQUIRE(binding && [binding ownerIsCurrent]);
        REQUIRE(source.alpha==1 && !binding.visual.userInteractionEnabled);
        REQUIRE(binding.visual.superview==source && !source.clipsToBounds);
        REQUIRE(CGPointEqualToPoint(binding.visual.center,CGPointMake(30.5,23.5)));
        [sources addObject:source]; [bindings addObject:binding];
    }
    UISwitch *last=sources.lastObject; NGQQBinding *binding=bindings.lastObject;
    for(int tap=0;tap<100;tap++) {
        [binding begin:CGPointMake(20,15)];
        REQUIRE(binding.touching && !binding.ending);
        [last simulateNativeValue:!last.isOn];
        [binding finish:NO];
        REQUIRE(!binding.touching && binding.ending);
        NGQQSyncSwitch(last); // Must not settle/cancel while native lift is finishing.
        pump();
        REQUIRE(!binding.ending && visual(binding).ends==(NSUInteger)tap+1);
        REQUIRE(visual(binding).displayed==last.isOn && last.nativeEvents==(NSUInteger)tap+1);
        for(int i=0;i<3;i++) REQUIRE(sources[i].nativeEvents==0 && !sources[i].isOn && visual(bindings[i]).begins==0);
    }
    // A host-rejected native action is reflected, never inverted a second time.
    NSUInteger ends=visual(binding).ends;
    [binding begin:CGPointZero]; [last simulateNativeValue:NO]; [binding finish:NO]; pump();
    REQUIRE(!visual(binding).displayed && visual(binding).ends==ends+1 && last.nativeEvents==101);
    // A queued release from the same object/cell but a different logical row is stale.
    [binding begin:CGPointZero]; [binding finish:NO]; ends=visual(binding).ends;
    table.fixturePath=[NSIndexPath indexPathWithIndex:1]; REQUIRE(![binding ownerIsCurrent]); pump();
    REQUIRE(visual(binding).ends==ends);
    NGQQRefreshSwitch(last); REQUIRE([binding ownerIsCurrent] && !binding.touching);
    [binding begin:CGPointZero]; last.hidden=YES; NGQQRefreshSwitch(last);
    REQUIRE(!binding.touching && ![binding ownerIsCurrent]); last.hidden=NO; NGQQRefreshSwitch(last);
    [binding begin:CGPointZero]; last.enabled=NO; NGQQSyncSwitch(last);
    REQUIRE(!binding.touching && ![binding ownerIsCurrent]); last.enabled=YES; NGQQRefreshSwitch(last);
    [binding begin:CGPointZero]; last.alpha=0; NGQQRefreshSwitch(last);
    REQUIRE(!binding.touching && last.alpha==0); last.alpha=1; NGQQRefreshSwitch(last);
    // A new owner invalidates the previous owner's queued finishing callback.
    NGQQRefreshSwitch(sources[0]);
    [binding begin:CGPointZero]; [binding finish:NO]; ends=visual(binding).ends;
    [bindings[0] begin:CGPointZero]; pump(); REQUIRE(visual(binding).ends==ends && !binding.ending);
    [bindings[0] finish:YES]; pump();
    // Mask only this source's native drawing layers. Never mask the visual itself.
    CALayer *native=[CALayer layer], *oldMask=[CALayer layer]; native.mask=oldMask;
    [last.layer insertSublayer:native atIndex:0]; NGQQRefreshSwitch(last);
    CALayer *installed=native.mask; REQUIRE(installed && installed!=oldMask && binding.visual.layer.mask==nil);
    for(int i=0;i<100;i++) NGQQRefreshSwitch(last);
    REQUIRE(native.mask==installed && binding.layers.count==1 && last.alpha==1);
    CALayer *external=[CALayer layer]; native.mask=external; NGQQRefreshSwitch(last);
    REQUIRE(native.mask==installed);
    [native removeFromSuperlayer]; NGQQRefreshSwitch(last);
    REQUIRE(native.mask==external && binding.layers.count==0);
    [last.layer addSublayer:native]; NGQQRefreshSwitch(last);
    NGQQRemoveSwitch(last); REQUIRE(native.mask==external && last.clipsToBounds && last.alpha==1);
    REQUIRE(!objc_getAssociatedObject(last,&kNGQQBinding) && !last.eventTarget);
    NGQQRefreshSwitch(last); binding=objc_getAssociatedObject(last,&kNGQQBinding);
    [binding begin:CGPointZero]; [binding finish:NO]; ends=visual(binding).ends;
    NGQQRemoveSwitch(last); pump(); REQUIRE(visual(binding).ends==ends);
    NGQQRefreshSwitch(last); featureEnabled=NO; NGQQRemoveAllSwitches();
    for(UISwitch *source in sources) REQUIRE(!objc_getAssociatedObject(source,&kNGQQBinding) && source.alpha==1 && source.clipsToBounds);
    printf("PASS %lu exact QQ production binding/mask/lifecycle assertions; 100 native-owned events, reuse, hidden/disabled, stale lifts (not UIKit device touches)\n",(unsigned long)checks);
} return 0; }
