#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import "../../shared/LiquidSwitchConfiguration.h"
#import "CG27PageController.h"
#include <spawn.h>
#include <unistd.h>

static NSString *const kCG27Domain = @"com.bazik1337.ios2627anims";

@interface PSListController (CG27)
- (NSArray *)loadSpecifiersFromPlistName:(NSString *)name target:(id)target bundle:(NSBundle *)bundle;
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier;
- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath;
@end

static void CG27PublishLiquidSwitchPreference(void) {
    NSError *error = nil;
    if (!CG27LSPublishSavedPreference(&error))
        NSLog(@"[iOS27Switch] Settings publish failed: %@:%ld", error.domain, (long)error.code);
}

static NSString *CG27L(NSString *key) {
    return [[NSBundle bundleWithIdentifier:@"com.bazik1337.ios2627anims.prefs"] localizedStringForKey:key value:key table:@"Root"];
}

static UIColor *CG27Tint(void) {
    return [UIColor colorWithRed:0.40 green:0.35 blue:0.98 alpha:1];
}

// All pages share this controller. Tint each actual slider, rather than
// recolouring every control or inheriting the page's purple tint.
static void CG27ApplySliderTint(UIView *view) {
    if ([view isKindOfClass:UISlider.class]) {
        UISlider *slider = (UISlider *)view;
        slider.tintColor = UIColor.systemBlueColor;
        slider.minimumTrackTintColor = UIColor.systemBlueColor;
    }
    for (UIView *child in view.subviews) CG27ApplySliderTint(child);
}

@implementation CG27PageController

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSString *plist = [self.specifier propertyForKey:@"plist"] ?: @"Root";
        _specifiers = [[self loadSpecifiersFromPlistName:plist target:self
                                                  bundle:[NSBundle bundleForClass:self.class]] mutableCopy];
    }
    return _specifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.tintColor = CG27Tint();
    [UISwitch appearanceWhenContainedInInstancesOfClasses:@[self.class]].onTintColor = CG27Tint();
    [UISlider appearanceWhenContainedInInstancesOfClasses:@[self.class]].minimumTrackTintColor = UIColor.systemBlueColor;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];
    if (![[specifier propertyForKey:@"key"] isEqualToString:@"LiquidSwitchEnabled"] ||
        ![[specifier propertyForKey:@"defaults"] isEqualToString:CG27LSDomain]) return;
    CFPreferencesAppSynchronize((__bridge CFStringRef)CG27LSDomain);
    BOOL enabled = NO;
    if (!CG27LSDecodeBoolean(value, &enabled)) return;
    NSError *error = nil;
    if (!CG27LSPublishValue(enabled, &error))
        NSLog(@"[iOS27Switch] Settings save publish failed: %@:%ld", error.domain, (long)error.code);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    CG27PublishLiquidSwitchPreference();
    self.navigationController.navigationBar.tintColor = CG27Tint();
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.navigationController.navigationBar.tintColor = nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    PSSpecifier *spec = [cell respondsToSelector:@selector(specifier)] ? [(id)cell specifier] : nil;
    if ([spec propertyForKey:@"action"]) cell.textLabel.textColor = UIColor.labelColor;
    CG27ApplySliderTint(cell.contentView);
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([PSListController instancesRespondToSelector:_cmd])
        [super tableView:tableView willDisplayCell:cell forRowAtIndexPath:indexPath];
    CG27ApplySliderTint(cell.contentView);
}

@end

@interface CG27RootListController : CG27PageController
@end

@implementation CG27RootListController

- (void)viewDidLoad {
    [super viewDidLoad];
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 104)];
    UILabel *title = [UILabel new];
    title.text = CG27L(@"iOS 27 Animations");
    title.font = [UIFont systemFontOfSize:30 weight:UIFontWeightBold];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:title];
    [title.centerXAnchor constraintEqualToAnchor:header.centerXAnchor].active = YES;
    [title.topAnchor constraintEqualToAnchor:header.topAnchor constant:28].active = YES;
    self.table.tableHeaderView = header;
}

- (void)resetSettings {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:CG27L(@"Reset settings?")
        message:CG27L(@"All settings return to defaults.") preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:CG27L(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:CG27L(@"Reset") style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        [self performReset];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)performReset {
    CFStringRef domain = (__bridge CFStringRef)kCG27Domain;
    CFArrayRef stored = CFPreferencesCopyKeyList(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (stored) {
        for (NSString *key in (__bridge NSArray *)stored)
            if (![key isEqualToString:@"Enabled"] && ![key isEqualToString:@"PromptStage"]) CFPreferencesSetAppValue((__bridge CFStringRef)key, NULL, domain);
        CFRelease(stored);
    }
    CFPreferencesAppSynchronize(domain);
    NSError *error = nil;
    if (!CG27LSPublishValue(NO, &error))
        NSLog(@"[iOS27Switch] Reset publish failed: %@:%ld", error.domain, (long)error.code);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("com.bazik1337.ios2627anims/changed"), NULL, NULL, YES);
    [self reloadSpecifiers];
}

- (void)respring {
    for (NSString *tool in @[@"/var/jb/usr/bin/sbreload", @"/usr/bin/sbreload", @"/var/jb/usr/bin/killall", @"/usr/bin/killall"]) {
        if (access(tool.fileSystemRepresentation, X_OK) != 0) continue;
        BOOL killall = [tool hasSuffix:@"killall"];
        const char *argv[] = {tool.fileSystemRepresentation, killall ? "SpringBoard" : NULL, NULL};
        pid_t pid;
        if (posix_spawn(&pid, argv[0], NULL, NULL, (char *const *)argv, NULL) == 0) return;
    }
}

@end
