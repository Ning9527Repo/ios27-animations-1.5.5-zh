#import "Bridge.h"
#import <dlfcn.h>
#import <stdlib.h>
#import <unistd.h>

static char kNGResourceAnchor;

static NSString *NGInstallPrefix(void) {
    Dl_info info = {0};
    if (!dladdr(&kNGResourceAnchor, &info) || !info.dli_fname) return nil;
    char resolved[PATH_MAX] = {0};
    const char *raw = realpath(info.dli_fname, resolved) ?: info.dli_fname;
    NSString *path = [NSString stringWithUTF8String:raw];
    for (NSString *suffix in @[@"/Library/MobileSubstrate/DynamicLibraries/iOS2627Anims.dylib",
                               @"/usr/lib/TweakInject/iOS2627Anims.dylib"]) {
        if ([path hasSuffix:suffix]) return [path substringToIndex:path.length-suffix.length];
    }
    return nil;
}

NSBundle *NGBundleResources(void) {
#ifdef NG_TESTING
    NSString *test = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"TheseusSwitchResources.bundle"];
    if ([NSFileManager.defaultManager fileExistsAtPath:test]) return [NSBundle bundleWithPath:test];
#endif
    NSString *prefix = NGInstallPrefix();
    if (!prefix) return nil;
    NSString *path = [prefix stringByAppendingPathComponent:@"Library/Application Support/iOS27Animations/TheseusSwitchResources.bundle"];
    return [NSBundle bundleWithPath:path];
}


