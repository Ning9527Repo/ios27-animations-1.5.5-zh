#import "CG27PageController.h"

@interface CG27KeyboardGlassController : CG27PageController
- (id)readPreferenceValue:(PSSpecifier *)specifier;
@property(nonatomic, strong) NSMutableArray *ngSpecifiers;
@property(nonatomic, assign) BOOL ngLoading;
@property(nonatomic, strong) id ngActiveObserver;
- (void)ngRebuildSpecifierState;
- (void)ngRefreshVisibleSettings;
- (void)changed;
- (void)resetCurrentSkin;
- (void)resetAll;
@end
