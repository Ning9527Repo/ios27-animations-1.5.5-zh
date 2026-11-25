#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

// UIKit is unavailable in the macOS host process. These stand-ins expose only
// the native control state consumed by the extracted production functions.
@interface UIView : NSObject
@property(nonatomic,strong) CALayer *layer;
@property(nonatomic,weak) UIView *superview;
@property(nonatomic,strong) id window;
@property(nonatomic) BOOL hidden, userInteractionEnabled, isAccessibilityElement, clipsToBounds;
@property(nonatomic) CGFloat alpha;
@property(nonatomic) CGRect bounds;
@property(nonatomic) CGPoint center;
@property(nonatomic) CGAffineTransform transform;
+ (BOOL)areAnimationsEnabled;
+ (void)setAnimationsEnabled:(BOOL)enabled;
- (CGPoint)convertPoint:(CGPoint)point toView:(UIView *)view;
- (void)removeFromSuperview;
@end
@implementation UIView
- (instancetype)init { if ((self=[super init])) { _layer=[CALayer layer]; _alpha=1; _userInteractionEnabled=YES; _transform=CGAffineTransformIdentity; } return self; }
+ (BOOL)areAnimationsEnabled { return YES; }
+ (void)setAnimationsEnabled:(BOOL)enabled { (void)enabled; }
- (CGPoint)convertPoint:(CGPoint)point toView:(UIView *)view { (void)view; return point; }
- (void)removeFromSuperview { self.superview=nil; [self.layer removeFromSuperlayer]; }
@end
@interface UITableView : UIView @end
@implementation UITableView @end
@interface UISwitch : UIView
@property(nonatomic,getter=isOn) BOOL on;
@property(nonatomic,getter=isEnabled) BOOL enabled;
@property(nonatomic) NSUInteger events;
@property(nonatomic,copy) void (^callback)(UISwitch *);
- (void)setOn:(BOOL)value animated:(BOOL)animated;
- (void)sendActionsForControlEvents:(NSUInteger)events;
@end
@implementation UISwitch
- (instancetype)init { if ((self=[super init])) { _enabled=YES; self.bounds=CGRectMake(0,0,51,31); self.window=[NSObject new]; } return self; }
- (void)setOn:(BOOL)value animated:(BOOL)animated { (void)animated; self.on=value; }
- (void)sendActionsForControlEvents:(NSUInteger)events { (void)events; self.events++; if(self.callback)self.callback(self); }
@end
static char kNGBindingKey;
static const NSUInteger UIControlEventValueChanged=1;
static int syncs;
static BOOL NGIsClock(void) { return NO; }
static void NGWithoutAnimation(void (^changes)(void)) { changes(); }
static void NGScheduleSwitchSync(UISwitch *source) { (void)source; syncs++; }
#define NGClockTrace(...) do {} while (0)
/* PRODUCTION_BINDING_INTERFACE */
static UITableView *NGClockBeginReplay(NGSwitchBinding *binding, BOOL value) { (void)binding;(void)value;return nil; }
static void NGClockScheduleReplay(UITableView *table) { (void)table; }
/* PRODUCTION_BINDING_IMPLEMENTATION */
/* PRODUCTION_MASK_HELPERS */
/* PRODUCTION_GEOMETRY */
static int checks;
#define REQUIRE(x) do { checks++; if(!(x)){ NSLog(@"FAIL line %d: %s",__LINE__,#x);abort();} }while(0)
static NGSwitchBinding *bind(UISwitch *source) {
    NGSwitchBinding *b=[NGSwitchBinding new];b.source=source;b.sourceHosted=YES;b.overlay=[UIView new];
    b.overlay.superview=source;[source.layer addSublayer:b.overlay.layer];
    objc_setAssociatedObject(source,&kNGBindingKey,b,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return b;
}
int main(void) { @autoreleasepool {
    NSMutableArray<UISwitch *> *sources=[NSMutableArray array];
    NSMutableArray<NGSwitchBinding *> *bindings=[NSMutableArray array];
    for(int i=0;i<4;i++){ UISwitch *s=[UISwitch new];[sources addObject:s];[bindings addObject:bind(s)]; }
    for(int tap=0;tap<100;tap++) [bindings.lastObject commit:!sources.lastObject.isOn];
    REQUIRE(sources.lastObject.events==100 && syncs==100);
    for(int i=0;i<3;i++) REQUIRE(!sources[i].isOn && sources[i].events==0);
    UISwitch *last=sources.lastObject;NGSwitchBinding *binding=bindings.lastObject;
    BOOL original=last.isOn;
    last.callback=^(UISwitch *s){s.on=original;};
    [binding commit:!original];REQUIRE(last.isOn==original && last.events==101);
    for(int i=0;i<3;i++) REQUIRE(!sources[i].isOn && sources[i].events==0);
    last.callback=nil;
    binding.overlay.superview=sources[1];[binding commit:!original];REQUIRE(last.events==101 && sources[1].events==0);
    binding.overlay.superview=last;
    last.hidden=YES;[binding commit:!original];REQUIRE(last.events==101);last.hidden=NO;
    last.alpha=0;[binding commit:!original];REQUIRE(last.events==101);last.alpha=1;
    last.window=nil;[binding commit:!original];REQUIRE(last.events==101);last.window=[NSObject new];
    objc_setAssociatedObject(last,&kNGBindingKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [binding commit:!original];REQUIRE(last.events==101);
    objc_setAssociatedObject(last,&kNGBindingKey,binding,OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    CALayer *native=[CALayer layer],*saved=[CALayer layer];native.mask=saved;[last.layer insertSublayer:native atIndex:0];
    NGMaskHostedNativeLayers(last,binding);
    REQUIRE(native.mask!=saved && native.mask!=nil && binding.nativeMasks.count==1);
    REQUIRE(binding.overlay.layer.mask==nil && last.alpha==1);
    CALayer *mask=native.mask;
    for(int i=0;i<100;i++) NGMaskHostedNativeLayers(last,binding);
    REQUIRE(native.mask==mask && binding.nativeMasks.count==1);
    CALayer *replacement=[CALayer layer];native.mask=replacement;
    NGMaskHostedNativeLayers(last,binding);REQUIRE(native.mask==mask);
    [native removeFromSuperlayer];NGMaskHostedNativeLayers(last,binding);
    REQUIRE(native.mask==replacement && !binding.nativeMasks.count);
    CALayer *native2=[CALayer layer];[last.layer insertSublayer:native2 atIndex:0];
    NGMaskHostedNativeLayers(last,binding);REQUIRE(native2.mask!=nil);
    NGRestoreHostedNativeLayers(binding);REQUIRE(native2.mask==nil && !binding.nativeMasks.count);
    [last.layer addSublayer:native];NGMaskHostedNativeLayers(last,binding);
    CALayer *external=[CALayer layer];native.mask=external;NGRestoreHostedNativeLayers(binding);
    REQUIRE(native.mask==external);
    for(int tx=-2;tx<=2;tx++)for(int ty=-2;ty<=2;ty++) {
        last.transform=CGAffineTransformMakeTranslation(tx*30,ty*30);last.bounds=CGRectMake(5,8,51,31);
        NGApplySwitchGeometry(last,binding,last);
        REQUIRE(CGPointEqualToPoint(binding.overlay.center,CGPointMake(30.5,23.5)));
        REQUIRE(CGAffineTransformIsIdentity(binding.overlay.transform));
        REQUIRE(CGSizeEqualToSize(binding.overlay.bounds.size,CGSizeMake(63,28)));
        REQUIRE(last.alpha==1);
    }
    printf("PASS %d extracted production binding/mask/geometry assertions; four isolated controls, host rejection, stale bindings (Foundation/CALayer stand-in, not UIKit)\n",checks);
} return 0; }
