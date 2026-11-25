#import <Foundation/Foundation.h>
#import "shared/LiquidSwitchConfiguration.h"
#include <sys/stat.h>
#include <stdatomic.h>

static int checks;
#define REQUIRE(x) do { checks++; if (!(x)) { NSLog(@"FAIL %s:%d %s", __FILE__, __LINE__, #x); abort(); } } while (0)

// Test the exact production apply function, with only rendering/IO replaced.
static _Atomic(BOOL) gNGSwitchFeatureEnabled = NO;
static BOOL gNGHasValidSwitchConfiguration = NO;
static BOOL readable, incoming;
static int refreshed, removed;
static BOOL NGLoadSwitchFeaturePreference(BOOL *value) {
    if (!readable) return NO;
    *value = incoming;
    return YES;
}
static void NGRemoveAllSwitches(void) { removed++; }
static void NGRefreshVisibleSwitches(void) { refreshed++; }
/* PRODUCTION_APPLY */

static NSData *encode(id value) {
    return [NSPropertyListSerialization dataWithPropertyList:value format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc == 4) {
            NSString *path = @(argv[2]);
            BOOL value = strcmp(argv[3], "1") == 0;
            if (!strcmp(argv[1], "write")) REQUIRE(CG27LSWriteSnapshot(path, value, NULL));
            else { BOOL read = !value; REQUIRE(CG27LSReadSnapshot(path, &read, NULL)); REQUIRE(read == value); }
            return 0;
        }
        BOOL value = YES;
        REQUIRE(!CG27LSDecodeBoolean(nil, &value) && value);
        REQUIRE(!CG27LSDecodeBoolean(@"1", &value) && value);
        REQUIRE(!CG27LSDecodeBoolean(@2, &value) && value);
        REQUIRE(!CG27LSDecodeBoolean(@(-1), &value) && value);
        REQUIRE(!CG27LSDecodeBoolean(@(NAN), &value) && value);
        REQUIRE(CG27LSDecodeBoolean(@NO, &value) && !value);
        REQUIRE(CG27LSDecodeBoolean(@YES, &value) && value);
        REQUIRE(CG27LSDecodeBoolean(@0, &value) && !value);
        REQUIRE(CG27LSDecodeBoolean(@1, &value) && value);
        for (id invalid in @[@[], @{}, @{@"Schema":@2,@"LiquidSwitchEnabled":@YES},
                              @{@"Schema":@1,@"LiquidSwitchEnabled":@"true"},
                              @{@"Schema":@1,@"LiquidSwitchEnabled":@2}]) {
            value = YES;
            REQUIRE(!CG27LSDecodeSnapshot(encode(invalid), &value, NULL));
            REQUIRE(value);
        }
        value = YES;
        REQUIRE(!CG27LSDecodeSnapshot([@"broken" dataUsingEncoding:NSUTF8StringEncoding], &value, NULL));
        REQUIRE(value);
        REQUIRE(!CG27LSDecodeSnapshot([NSMutableData dataWithLength:4097], &value, NULL));
        REQUIRE(value);
        for (NSNumber *state in @[@NO,@YES]) {
            for (NSNumber *format in @[@(NSPropertyListXMLFormat_v1_0),@(NSPropertyListBinaryFormat_v1_0)]) {
                NSData *data = [NSPropertyListSerialization dataWithPropertyList:@{@"Schema":@1,@"LiquidSwitchEnabled":state}
                    format:format.unsignedIntegerValue options:0 error:NULL];
                REQUIRE(CG27LSDecodeSnapshot(data, &value, NULL));
                REQUIRE(value == state.boolValue);
            }
        }
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSString *path = [dir stringByAppendingPathComponent:@"nested/switch.plist"];
        REQUIRE(CG27LSWriteSnapshot(path, YES, NULL));
        REQUIRE(CG27LSReadSnapshot(path, &value, NULL) && value);
        struct stat st;
        REQUIRE(!stat(path.fileSystemRepresentation, &st) && (st.st_mode & 0777) == 0644);
        chmod(path.fileSystemRepresentation, 0600);
        REQUIRE(CG27LSWriteSnapshot(path, YES, NULL));
        REQUIRE(!stat(path.fileSystemRepresentation, &st) && (st.st_mode & 0777) == 0644);
        REQUIRE(CG27LSWriteSnapshot(path, NO, NULL));
        REQUIRE(CG27LSReadSnapshot(path, &value, NULL) && !value);
        REQUIRE(!CG27LSWriteSnapshot(dir, YES, NULL));
        REQUIRE(CG27LSReadSnapshot(path, &value, NULL) && !value);
        [NSFileManager.defaultManager removeItemAtPath:dir error:NULL];

        readable = NO;
        NGApplySwitchFeaturePreference();
        REQUIRE(!gNGHasValidSwitchConfiguration && !gNGSwitchFeatureEnabled && !refreshed && !removed);
        readable = YES; incoming = YES;
        NGApplySwitchFeaturePreference();
        REQUIRE(gNGHasValidSwitchConfiguration && gNGSwitchFeatureEnabled && refreshed == 1 && !removed);
        readable = NO;
        for (int i=0; i<20; i++) NGApplySwitchFeaturePreference();
        REQUIRE(gNGSwitchFeatureEnabled && refreshed == 1 && !removed);
        readable = YES; incoming = YES;
        NGApplySwitchFeaturePreference();
        REQUIRE(gNGSwitchFeatureEnabled && refreshed == 1 && !removed);
        incoming = NO;
        NGApplySwitchFeaturePreference();
        REQUIRE(!gNGSwitchFeatureEnabled && removed == 1);
        readable = NO;
        NGApplySwitchFeaturePreference();
        REQUIRE(!gNGSwitchFeatureEnabled && removed == 1);
        readable = YES; incoming = YES;
        NGApplySwitchFeaturePreference();
        REQUIRE(gNGSwitchFeatureEnabled && refreshed == 2 && removed == 1);
        printf("PASS %d production snapshot / apply assertions (Foundation stand-in, no UIKit claim)\n", checks);
    }
    return 0;
}
