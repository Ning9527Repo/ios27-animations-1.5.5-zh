#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSBundle * _Nullable NGBundleResources(void);
FOUNDATION_EXPORT BOOL NGSwitchFeatureEnabled(void);
FOUNDATION_EXPORT void NGRemoveAllSwitches(void);
FOUNDATION_EXPORT void NGRefreshSwitch(UISwitch *source);
FOUNDATION_EXPORT void NGSyncSwitchGeometry(UISwitch *source);
FOUNDATION_EXPORT void NGRemoveSwitch(UISwitch *source);
FOUNDATION_EXPORT void NGScheduleSwitchSync(UISwitch *source);
FOUNDATION_EXPORT void NGClockResetAlarmCell(UIView *view);
FOUNDATION_EXPORT void NGClockScheduleReplay(UITableView * _Nullable table);
FOUNDATION_EXPORT BOOL NGClockHasSwitchOverlay(UISwitch *source);
FOUNDATION_EXPORT BOOL NGHandleSwitchAlpha(UISwitch *source, CGFloat alpha);

@protocol NGSwitchComponent <NSObject>
@property(nonatomic,copy,nullable) void (^onChanged)(BOOL value);
@property(nonatomic,getter=isOn) BOOL on;
- (BOOL)clockTouchActive;
- (void)resetForClockReuse:(BOOL)value;
- (void)replayClockTransition:(BOOL)value;
- (void)setOn:(BOOL)value animated:(BOOL)animated;
@end
NS_ASSUME_NONNULL_END
