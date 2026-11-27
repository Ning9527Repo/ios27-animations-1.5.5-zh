#pragma once
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <math.h>
#import <dlfcn.h>
#include <limits.h>
#include <stdlib.h>

static NSString *const CG27LSConfigurationPath = @"/var/mobile/Library/Accessibility/iOS27Animations-switch.plist";
static NSString *const CG27LSDomain = @"com.ning.ios2627anims";
static NSString *const CG27LSChanged = @"com.ning.ios2627anims/changed";

static inline NSError *CG27LSError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"iOS27Animations.SwitchConfiguration" code:code
                          userInfo:@{NSLocalizedDescriptionKey:message}];
}

// Never turn an unreadable/malformed value into an authoritative OFF update.
static inline BOOL CG27LSDecodeBoolean(id value, BOOL *outValue) {
    if (![value isKindOfClass:NSNumber.class]) return NO;
    double number = [value doubleValue];
    if (!isfinite(number) || (number != 0 && number != 1)) return NO;
    if (outValue) *outValue = [value boolValue];
    return YES;
}

static inline BOOL CG27LSDecodeSnapshot(NSData *data, BOOL *enabled, NSError **error) {
    if (!data || data.length > 4096) {
        if (error) *error = CG27LSError(1, @"missing-or-oversized-snapshot");
        return NO;
    }
    id envelope = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable
                                                            format:NULL error:error];
    if (![envelope isKindOfClass:NSDictionary.class] ||
        ![envelope[@"Schema"] isKindOfClass:NSNumber.class] ||
        ![envelope[@"Schema"] isEqual:@1] ||
        !CG27LSDecodeBoolean(envelope[@"LiquidSwitchEnabled"], enabled)) {
        if (error && !*error) *error = CG27LSError(2, @"invalid-switch-snapshot");
        return NO;
    }
    return YES;
}

static inline BOOL CG27LSReadSnapshot(NSString *path, BOOL *enabled, NSError **error) {
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:error];
    return data && CG27LSDecodeSnapshot(data, enabled, error);
}

static inline BOOL CG27LSWriteSnapshot(NSString *path, BOOL enabled, NSError **error) {
    NSFileManager *manager = NSFileManager.defaultManager;
    if (![manager createDirectoryAtPath:path.stringByDeletingLastPathComponent
            withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    BOOL existing = NO;
    if (CG27LSReadSnapshot(path, &existing, NULL) && existing == enabled)
        return [manager setAttributes:@{NSFilePosixPermissions:@0644} ofItemAtPath:path error:error];
    NSDictionary *envelope = @{@"Schema":@1, @"LiquidSwitchEnabled":@(enabled)};
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:envelope
                        format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
    if (!data || ![data writeToFile:path options:NSDataWritingAtomic error:error]) return NO;
    return [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0644}
                                          ofItemAtPath:path error:error];
}

// Resolve the saved plist beside this tweak/prefs image before consulting cfprefsd.
// RootHide redirects /var/mobile into jbroot, so a guessed global path is insufficient.
static inline id CG27LSSavedValueFromImage(const void *anchor) {
    Dl_info image = {0};
    if (!dladdr(anchor, &image) || !image.dli_fname) return nil;
    char resolved[PATH_MAX] = {0};
    NSString *path = [NSString stringWithUTF8String:realpath(image.dli_fname, resolved) ?: image.dli_fname];
    for (NSString *marker in @[@"/Library/MobileSubstrate/DynamicLibraries/", @"/usr/lib/TweakInject/",
                               @"/Library/PreferenceBundles/"]) {
        NSRange range = [path rangeOfString:marker options:NSBackwardsSearch];
        if (range.location == NSNotFound) continue;
        NSString *saved = [[path substringToIndex:range.location] stringByAppendingFormat:
                          @"/var/mobile/Library/Preferences/%@.plist", CG27LSDomain];
        NSData *data = [NSData dataWithContentsOfFile:saved];
        id dictionary = data ? [NSPropertyListSerialization propertyListWithData:data
                                    options:NSPropertyListImmutable format:NULL error:NULL] : nil;
        if ([dictionary isKindOfClass:NSDictionary.class]) {
            id value = dictionary[@"LiquidSwitchEnabled"];
            if (value) return value;
        }
    }
    return nil;
}

static inline BOOL CG27LSPublishValue(BOOL enabled, NSError **error) {
    if (!CG27LSWriteSnapshot(CG27LSConfigurationPath, enabled, error)) return NO;
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                        (__bridge CFStringRef)CG27LSChanged, NULL, NULL, YES);
    return YES;
}

// Called only by Settings and SpringBoard. Sandboxed consumers never read this domain.
static inline BOOL CG27LSPublishSavedPreference(NSError **error) {
    NSString *host = NSBundle.mainBundle.bundleIdentifier;
    if (![host isEqualToString:@"com.apple.Preferences"] &&
        ![host isEqualToString:@"com.apple.springboard"]) {
        if (error) *error = CG27LSError(3, @"publisher-not-authorized");
        return NO;
    }
    CFPreferencesAppSynchronize((__bridge CFStringRef)CG27LSDomain);
    id value = CG27LSSavedValueFromImage((const void *)&CG27LSPublishSavedPreference);
    if (!value) value = CFBridgingRelease(CFPreferencesCopyAppValue(CFSTR("LiquidSwitchEnabled"),
                                                                (__bridge CFStringRef)CG27LSDomain));
    BOOL enabled = NO;
    if (value && !CG27LSDecodeBoolean(value, &enabled)) {
        if (error) *error = CG27LSError(4, @"invalid-saved-switch-value");
        return NO;
    }
    // Missing reads in either publisher must not replace a previous valid ON/OFF.
    if (!value) {
        BOOL published = NO;
        if (CG27LSReadSnapshot(CG27LSConfigurationPath, &published, NULL)) return YES;
        if (error) *error = CG27LSError(5, @"saved-value-not-available-yet");
        return NO;
    }
    return CG27LSPublishValue(enabled, error);
}
