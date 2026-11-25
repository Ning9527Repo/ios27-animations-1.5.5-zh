#import "CG27PageController.h"

@interface CG27KeyboardGlassController : CG27PageController
@property(nonatomic, strong) NSArray *ngSpecifiers;
@property(nonatomic, assign) BOOL ngLoading;
@property(nonatomic, strong) id ngActiveObserver;
- (void)ngRebuildSpecifierState;
- (void)ngRefreshVisibleSettings;
- (void)changed;
- (void)resetCurrentSkin;
- (void)resetAll;
@end
