#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <notify.h>
#import <dlfcn.h>
#import <string.h>
#import "NB27ReferenceMotion.h"
#import "NB27Compact.h"
#import "NB27Diagnostics.h"
#import "NB27Motion.h"

// No GlassSuiteX library is embedded, dlopened, patched, or required.
static NSString *const NB27Domain=@"com.ning.ios2627anims";
static NSString *const NB27Prefix=@"com.ning.ios2627anims.";
static NSString *const NB27EntranceKey=@"com.ning.ios2627anims.entrance";
static NSString *const NB27ExitKey=@"com.ning.ios2627anims.exit";
static NSString *const NB27BaseKey=@"com.ning.ios2627anims.exitBase";
static char NB27CurrentKey,NB27PendingKey,NB27OwnerKey,NB27InteractionKey,NB27GenerationKey,NB27NativeExitKey;
static BOOL NB27OriginalClassSeen=NO;
static void NB27Reload(void);
static NSHashTable *NB27Sessions;
static BOOL NB27UserEnabled=YES,NB27OriginalEnabled=NO;
static double NB27Elasticity=1.0,NB27TransitionScale=1.0,NB27DwellScale=1.0;
static BOOL NB27BannerTransitionDurationDone=NO;
static BOOL NB27DismissTimerDone=NO,NB27StartTimerWithDelayDone=NO;
static NSString *const NB27DismissScopeKey=@"com.ning.ios2627anims.dismiss-scope";
static double (*NB27OriginalBannerTransitionDuration)(id,SEL,id);
static void (*NB27OriginalStartDismissTimer)(id,SEL);
static id (*NB27OriginalStartTimerWithDelay)(id,SEL,unsigned long long,id);
static BOOL NB27IsReplacement(id animator);
static BOOL NB27IsReplacementTransition(id animator,id<UIViewControllerContextTransitioning> context);
@class NB27Session;
static void NB27End(NB27Session *s);
static BOOL NB27Enabled(void);
static void NB27AnimateEntrance(NB27Session *s,UIView *card);
static void NB27AnimateExit(NB27Session *s);
static void NB27ClearController(UIViewController *controller);
static void NB27AbortNativeExit(id object);
static void NB27BeginNativeExit(id animator,id<UIViewControllerContextTransitioning> context);
static double NB27NativeExitDuration(id animator,id<UIViewControllerContextTransitioning> context);

@interface NB27Pose:NSObject
@property(nonatomic,weak) CALayer *layer;
@property(nonatomic) CGPoint position;
@property(nonatomic) CGRect bounds;
@property(nonatomic) CATransform3D transform;
@property(nonatomic) float opacity;
+(instancetype)capture:(CALayer *)layer;
-(CAAnimationGroup *)hold:(double)duration;
@end
@implementation NB27Pose
+(instancetype)capture:(CALayer *)layer {
 NB27Pose *p=[self new];CALayer *source=layer.presentationLayer?:layer;
 p.layer=layer;p.position=source.position;p.bounds=source.bounds;
 p.transform=source?source.transform:(CATransform3D){0};p.opacity=source.opacity;return p;
}
-(CAAnimationGroup *)hold:(double)duration {
 NSArray *paths=@[@"position",@"bounds",@"transform",@"opacity"];
 NSArray *values=@[[NSValue valueWithCGPoint:self.position],[NSValue valueWithCGRect:self.bounds],
  [NSValue valueWithCATransform3D:self.transform],@(self.opacity)];
 NSMutableArray *parts=[NSMutableArray new];
 for(NSUInteger i=0;i<4;i++) { CABasicAnimation *a=[CABasicAnimation animationWithKeyPath:paths[i]];
  a.fromValue=values[i];a.toValue=values[i];a.duration=duration;
  a.fillMode=kCAFillModeBoth;a.removedOnCompletion=NO;[parts addObject:a]; }
 CAAnimationGroup *g=[CAAnimationGroup animation];g.animations=parts;g.duration=duration;
 g.fillMode=kCAFillModeBoth;g.removedOnCompletion=NO;return g;
}
@end
@interface NB27Session:NSObject<CAAnimationDelegate>
@property(nonatomic,weak) UIViewController *controller;
@property(nonatomic,weak) UIView *card;
@property(nonatomic,strong) NSHashTable<CALayer *> *guardedLayers;
@property(nonatomic,copy) NSArray<NB27Pose *> *heldPoses;
@property(nonatomic) BOOL active,exiting,motionOriginReady,retentionOnly,delayedEntrance;
@property(nonatomic) float savedEntranceOpacity;
@property(nonatomic) NSUInteger compactTicket;
@property(nonatomic) double compactDX,compactDY,compactScaleX,compactScaleY,baseScaleX,baseScaleY;
@property(nonatomic) double exitAdjustmentX,exitAdjustmentY;
@property(nonatomic) NB27CompactAnchor timeAnchor;
@property(nonatomic,strong) id<UIViewControllerContextTransitioning> transitionContext;
@property(nonatomic,strong) id transitionGeneration;
@property(nonatomic) double deadline,startedAt,pendingSince,startMotionTime,nativeDuration,exitDuration;
@property(nonatomic) double elasticity,transitionScale;
@end
@implementation NB27Session
-(void)animationDidStop:(CAAnimation *)animation finished:(BOOL)finished {
 (void)animation;(void)finished;
 if(self.exiting) {
  // Native removal can invoke the delegate before DidDisappear. Wait for that
  // confirmation (or bounded expiry) instead of discarding a successful exit.
  // Explicit cancellation/interaction still clears the session immediately.
  if(self.transitionContext.transitionWasCancelled)NB27End(self);
  return;
 }
 NB27End(self);
}
@end
static id NB27Associated(id object,const void *key) {
 return object?objc_getAssociatedObject(object,key):nil;
}
static void NB27RemoveCardAnimations(UIView *card) {
 [card.layer removeAnimationForKey:NB27EntranceKey];
 [card.layer removeAnimationForKey:NB27ExitKey];
 [card.layer removeAnimationForKey:NB27BaseKey];
}
static void NB27ReleaseExitVisual(NB27Session *s) {
 if(!s)return;
 NB27RemoveCardAnimations(s.card);
 for(CALayer *layer in s.guardedLayers.allObjects)[layer removeAnimationForKey:NB27BaseKey];
 s.deadline=0;
}
static void NB27End(NB27Session *s) {
 if(!s)return;[NB27Sessions removeObject:s];
 UIViewController *c=s.controller;
 if(s.delayedEntrance) {
  UIView *card=s.card;
  if(card) { [CATransaction begin];[CATransaction setDisableActions:YES];card.layer.opacity=s.savedEntranceOpacity;[CATransaction commit]; }
  s.delayedEntrance=NO;
 }
 if(c&&NB27Associated(c,&NB27PendingKey)==s)
  objc_setAssociatedObject(c,&NB27PendingKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
 if(!s.active)return;s.active=NO;
 NB27CompactAbortExit(s.compactTicket);s.compactTicket=0;
 NB27RemoveCardAnimations(s.card);
 for(CALayer *layer in s.guardedLayers.allObjects) {
  if(NB27Associated(layer,&NB27OwnerKey)==s) {
   [layer removeAnimationForKey:NB27BaseKey];
   objc_setAssociatedObject(layer,&NB27OwnerKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  }
 }
 if(c&&NB27Associated(c,&NB27CurrentKey)==s)
  objc_setAssociatedObject(c,&NB27CurrentKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
 [s.guardedLayers removeAllObjects];s.heldPoses=nil;s.transitionContext=nil;s.transitionGeneration=nil;
}
static void NB27ClearController(UIViewController *c) {
 NB27End(NB27Associated(c,&NB27CurrentKey));NB27End(NB27Associated(c,&NB27PendingKey));
}
static void NB27CancelPendingForTransition(UIViewController *c,id generation) {
 if(!c||!generation||NB27Associated(c,&NB27GenerationKey)!=generation)return;
 NB27Session *pending=NB27Associated(c,&NB27PendingKey);
 if(pending)NB27End(pending);
 NB27Session *current=NB27Associated(c,&NB27CurrentKey);
 if(current&&current.transitionGeneration==generation)NB27End(current);
 objc_setAssociatedObject(c,&NB27GenerationKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static BOOL NB27Enabled(void) {
 if(!NB27OriginalClassSeen&&NSClassFromString(@"GAXIOS27BannerSession"))NB27Reload();
 return NB27UserEnabled&&!NB27OriginalEnabled&&!UIAccessibilityIsReduceMotionEnabled();
}
static void NB27Guard(NB27Session *s,CALayer *layer) {
 if(!layer)return;NB27Session *owner=NB27Associated(layer,&NB27OwnerKey);
 if(owner&&owner!=s)NB27End(owner);
 objc_setAssociatedObject(layer,&NB27OwnerKey,s,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
 [s.guardedLayers addObject:layer];
}
static NSArray<CALayer *> *NB27Layers(UIView *card,UIView *root,UIView *container) {
 NSHashTable *layers=[NSHashTable weakObjectsHashTable];
 for(UIView *start in @[card,root?:card]) {
  UIView *view=start;
  for(NSUInteger depth=0;view&&view!=container&&depth<16;depth++,view=view.superview) {
   if([view isKindOfClass:UIWindow.class])break;
   [layers addObject:view.layer];if(view==root)break;
  }
 }
 return layers.allObjects;
}
static void NB27GuardPath(NB27Session *s,UIView *view,UIView *container) {
 for(NSUInteger depth=0;view&&view!=container&&depth<16;depth++,view=view.superview) {
  if([view isKindOfClass:UIWindow.class])break;NB27Guard(s,view.layer);
 }
}
static NSArray<NB27Pose *> *NB27Capture(NSArray<CALayer *> *layers) {
 NSMutableArray *poses=[NSMutableArray new];
 for(CALayer *layer in layers)[poses addObject:[NB27Pose capture:layer]];return poses;
}
static UIView *NB27FindShortLook(UIView *view,NSUInteger depth) {
 if(!view||depth>12)return nil;
 Class cls=NSClassFromString(@"NCNotificationShortLookView");
 if(cls&&[view isKindOfClass:cls])return view;
 for(UIView *child in view.subviews) { UIView *found=NB27FindShortLook(child,depth+1);if(found)return found; }
 return nil;
}
static BOOL NB27ValidCard(UIView *card) {
 CGFloat w=CGRectGetWidth(card.bounds),h=CGRectGetHeight(card.bounds);
 return card&&isfinite(w)&&isfinite(h)&&w>=100&&h>=20&&h<=360;
}
static UIView *NB27Root(id<UIViewControllerContextTransitioning> context,UIViewController *controller,BOOL to) {
 return [context viewForKey:to?UITransitionContextToViewKey:UITransitionContextFromViewKey]?:controller.view;
}
static UIView *NB27Card(id<UIViewControllerContextTransitioning> context,UIViewController *controller,BOOL to) {
 UIView *root=NB27Root(context,controller,to);UIView *card=NB27FindShortLook(root,0);
 if(!card&&NB27ValidCard(root))card=root;return card;
}

static CAKeyframeAnimation *NB27Keyframes(NSString *path,NSArray<NSNumber *> *values,double duration,BOOL exit) {
 CAKeyframeAnimation *a=[CAKeyframeAnimation animationWithKeyPath:path];
 a.values=values;a.duration=duration;a.calculationMode=kCAAnimationLinear;
 a.timingFunction=[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
 a.additive=YES;a.removedOnCompletion=!exit;if(exit)a.fillMode=kCAFillModeBoth;return a;
}
static void NB27SetFrameRate(CAAnimation *a,UIView *view) {
 if(@available(iOS 15.0,*)) {
  UIScreen *screen=view.window.screen?:UIScreen.mainScreen;
  float maxFPS=(float)MIN(MAX(screen.maximumFramesPerSecond,60),120);
  a.preferredFrameRateRange=CAFrameRateRangeMake(60,maxFPS,maxFPS);
 }
}
static void NB27Expire(NB27Session *s,double delay) {
 __weak NB27Session *weak=s;
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
  NB27Session *strong=weak;
  if(!strong||!strong.active)return;
  if(strong.exiting&&!strong.transitionContext.transitionWasCancelled) {
   if(!strong.retentionOnly) {
    strong.retentionOnly=YES;
    NB27CompactFinishExit(strong.compactTicket);strong.compactTicket=0;
    NB27ReleaseExitVisual(strong);NB27Expire(strong,4.0);
   } else NB27End(strong);
  } else NB27End(strong);
 });
}
static BOOL NB27ModelScale(UIView *card,double *x,double *y) {
 CATransform3D t=card.layer.transform,axis=CATransform3DIdentity;
 axis.m11=t.m11;axis.m22=t.m22;axis.m41=t.m41;axis.m42=t.m42;
 if(!CATransform3DEqualToTransform(t,axis)||!isfinite(t.m11)||!isfinite(t.m22)||
    !isfinite(t.m41)||!isfinite(t.m42)||t.m11<=.05||t.m22<=.05||t.m11>4||t.m22>4)return NO;
 *x=t.m11;*y=t.m22;return YES;
}
static BOOL NB27MeasureCompactOrigin(NB27Session *s,UIView *card) {
 double baseX,baseY;
 if(!card.superview||!card.window||!NB27ModelScale(card,&baseX,&baseY)) {
  NB27Diagnostic(@"origin-fallback",@"unsupported or detached banner model");return NO;
 }
 s.baseScaleX=baseX;s.baseScaleY=baseY;
 double w=CGRectGetWidth(card.bounds)*baseX,h=CGRectGetHeight(card.bounds)*baseY;
 s.compactScaleX=NB27MotionNodes[0][1];s.compactScaleY=NB27MotionNodes[0][2];
 s.compactDX=w*NB27MotionNodes[0][3];s.compactDY=h*NB27MotionNodes[0][4];
 s.motionOriginReady=NO;
 CGPoint origin=CGPointZero;CGSize lineSize=CGSizeZero;
 NB27CompactAnchor anchor=s.timeAnchor;
 if(!anchor.valid)anchor=NB27CompactPrepareTimeAnchor(card);
 if(!NB27CompactOriginFromAnchor(card,anchor,&origin,&lineSize)) {
  NB27Diagnostic(@"origin-fallback",anchor.valid?@"clock snapshot cannot map to banner":@"no visible status clock");return YES;
 }
 double compactScaleX=NB27ReferenceCompactScale(lineSize.width,CGRectGetWidth(card.bounds)*baseX);
 double compactScaleY=NB27ReferenceCompactScale(lineSize.height,CGRectGetHeight(card.bounds)*baseY);
 CGPoint visualCenter=[card.layer convertPoint:CGPointMake(CGRectGetMidX(card.bounds),CGRectGetMidY(card.bounds))
  toLayer:card.superview.layer];
 double dx=origin.x-visualCenter.x,dy=origin.y-visualCenter.y;
 if(!isfinite(dx)||!isfinite(dy)||fabs(dx)>w*4||fabs(dy)>h*4) {
  NB27Diagnostic(@"origin-fallback",@"clock snapshot outside supported card coordinate range");return YES;
 }
 s.compactDX=dx;s.compactDY=dy;s.compactScaleX=compactScaleX;s.compactScaleY=compactScaleY;s.motionOriginReady=YES;
 return YES;
}
static void NB27AnimateEntrance(NB27Session *s,UIView *card) {
 if(!s)return;if(!NB27Enabled()){NB27End(s);return;}
 NB27RemoveCardAnimations(card);if(!s.active)return;s.card=card;
 NB27CompactNoteEntrance(card);
 // Sample the clock line after the native transition has installed the final
 // banner hierarchy. A pre-transition snapshot may map to the wrong position.
 s.timeAnchor=NB27CompactPrepareTimeAnchor(card);
 if(!NB27MeasureCompactOrigin(s,card)){NB27End(s);return;}
 if(!s.motionOriginReady) {
  NB27Diagnostic(@"entrance-fallback",@"clock-line origin unavailable; refusing guessed banner position");
  NB27End(s);return;
 }
 if(s.delayedEntrance) {
  [CATransaction begin];[CATransaction setDisableActions:YES];card.layer.opacity=s.savedEntranceOpacity;[CATransaction commit];
  s.delayedEntrance=NO;
 }
 s.timeAnchor=(NB27CompactAnchor){0};
 double duration=NB27ScaledDuration(s.transitionScale),w=CGRectGetWidth(card.bounds),h=CGRectGetHeight(card.bounds);
 CGPoint anchor=card.layer.anchorPoint;
 NSMutableArray *sx=[NSMutableArray new],*sy=[NSMutableArray new],*px=[NSMutableArray new],*py=[NSMutableArray new];
 for(NSUInteger i=0;i<NB27SampleCount;i++) {
  double t=(double)i*duration/(NB27SampleCount-1);
  NB27ReferencePose p=NB27ReferenceLayerCompactAtWithSettings(t,w,h,anchor.x,anchor.y,s.compactDX,s.compactDY,s.baseScaleX,s.baseScaleY,s.compactScaleX,s.compactScaleY,s.elasticity,s.transitionScale);
  [sx addObject:@(p.scaleX)];[sy addObject:@(p.scaleY)];
  [px addObject:@(p.x)];[py addObject:@(p.y)];
 }
 CAAnimationGroup *g=[CAAnimationGroup animation];
 g.animations=@[NB27Keyframes(@"transform.scale.x",sx,duration,NO),
  NB27Keyframes(@"transform.scale.y",sy,duration,NO),
  NB27Keyframes(@"position.x",px,duration,NO),NB27Keyframes(@"position.y",py,duration,NO)];
 g.duration=duration;g.timingFunction=[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
 double now=CACurrentMediaTime();g.beginTime=[card.layer convertTime:now fromLayer:nil];
 g.removedOnCompletion=YES;g.delegate=s;NB27SetFrameRate(g,card);
 s.startedAt=now;s.deadline=now+duration+.15;
 [card.layer addAnimation:g forKey:NB27EntranceKey];NB27Expire(s,duration+.15);
}
static void NB27AnimateExit(NB27Session *s) {
 if(!s||!s.active)return;
 UIView *card=s.card;if(!NB27Enabled()){NB27End(s);return;}
 if(!card.window) {
  s.retentionOnly=YES;NB27ReleaseExitVisual(s);NB27Expire(s,4.0);return;
 }
 double now=CACurrentMediaTime(),w=CGRectGetWidth(card.bounds),h=CGRectGetHeight(card.bounds);
 float opacity=1;
 for(NB27Pose *pose in s.heldPoses) {
  CALayer *layer=pose.layer;if(!layer)continue;
  CAAnimationGroup *hold=[pose hold:s.exitDuration];hold.beginTime=[layer convertTime:now fromLayer:nil];
  [layer addAnimation:hold forKey:NB27BaseKey];
  if(layer==card.layer){w=CGRectGetWidth(pose.bounds);h=CGRectGetHeight(pose.bounds);opacity=pose.opacity;}
 }
 CGPoint anchor=card.layer.anchorPoint;
 NSMutableArray *sx=[NSMutableArray new],*sy=[NSMutableArray new],*px=[NSMutableArray new],*py=[NSMutableArray new],*alpha=[NSMutableArray new];
 double start=s.startMotionTime;
 // Geometry and ticket were captured before the native animator changed the
 // model layers. Never remeasure against its offscreen/end position here.
 for(NSUInteger i=0;i<NB27SampleCount;i++) {
  double progress=(double)i/(NB27SampleCount-1),t=(1-progress)*NB27Clamp(start,0,NB27ScaledDuration(s.transitionScale));
  NB27ReferencePose p=NB27ReferenceLayerCompactReverseWithSettings(t,start,w,h,anchor.x,anchor.y,s.compactDX,s.compactDY,s.baseScaleX,s.baseScaleY,s.compactScaleX,s.compactScaleY,s.elasticity,s.transitionScale);
  double blend=progress*progress*(3-2*progress);
  [sx addObject:@(p.scaleX)];[sy addObject:@(p.scaleY)];
  [px addObject:@(fma(blend,s.exitAdjustmentX,p.x))];[py addObject:@(fma(blend,s.exitAdjustmentY,p.y))];
  [alpha addObject:@((NB27ExitOpacity(progress)-1)*opacity)];
 }
 CAAnimationGroup *g=[CAAnimationGroup animation];
 g.animations=@[NB27Keyframes(@"transform.scale.x",sx,s.exitDuration,YES),
  NB27Keyframes(@"transform.scale.y",sy,s.exitDuration,YES),
  NB27Keyframes(@"position.x",px,s.exitDuration,YES),NB27Keyframes(@"position.y",py,s.exitDuration,YES),
  NB27Keyframes(@"opacity",alpha,s.exitDuration,YES)];
 g.duration=s.exitDuration;g.beginTime=[card.layer convertTime:now fromLayer:nil];
 g.fillMode=kCAFillModeBoth;g.removedOnCompletion=NO;g.delegate=s;NB27SetFrameRate(g,card);
 [card.layer addAnimation:g forKey:NB27ExitKey];
 NB27CompactAnimateExit(s.compactTicket,s.exitDuration);
 NB27Expire(s,s.nativeDuration+.15);
}
static CAAnimation *NB27Neutralize(CAAnimation *animation,BOOL exit) {
 if([animation isKindOfClass:CAAnimationGroup.class]) {
  CAAnimationGroup *original=(id)animation;NSMutableArray *children=[NSMutableArray new];BOOL changed=NO;
  for(CAAnimation *child in original.animations) {
   CAAnimation *new=NB27Neutralize(child,exit);[children addObject:new];changed|=new!=child;
  }
  if(!changed)return animation;CAAnimationGroup *copy=[original copy];copy.animations=children;return copy;
 }
 if(![animation isKindOfClass:CAPropertyAnimation.class])return animation;
 NSString *path=((CAPropertyAnimation *)animation).keyPath;
 BOOL match=[path isEqualToString:@"position"]||[path hasPrefix:@"position."]||
  [path isEqualToString:@"transform"]||[path hasPrefix:@"transform."]||
  [path isEqualToString:@"sublayerTransform"]||[path hasPrefix:@"sublayerTransform."]||
  [path isEqualToString:@"opacity"]||(exit&&([path isEqualToString:@"bounds"]||[path hasPrefix:@"bounds."]));
 if(!match)return animation;id zero=@0;
 if([path isEqualToString:@"position"]||[path isEqualToString:@"bounds.origin"])zero=[NSValue valueWithCGPoint:CGPointZero];
 else if([path isEqualToString:@"bounds"])zero=[NSValue valueWithCGRect:CGRectZero];
 else if([path isEqualToString:@"bounds.size"])zero=[NSValue valueWithCGSize:CGSizeZero];
 else if([path isEqualToString:@"transform"]||[path isEqualToString:@"sublayerTransform"])
  zero=[NSValue valueWithCATransform3D:CATransform3DIdentity];
 if([animation isKindOfClass:CABasicAnimation.class]) {
  CABasicAnimation *copy=[animation copy];copy.additive=YES;copy.cumulative=NO;copy.valueFunction=nil;
  copy.fromValue=zero;copy.toValue=zero;copy.byValue=nil;return copy;
 }
 if([animation isKindOfClass:CAKeyframeAnimation.class]) {
  CAKeyframeAnimation *copy=[animation copy];copy.additive=YES;copy.cumulative=NO;copy.valueFunction=nil;
  copy.path=nil;copy.rotationMode=nil;copy.values=@[zero,zero];copy.keyTimes=@[@0,@1];
  copy.timingFunctions=nil;copy.calculationMode=kCAAnimationLinear;return copy;
 }
 return animation;
}

static NB27Session *NB27FindSession(id object) {
 if(!object)return nil;NB27Session *s=NB27Associated(object,&NB27CurrentKey);if(s)return s;
 if([object isKindOfClass:UIViewController.class]) {
  UIViewController *c=object;
  for(NSUInteger i=0;c&&i<13;i++,c=c.parentViewController){s=NB27Associated(c,&NB27CurrentKey);if(s)return s;}
  UIViewController *c0=object;if(!c0.isViewLoaded)return nil;object=c0.view;
 }
 if([object isKindOfClass:UIView.class]) {
  UIView *v=object;
  for(NSUInteger i=0;v&&i<17;i++,v=v.superview){s=NB27Associated(v.layer,&NB27OwnerKey);if(s)return s;}
 }
 return nil;
}
static NB27Session *NB27NewSession(UIViewController *controller) {
 NB27Session *s=[NB27Session new];s.controller=controller;s.active=YES;
 s.elasticity=NB27Elasticity;s.transitionScale=NB27TransitionScale;
 s.transitionGeneration=NB27Associated(controller,&NB27GenerationKey);
 s.guardedLayers=[NSHashTable weakObjectsHashTable];[NB27Sessions addObject:s];
 objc_setAssociatedObject(controller,&NB27CurrentKey,s,OBJC_ASSOCIATION_RETAIN_NONATOMIC);return s;
}
static BOOL NB27IsReplacement(id animator) {
 Class cls=NSClassFromString(@"BNBannerReplacementTransitionAnimator");return cls&&[animator isKindOfClass:cls];
}
static BOOL NB27IsReplacementTransition(id animator,id<UIViewControllerContextTransitioning> context) {
 if(NB27IsReplacement(animator))return YES;
 if(!context)return NO;
 Class presentable=NSClassFromString(@"SBNotificationPresentableViewController");
 UIViewController *from=[context viewControllerForKey:UITransitionContextFromViewControllerKey];
 UIViewController *to=[context viewControllerForKey:UITransitionContextToViewControllerKey];
 return presentable&&from&&to&&from!=to&&[from isKindOfClass:presentable]&&[to isKindOfClass:presentable];
}
static NB27Session *NB27PrepareExit(id animator,id<UIViewControllerContextTransitioning> context,
 UIViewController *controller,double overrideDuration) {
 if(!NB27Enabled())return nil;
 SEL selector=NSSelectorFromString(@"transitionDuration:");
 double duration=overrideDuration>=0?overrideDuration:
  ([animator respondsToSelector:selector]?((double(*)(id,SEL,id))objc_msgSend)(animator,selector,context):.25);
 if(!isfinite(duration)||duration<0)return nil;
 duration=fmax(duration,1.0/60.0);
 UIView *card=NB27Card(context,controller,NO);if(!NB27ValidCard(card))return nil;
 NB27Session *old=NB27Associated(controller,&NB27CurrentKey);if(old.exiting)return nil;
 NSArray *layers=NB27Layers(card,NB27Root(context,controller,NO),context.containerView);
 NSArray<NB27Pose *> *poses=NB27Capture(layers);
 NB27Session *pending=NB27Associated(controller,&NB27PendingKey);
 id generation=NB27Associated(controller,&NB27GenerationKey);
 double elasticity=NB27Elasticity,transitionScale=NB27TransitionScale;
 double now=CACurrentMediaTime(),start=NB27ScaledDuration(transitionScale);
 BOOL reusable=pending&&generation&&pending.transitionGeneration==generation&&pending.card==card&&
  pending.heldPoses.count>0&&now-pending.pendingSince<.5;
 Class transitionClass=NSClassFromString(@"BNBannerTransitionAnimator");
 BOOL nativeDurationScaled=NB27BannerTransitionDurationDone&&transitionClass&&[animator isKindOfClass:transitionClass];
 if(overrideDuration>0||!nativeDurationScaled)duration*=transitionScale;
 if(reusable) {
  NSMutableArray *matches=[NSMutableArray new];
  for(NB27Pose *p in pending.heldPoses)if(p.layer&&[layers containsObject:p.layer])[matches addObject:p];
  reusable=matches.count>0;if(reusable){poses=matches;start=pending.startMotionTime;}
 }
 if(!reusable&&old.active&&old.startedAt>0)start=NB27Clamp(now-old.startedAt,0,NB27ScaledDuration(old.transitionScale));
 if(reusable&&pending.transitionScale!=transitionScale)start=NB27ScaledDuration(transitionScale);
 NB27Session *originSource=reusable?pending:((old.active&&old.card==card&&old.startedAt>0)?old:nil);
 double dx=originSource.compactDX,dy=originSource.compactDY;
 double compactScaleX=originSource.compactScaleX,compactScaleY=originSource.compactScaleY;
 NB27End(old);NB27End(pending);
 NB27Session *s=NB27NewSession(controller);s.card=card;s.exiting=YES;s.heldPoses=poses;
 s.elasticity=elasticity;s.transitionScale=transitionScale;s.transitionContext=context;
 if(NB27IsReplacementTransition(animator,context)) s.timeAnchor=NB27CompactPrepareTimeAnchor(context.containerView);
 if(!NB27MeasureCompactOrigin(s,card)) {
  NB27CompactBeginExit(NO);NB27End(s);return nil;
 }
 if(originSource&&start<NB27ScaledDuration(transitionScale)) {
  // Reverse from the interrupted entrance; ease toward the freshly measured endpoint.
  if(s.motionOriginReady) {
   s.exitAdjustmentX=s.compactDX-dx;s.exitAdjustmentY=s.compactDY-dy;
  }
  s.compactDX=dx;s.compactDY=dy;
  s.compactScaleX=compactScaleX;s.compactScaleY=compactScaleY;
 }
 s.compactTicket=NB27CompactBeginExit(s.motionOriginReady);
 s.startMotionTime=start;s.nativeDuration=duration;s.exitDuration=NB27ExitDuration(duration,start,transitionScale);
 s.deadline=now+duration+.15;
 for(NB27Pose *pose in poses)NB27Guard(s,pose.layer);
 return s;
}
static void NB27StagePending(NB27Session *old) {
 if(!NB27Enabled()||!old.active||old.exiting||!old.card||old.startedAt<=0)return;
 UIViewController *controller=old.controller;if(!controller)return;
 NB27End(NB27Associated(controller,&NB27PendingKey));
 NB27Session *pending=[NB27Session new];pending.controller=controller;pending.card=old.card;
 pending.heldPoses=NB27Capture(old.guardedLayers.allObjects);
 pending.transitionGeneration=NB27Associated(controller,&NB27GenerationKey);
 pending.compactDX=old.compactDX;pending.compactDY=old.compactDY;
 pending.compactScaleX=old.compactScaleX;pending.compactScaleY=old.compactScaleY;
 double elapsed=CACurrentMediaTime()-old.startedAt;
 pending.startMotionTime=NB27Clamp(elapsed,0,NB27ScaledDuration(old.transitionScale));
 pending.elasticity=old.elasticity;pending.transitionScale=old.transitionScale;
 pending.pendingSince=CACurrentMediaTime();[NB27Sessions addObject:pending];
 objc_setAssociatedObject(controller,&NB27PendingKey,pending,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
 NB27Expire(pending,.5);
}
static void (*NB27OriginalAnimate)(id,SEL,id);
static void (*NB27OriginalAdd)(id,SEL,CAAnimation *,NSString *);
static void (*NB27OriginalWillDisappear)(id,SEL,id,id);
static void (*NB27OriginalDidDisappear)(id,SEL,id,id);
static void (*NB27OriginalInteraction)(id,SEL,id);
static void (*NB27OriginalViewInteraction)(id,SEL,id);
static void (*NB27OriginalLongLook)(id,SEL,id);
static void NB27AnimateHook(id animator,SEL cmd,id<UIViewControllerContextTransitioning> context) {
 if(!NB27Enabled()) {
  for(NB27Session *s in NB27Sessions.allObjects)NB27End(s);
  NB27BeginNativeExit(animator,context);
  NB27OriginalAnimate(animator,cmd,context);
  if(context.transitionWasCancelled)NB27AbortNativeExit([context viewControllerForKey:UITransitionContextFromViewControllerKey]);
  return;
 }
 UIViewController *to=[context viewControllerForKey:UITransitionContextToViewControllerKey];
 UIViewController *from=[context viewControllerForKey:UITransitionContextFromViewControllerKey];
 Class presentable=NSClassFromString(@"SBNotificationPresentableViewController");
 BOOL validTo=presentable&&[to isKindOfClass:presentable];
 BOOL validFrom=presentable&&[from isKindOfClass:presentable];
 BOOL replacement=NB27IsReplacementTransition(animator,context);
 SEL presentingSelector=NSSelectorFromString(@"isPresenting");
 BOOL knows=[animator respondsToSelector:presentingSelector];
 BOOL presenting=knows&&((BOOL(*)(id,SEL))objc_msgSend)(animator,presentingSelector);
 Class transition=NSClassFromString(@"BNBannerTransitionAnimator");
 BOOL dismissing=transition&&[animator isKindOfClass:transition]&&knows&&!presenting&&!replacement;
 if(replacement) {
  // Interactive replacements remain entirely system-owned. For the normal
  // notification hand-off, preserve the outgoing compact-to-line animation,
  // then start the incoming card from that same measured clock-line anchor.
  if(context.isInteractive||!NB27Enabled()) {
   if(validFrom)NB27ClearController(from);
   if(validTo)NB27ClearController(to);
   if(!context.isInteractive)NB27BeginNativeExit(animator,context);
   NB27OriginalAnimate(animator,cmd,context);
   if(context.transitionWasCancelled&&from)NB27AbortNativeExit(from);
   return;
  }
  UIView *newCard=validTo?NB27Card(context,to,YES):nil;
  BOOL animateIncoming=newCard&&NB27ValidCard(newCard)&&CGRectGetHeight(newCard.bounds)<=360;
  NB27Session *outgoing=validFrom?NB27PrepareExit(animator,context,from,-1):nil;
  NB27Session *incoming=nil;
  if(animateIncoming) {
   NB27ClearController(to);NB27RemoveCardAnimations(newCard);incoming=NB27NewSession(to);
   incoming.timeAnchor=NB27CompactPrepareTimeAnchor(context.containerView);
   animateIncoming=incoming.timeAnchor.valid;
   if(animateIncoming) {
    incoming.card=newCard;
    incoming.savedEntranceOpacity=newCard.layer.opacity;
    incoming.delayedEntrance=YES;
    [CATransaction begin];[CATransaction setDisableActions:YES];newCard.layer.opacity=0;[CATransaction commit];
    NB27Guard(incoming,newCard.layer);
   } else NB27End(incoming);
  }
  // Keep the native path if either card or the outgoing clock-line geometry
  // cannot be measured safely; never start the new card from a guessed point.
  if(!animateIncoming||!outgoing||!outgoing.active||!outgoing.motionOriginReady) {
   if(outgoing)NB27End(outgoing);
   if(validFrom)NB27ClearController(from);
   if(validTo)NB27ClearController(to);
   NB27BeginNativeExit(animator,context);
   NB27OriginalAnimate(animator,cmd,context);
   if(context.transitionWasCancelled&&from)NB27AbortNativeExit(from);
   return;
  }
  double nativeDuration=NB27NativeExitDuration(animator,context);
  double delay=fmax(nativeDuration,outgoing.exitDuration>0?outgoing.exitDuration:0);
  incoming.deadline=CACurrentMediaTime()+delay+NB27ScaledDuration(incoming.transitionScale)+.2;
  NB27OriginalAnimate(animator,cmd,context);
  if(context.transitionWasCancelled) { NB27End(incoming);NB27End(outgoing);return; }
  NB27AnimateExit(outgoing);
  __weak NB27Session *weakIncoming=incoming;
  __weak UIViewController *weakTo=to;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
   NB27Session *strong=weakIncoming;UIViewController *controller=weakTo;
   if(!strong||!strong.active||!controller||context.transitionWasCancelled||!NB27Enabled()) {
    NB27End(strong);return;
   }
   UIView *card=NB27Card(context,controller,YES);
   if(!NB27ValidCard(card)) { NB27End(strong);return; }
   if(card!=strong.card) {
    UIView *previous=strong.card;
    if(previous) { [CATransaction begin];[CATransaction setDisableActions:YES];previous.layer.opacity=strong.savedEntranceOpacity;[CATransaction commit]; }
    strong.card=card;strong.savedEntranceOpacity=card.layer.opacity;
    [CATransaction begin];[CATransaction setDisableActions:YES];card.layer.opacity=0;[CATransaction commit];
   }
   NB27Guard(strong,card.layer);
   NB27AnimateEntrance(strong,card);
  });
  return;
 }
 BOOL entrance=!context.isInteractive&&presenting&&validTo;
 BOOL exit=!context.isInteractive&&dismissing&&validFrom&&from!=to;
 id generation=[NSObject new];
 id previousFromGeneration=validFrom?NB27Associated(from,&NB27GenerationKey):nil;
 if(validTo)objc_setAssociatedObject(to,&NB27GenerationKey,generation,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
 if(validFrom)objc_setAssociatedObject(from,&NB27GenerationKey,generation,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
 if(dismissing&&validFrom) {
  NB27Session *pending=NB27Associated(from,&NB27PendingKey);
  BOOL matches=pending&&previousFromGeneration&&pending.transitionGeneration==previousFromGeneration&&
   CACurrentMediaTime()-pending.pendingSince<.5;
  if(matches)pending.transitionGeneration=generation;
  else if(pending)NB27End(pending);
 }
 if(context.isInteractive&&dismissing&&validFrom) {
  NB27OriginalAnimate(animator,cmd,context);
  id<UIViewControllerTransitionCoordinator> coordinator=from.transitionCoordinator;
  if(!coordinator) {
   if(context.transitionWasCancelled)NB27CancelPendingForTransition(from,generation);
   return;
  }
  if(NB27Associated(context,&NB27InteractionKey))return;
  objc_setAssociatedObject(context,&NB27InteractionKey,@YES,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  __weak id weakAnimator=animator;__weak UIViewController *weakFrom=from;
  [coordinator notifyWhenInteractionChangesUsingBlock:^(id<UIViewControllerTransitionCoordinatorContext> interaction) {
   objc_setAssociatedObject(context,&NB27InteractionKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
   dispatch_async(dispatch_get_main_queue(),^{
    id a=weakAnimator;UIViewController *c=weakFrom;
    if(!a||!c||!NB27Enabled())return;
    if(interaction.isCancelled||context.transitionWasCancelled) {
     NB27CancelPendingForTransition(c,generation);return;
    }
    if(!c.isViewLoaded||!c.view.window||objc_getAssociatedObject(c,&NB27GenerationKey)!=generation)return;
    double remaining=interaction.transitionDuration*(1-NB27Clamp(interaction.percentComplete,0,1));
    NB27Session *s=NB27PrepareExit(a,context,c,remaining);
    if(s){NB27CompactAbortExit(s.compactTicket);s.compactTicket=0;}
    NB27AnimateExit(s);
   });
  }];return;
 }
 UIView *card=entrance?NB27Card(context,to,YES):nil;
 if(entrance&&(!card||CGRectGetHeight(card.bounds)>360))entrance=NO;
 NB27Session *outgoing=exit?NB27PrepareExit(animator,context,from,-1):nil;
 NB27Session *incoming=nil;
 if(entrance) {
  NB27ClearController(to);NB27RemoveCardAnimations(card);incoming=NB27NewSession(to);
  incoming.timeAnchor=NB27CompactPrepareTimeAnchor(context.containerView);
  incoming.deadline=CACurrentMediaTime()+NB27ScaledDuration(incoming.transitionScale)+.15;
  NB27GuardPath(incoming,NB27Root(context,to,YES),context.containerView);
  NB27GuardPath(incoming,card,context.containerView);
 }
 NB27OriginalAnimate(animator,cmd,context);
 if(context.transitionWasCancelled){NB27End(incoming);NB27End(outgoing);return;}
 NB27AnimateExit(outgoing);
 if(incoming.active) {
  UIView *actual=NB27Card(context,to,YES);
  if(!NB27ValidCard(actual)){NB27End(incoming);return;}
  NB27GuardPath(incoming,actual,context.containerView);NB27AnimateEntrance(incoming,actual);
 }
}
static void NB27AddHook(CALayer *layer,SEL cmd,CAAnimation *animation,NSString *key) {
 NB27Session *s=NB27Associated(layer,&NB27OwnerKey);
 if(s.active&&!NB27Enabled())NB27End(s);
 if(s.active&&CACurrentMediaTime()<=s.deadline&&![key hasPrefix:NB27Prefix])
  animation=NB27Neutralize(animation,s.exiting);
 NB27OriginalAdd(layer,cmd,animation,key);
}
static void NB27WillDisappear(id self,SEL cmd,id presentable,id reason) {
 NB27Session *s=NB27FindSession(presentable);
 if(!s.exiting){NB27StagePending(s);NB27End(s);}
 NB27OriginalWillDisappear(self,cmd,presentable,reason);
}
static void NB27DidDisappear(id self,SEL cmd,id presentable,id reason) {
 id nativeState=NB27Associated(presentable,&NB27NativeExitKey);
 if(nativeState) {
  objc_setAssociatedObject(presentable,&NB27NativeExitKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  id<UIViewControllerContextTransitioning> context=nativeState[@"context"];
  NSUInteger ticket=[nativeState[@"ticket"] unsignedIntegerValue];
  if(context.transitionWasCancelled)NB27CompactAbortExit(ticket);
  else NB27CompactFinishExit(ticket);
 }
 NB27Session *s=NB27FindSession(presentable);
 // Native lifecycle confirmation, not the CA delegate, owns retention. Commit
 // before calling original because it may remove our animation/delegate.
 if(s.exiting&&s.transitionContext&&!s.transitionContext.transitionWasCancelled) {
  NB27CompactFinishExit(s.compactTicket);s.compactTicket=0;
 }
 NB27OriginalDidDisappear(self,cmd,presentable,reason);
 if(s.exiting)NB27End(s);
 NB27End(NB27Associated(presentable,&NB27PendingKey));
}
static void NB27CancelForObject(id object) {
 NB27AbortNativeExit(object);
 NB27Session *s=NB27FindSession(object);UIViewController *owner=s.controller;
 // A staged pending session has no current/owner lookup path. Resolve the
 // controller first so interaction can invalidate both session slots.
 if(!owner&&[object isKindOfClass:UIViewController.class])owner=object;
 if(owner){objc_setAssociatedObject(owner,&NB27GenerationKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);NB27ClearController(owner);}
 NB27End(s);
 if([object isKindOfClass:UIViewController.class]) {
  UIViewController *c=object;
  for(NSUInteger i=0;c&&i<13;i++,c=c.parentViewController) {
   objc_setAssociatedObject(c,&NB27GenerationKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
   NB27ClearController(c);
  }
 }else if([object isKindOfClass:UIView.class]) {
  UIResponder *responder=object;
  for(NSUInteger i=0;responder&&i<32;i++,responder=responder.nextResponder) {
   if([responder isKindOfClass:UIViewController.class]){NB27CancelForObject(responder);break;}
  }
 }
}
static void NB27Interaction(id self,SEL cmd,id presentable) {
 NB27CancelForObject(presentable);NB27OriginalInteraction(self,cmd,presentable);
}
static void NB27ViewInteraction(id self,SEL cmd,id controller) {
 NB27CancelForObject(controller);NB27OriginalViewInteraction(self,cmd,controller);
}
static void NB27LongLook(id self,SEL cmd,id controller) {
 NB27CancelForObject(controller);NB27OriginalLongLook(self,cmd,controller);
}
static void NB27AbortNativeExit(id object) {
 id state=NB27Associated(object,&NB27NativeExitKey);
 if(!state)return;
 NB27CompactAbortExit([state[@"ticket"] unsignedIntegerValue]);
 objc_setAssociatedObject(object,&NB27NativeExitKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static double NB27NativeExitDuration(id animator,id<UIViewControllerContextTransitioning> context) {
 SEL selector=NSSelectorFromString(@"transitionDuration:");
 if(!animator||!context||![animator respondsToSelector:selector])return .25;
 double duration=((double(*)(id,SEL,id))objc_msgSend)(animator,selector,context);
 return isfinite(duration)&&duration>0?duration:.25;
}
static void NB27BeginNativeExit(id animator,id<UIViewControllerContextTransitioning> context) {
 if(!context||context.isInteractive||!NB27UserEnabled||NB27OriginalEnabled)return;
 Class transition=NSClassFromString(@"BNBannerTransitionAnimator");
 SEL presentingSelector=NSSelectorFromString(@"isPresenting");
 BOOL replacement=NB27IsReplacementTransition(animator,context);
 if(replacement) {
  if(!NB27Enabled())return;
 } else if(!transition||![animator isKindOfClass:transition]||![animator respondsToSelector:presentingSelector]||
    ((BOOL(*)(id,SEL))objc_msgSend)(animator,presentingSelector))return;
 UIViewController *controller=[context viewControllerForKey:UITransitionContextFromViewControllerKey];
 Class presentable=NSClassFromString(@"SBNotificationPresentableViewController");
 if(!presentable||![controller isKindOfClass:presentable])return;
 NB27CompactAnchor anchor=NB27CompactPrepareTimeAnchor(context.containerView);
 if(!anchor.valid)return;
 NB27AbortNativeExit(controller);
 NSUInteger ticket=NB27CompactBeginExit(YES);if(!ticket)return;
 NSDictionary *state=@{@"ticket":@(ticket),@"context":context};
 objc_setAssociatedObject(controller,&NB27NativeExitKey,state,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
 NB27CompactAnimateExit(ticket,NB27ExitDuration(NB27NativeExitDuration(animator,context),NB27ScaledDuration(NB27TransitionScale),NB27TransitionScale));
 __weak UIViewController *weakController=controller;
 dispatch_after(dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC),dispatch_get_main_queue(),^{
  UIViewController *strong=weakController;
  if((id)NB27Associated(strong,&NB27NativeExitKey)==state) {
   if(!context.transitionWasCancelled) NB27CompactFinishExit([state[@"ticket"] unsignedIntegerValue]);
   NB27AbortNativeExit(strong);
  }
 });
}

static void NB27Reload(void) {
 CFPreferencesAppSynchronize((__bridge CFStringRef)NB27Domain);
 id value=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("BannerAnimationEnabled"),(__bridge CFStringRef)NB27Domain));
 id elasticity=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("BannerElasticity"),(__bridge CFStringRef)NB27Domain));
 id transitionScale=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("BannerTransitionScale"),(__bridge CFStringRef)NB27Domain));
 id dwellScale=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("BannerDwellScale"),(__bridge CFStringRef)NB27Domain));
 NB27UserEnabled=[value isKindOfClass:NSNumber.class]?[value boolValue]:NO;
 NB27Elasticity=[elasticity isKindOfClass:NSNumber.class]&&isfinite([elasticity doubleValue])?NB27Clamp([elasticity doubleValue],0,2):1.0;
 NB27TransitionScale=[transitionScale isKindOfClass:NSNumber.class]&&isfinite([transitionScale doubleValue])?NB27Clamp([transitionScale doubleValue],.5,2):1.0;
 NB27DwellScale=[dwellScale isKindOfClass:NSNumber.class]&&isfinite([dwellScale doubleValue])?NB27Clamp([dwellScale doubleValue],.5,3):1.0;
 // Coexistence guard only; original plugin is never loaded or modified by us.
 CFPreferencesAppSynchronize(CFSTR("com.wkk.glasssuitex.preferences"));
 id original=CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("NotificationIOS27Enabled"),CFSTR("com.wkk.glasssuitex.preferences")));
 NB27OriginalClassSeen=NSClassFromString(@"GAXIOS27BannerSession")!=Nil;
 NB27OriginalEnabled=NB27OriginalClassSeen&&[original isKindOfClass:NSNumber.class]&&[original boolValue];
 BOOL enabled=NB27Enabled();
 NB27CompactSetEnabled(NB27UserEnabled&&!NB27OriginalEnabled);
 if(!enabled)for(NB27Session *s in NB27Sessions.allObjects)NB27End(s);
 if(NB27OriginalEnabled)NSLog(@"[27banner] Original iOS27 option is enabled; standalone animation suspended to avoid double hooks.");
}
typedef void (*NB27HookMessageFn)(Class,SEL,IMP,IMP *);
static BOOL NB27DurationABICompatible(Class cls,SEL sel) {
 Method method=class_getInstanceMethod(cls,sel);if(!method||method_getNumberOfArguments(method)!=3)return NO;
 char *ret=method_copyReturnType(method);BOOL valid=ret&&ret[0]=='d';free(ret);
 char *arg=valid?method_copyArgumentType(method,2):NULL;valid=valid&&arg&&arg[0]=='@';free(arg);return valid;
}
static double NB27BannerTransitionDuration(id self,SEL cmd,id transition) {
 double duration=NB27OriginalBannerTransitionDuration(self,cmd,transition);
 if(NB27Enabled()&&isfinite(duration)&&duration>0)duration*=NB27TransitionScale;
 return duration;
}
static BOOL NB27StartTimerABICompatible(Class cls,SEL sel) {
 Method method=class_getInstanceMethod(cls,sel);if(!method||method_getNumberOfArguments(method)!=4)return NO;
 char *ret=method_copyReturnType(method);BOOL valid=ret&&ret[0]=='@';free(ret);
 char *delay=valid?method_copyArgumentType(method,2):NULL;
 valid=valid&&delay&&strcmp(delay,@encode(unsigned long long))==0;free(delay);
 char *handler=valid?method_copyArgumentType(method,3):NULL;valid=valid&&handler&&handler[0]=='@';free(handler);
 return valid;
}
static id NB27StartTimerWithDelay(id self,SEL cmd,unsigned long long delay,id handler) {
 NSDictionary *threadState=[NSThread currentThread].threadDictionary;
 NSDictionary *scope=threadState[NB27DismissScopeKey];
 if(scope[@"destination"]==self)
  delay=NB27ScaleDismissDelay(delay,[scope[@"scale"] doubleValue]);
 return NB27OriginalStartTimerWithDelay(self,cmd,delay,handler);
}
static void NB27StartDismissTimer(id self,SEL cmd) {
 NSMutableDictionary *threadState=[NSThread currentThread].threadDictionary;
 id previous=threadState[NB27DismissScopeKey];
 double scale=(NB27UserEnabled&&!NB27OriginalEnabled)?NB27DwellScale:1.0;
 threadState[NB27DismissScopeKey]=@{@"destination":self,@"scale":@(scale)};
 @try { NB27OriginalStartDismissTimer(self,cmd); }
 @finally {
  if(previous)threadState[NB27DismissScopeKey]=previous;
  else [threadState removeObjectForKey:NB27DismissScopeKey];
 }
}
static BOOL NB27Hook(Class cls,NSString *name,IMP replacement,IMP *original,BOOL *done,NSUInteger objectArguments) {
 if(*done)return YES;if(!cls)return NO;SEL sel=NSSelectorFromString(name);
 Method method=class_getInstanceMethod(cls,sel);if(!method)return NO;
 if(method_getNumberOfArguments(method)!=objectArguments+2)return NO;
 char *ret=method_copyReturnType(method);BOOL valid=ret&&ret[0]=='v';free(ret);
 for(NSUInteger i=2;valid&&i<objectArguments+2;i++) {
  char *type=method_copyArgumentType(method,(unsigned)i);valid=type&&type[0]=='@';free(type);
 }
 if(!valid){NSLog(@"[27banner] skipped incompatible ABI: %@",name);return NO;}
 NB27HookMessageFn hook=(NB27HookMessageFn)dlsym(RTLD_DEFAULT,"MSHookMessageEx");if(!hook)return NO;
 // Mark before hooking: retries must never store our replacement as original.
 *done=YES;hook(cls,sel,replacement,original);return YES;
}
static void NB27Install(void) {
 static BOOL animateDone=NO,layerDone=NO,willDone=NO,didDone=NO;
 static BOOL interactionDone=NO,viewInteractionDone=NO,longLookDone=NO;
 Class animator=NSClassFromString(@"BNBannerAnimator");
 Class destination=NSClassFromString(@"SBNotificationBannerDestination");
 Class bannerTransition=NSClassFromString(@"BNBannerTransitionAnimator");
 SEL durationSelector=NSSelectorFromString(@"transitionDuration:");
 if(!NB27BannerTransitionDurationDone&&bannerTransition&&NB27DurationABICompatible(bannerTransition,durationSelector)) {
  NB27HookMessageFn hook=(NB27HookMessageFn)dlsym(RTLD_DEFAULT,"MSHookMessageEx");
  if(hook){NB27BannerTransitionDurationDone=YES;hook(bannerTransition,durationSelector,(IMP)NB27BannerTransitionDuration,(IMP *)&NB27OriginalBannerTransitionDuration);}
 }
 NB27HookMessageFn timerHook=(NB27HookMessageFn)dlsym(RTLD_DEFAULT,"MSHookMessageEx");
 if(timerHook&&destination) {
  if(!NB27DismissTimerDone) {
   Method method=class_getInstanceMethod(destination,NSSelectorFromString(@"_startDismissTimer"));
   if(method&&method_getNumberOfArguments(method)==2) {
    char *ret=method_copyReturnType(method);BOOL valid=ret&&ret[0]=='v';free(ret);
    if(valid){NB27DismissTimerDone=YES;timerHook(destination,NSSelectorFromString(@"_startDismissTimer"),(IMP)NB27StartDismissTimer,(IMP *)&NB27OriginalStartDismissTimer);}
   }
  }
  SEL timerSelector=NSSelectorFromString(@"_startTimerWithDelay:eventHandler:");
  if(!NB27StartTimerWithDelayDone&&NB27StartTimerABICompatible(destination,timerSelector)) {
   NB27StartTimerWithDelayDone=YES;
   timerHook(destination,timerSelector,(IMP)NB27StartTimerWithDelay,(IMP *)&NB27OriginalStartTimerWithDelay);
  }
 }
 NB27Hook(CALayer.class,@"addAnimation:forKey:",(IMP)NB27AddHook,(IMP *)&NB27OriginalAdd,&layerDone,2);
 // Do not enter the custom transition path before the layer guard is installed.
 if(layerDone)NB27Hook(animator,@"animateTransition:",(IMP)NB27AnimateHook,(IMP *)&NB27OriginalAnimate,&animateDone,1);
 NB27Hook(destination,@"presentableWillDisappearAsBanner:withReason:",(IMP)NB27WillDisappear,(IMP *)&NB27OriginalWillDisappear,&willDone,2);
 NB27Hook(destination,@"presentableDidDisappearAsBanner:withReason:",(IMP)NB27DidDisappear,(IMP *)&NB27OriginalDidDisappear,&didDone,2);
 NB27Hook(destination,@"userInteractionWillBeginForBannerForPresentable:",(IMP)NB27Interaction,(IMP *)&NB27OriginalInteraction,&interactionDone,1);
 NB27Hook(destination,@"notificationViewControllerWillBeginUserInteraction:",(IMP)NB27ViewInteraction,(IMP *)&NB27OriginalViewInteraction,&viewInteractionDone,1);
 NB27Hook(destination,@"longLookWillPresentForNotificationViewController:",(IMP)NB27LongLook,(IMP *)&NB27OriginalLongLook,&longLookDone,1);
 static BOOL reported=NO;
 if(animateDone&&layerDone&&!reported){reported=YES;NSLog(@"[27banner] animation hooks installed (not a visual verification)");}
}
__attribute__((constructor)) static void NB27Initialize(void) {
 @autoreleasepool {
  if(![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"])return;
  NSOperatingSystemVersion version=NSProcessInfo.processInfo.operatingSystemVersion;
  if(version.majorVersion<15||version.majorVersion>=18)return;
  dispatch_async(dispatch_get_main_queue(),^{
   NB27Sessions=[NSHashTable weakObjectsHashTable];NB27Reload();NB27Install();
   static int token=-1,originalToken=-1;
   notify_register_dispatch("com.ning.ios2627anims.changed",&token,dispatch_get_main_queue(),^(int t){(void)t;NB27Reload();});
   notify_register_dispatch("com.wkk.glasssuitex.preferences.changed",&originalToken,dispatch_get_main_queue(),^(int t){(void)t;NB27Reload();});
   [NSNotificationCenter.defaultCenter addObserverForName:UIAccessibilityReduceMotionStatusDidChangeNotification
    object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){(void)note;NB27Reload();}];
   // Bounded delayed loading recovery; every hook has an independent once flag.
   for(int i=1;i<=10;i++)dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)i*NSEC_PER_SEC),dispatch_get_main_queue(),^{NB27Reload();NB27Install();});
  });
 }
}
