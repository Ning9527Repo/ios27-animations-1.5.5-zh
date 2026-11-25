#import "Bridge.h"
#import "../../../shared/LiquidSwitchConfiguration.h"
#import <dlfcn.h>
#include <unistd.h>
#include <limits.h>
#include <stdlib.h>

void NGSwitchFeatureDiagnostic(NSString *event, NSString *detail) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ NGSwitchFeatureDiagnostic(event, detail); });
        return;
    }
    static NSMutableDictionary<NSString *, NSString *> *last;
    if (!last) last = [NSMutableDictionary dictionary];
    if ([last[event] isEqualToString:detail]) return;
    last[event] = detail ?: @"";
    NSString *message = [NSString stringWithFormat:@"%.3f pid=%d host=%@ %@ %@\n",
        CFAbsoluteTimeGetCurrent(), getpid(), NSBundle.mainBundle.bundleIdentifier ?: @"unknown", event, detail ?: @""];
    NSLog(@"[iOS27Switch] %@", message);
    // Per-host metadata only; no screen capture, user text or global log permission.
    NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches/iOS27Animations-switch.log"];
    NSData *data = [message dataUsingEncoding:NSUTF8StringEncoding];
    @try {
        NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:path error:NULL];
        if (!attributes || [attributes[NSFileSize] unsignedLongLongValue] > 65536) {
            [data writeToFile:path atomically:YES];
        } else {
            NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:path];
            [file seekToEndOfFile]; [file writeData:data]; [file closeFile];
        }
    } @catch (__unused NSException *exception) {}
}

static int NGAcquireSwitchConfigurationAccess(void) {
    typedef int (*ApplyProfile)(const char *);
    static ApplyProfile apply;
    static void *handle;
    if (!apply) apply = (ApplyProfile)dlsym(RTLD_DEFAULT, "libSandy_applyProfile");
    if (!apply) {
        Dl_info image = {0};
        if (dladdr((const void *)&NGAcquireSwitchConfigurationAccess, &image) && image.dli_fname) {
            char resolved[PATH_MAX] = {0};
            NSString *path = [NSString stringWithUTF8String:realpath(image.dli_fname, resolved) ?: image.dli_fname];
            for (NSString *suffix in @[@"/Library/MobileSubstrate/DynamicLibraries/", @"/usr/lib/TweakInject/"]) {
                NSRange range = [path rangeOfString:suffix options:NSBackwardsSearch];
                if (range.location == NSNotFound) continue;
                NSString *library = [[path substringToIndex:range.location] stringByAppendingString:@"/usr/lib/libsandy.dylib"];
                handle = dlopen(library.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
                if (handle) break;
            }
        }
        if (!handle) handle = dlopen("/usr/lib/libsandy.dylib", RTLD_NOW | RTLD_LOCAL);
        if (handle) apply = (ApplyProfile)dlsym(handle, "libSandy_applyProfile");
    }
    return apply ? apply("iOS27Animations_SwitchReadConfig") : -1;
}

BOOL NGLoadSwitchFeaturePreference(BOOL *enabled) {
    // All calls are serialized on the main queue; getters/hooks only read the atomic cache.
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfFile:CG27LSConfigurationPath options:0 error:&error];
    static CFAbsoluteTime lastGrantAttempt = -100;
    static int grantStatus = -2;
    if (!data) {
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if (now - lastGrantAttempt >= 5) {
            lastGrantAttempt = now;
            grantStatus = NGAcquireSwitchConfigurationAccess();
        }
        error = nil;
        data = [NSData dataWithContentsOfFile:CG27LSConfigurationPath options:0 error:&error];
    }
    BOOL value = NO;
    if (!data || !CG27LSDecodeSnapshot(data, &value, &error)) {
        NGSwitchFeatureDiagnostic(@"configuration-unavailable",
            [NSString stringWithFormat:@"grant=%d error=%@:%ld retaining-last-valid-state",
                grantStatus, error.domain ?: @"missing", (long)error.code]);
        return NO;
    }
    if (enabled) *enabled = value;
    NGSwitchFeatureDiagnostic(@"configuration-loaded",
        [NSString stringWithFormat:@"enabled=%d grant=%d source=shared-snapshot", value, grantStatus]);
    return YES;
}

void NGPublishSwitchPreferenceIfTrusted(void) {
    NSString *host = NSBundle.mainBundle.bundleIdentifier;
    if (![host isEqualToString:@"com.apple.springboard"]) return;
    NSError *error = nil;
    BOOL success = CG27LSPublishSavedPreference(&error);
    NGSwitchFeatureDiagnostic(@"configuration-publish",
        success ? @"saved-setting-published" : [NSString stringWithFormat:@"%@:%ld", error.domain, (long)error.code]);
}
