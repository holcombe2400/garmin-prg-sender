#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import <objc/runtime.h>

static NSString * const GCBDir = @"/var/mobile/Documents/GarminConnectBypass";
static NSString * const GCBLogPath = @"/var/mobile/Documents/GarminConnectBypass/live.log";
static uintptr_t (*origDeviceAttributesProductNumber)(id, SEL);
static uintptr_t (*origDeviceAttributesSoftwareVersion)(id, SEL);
static unsigned short (*origMessageProductNumber)(id, SEL);
static unsigned short (*origMessageProtocolVersion)(id, SEL);
static unsigned short (*origMessageSoftwareVersion)(id, SEL);
static void (*origCancelPeripheralConnection)(id, SEL, id);
static NSString *(*origLocalizedString)(id, SEL, NSString *, NSString *, NSString *);
static id (*origAlertController)(id, SEL, NSString *, NSString *, NSInteger);

void *memset(void *ptr, int value, unsigned long count) {
    unsigned char *p = (unsigned char *)ptr;
    while (count--) *p++ = (unsigned char)value;
    return ptr;
}

static BOOL GCBFileExists(NSString *name) {
    NSString *path = [GCBDir stringByAppendingPathComponent:name];
    return [[NSFileManager defaultManager] fileExistsAtPath:path];
}

static void GCBLog(NSString *format, ...) {
    @autoreleasepool {
        [[NSFileManager defaultManager] createDirectoryAtPath:GCBDir withIntermediateDirectories:YES attributes:nil error:nil];
        va_list args;
        va_start(args, format);
        NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
        va_end(args);
        NSDateFormatter *formatter = [NSDateFormatter new];
        formatter.dateFormat = @"HH:mm:ss.SSS";
        NSString *line = [NSString stringWithFormat:@"%@  %@\n", [formatter stringFromDate:[NSDate date]], message];
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        if (![[NSFileManager defaultManager] fileExistsAtPath:GCBLogPath]) {
            [data writeToFile:GCBLogPath atomically:YES];
            return;
        }
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:GCBLogPath];
        [handle seekToEndOfFile];
        [handle writeData:data];
        [handle closeFile];
    }
}

static NSString *GCBStack(void) {
    NSArray *stack = [NSThread callStackSymbols];
    NSUInteger count = MIN((NSUInteger)18, stack.count);
    return [[stack subarrayWithRange:NSMakeRange(0, count)] componentsJoinedByString:@" | "];
}

static BOOL GCBInterestingText(NSString *text) {
    NSString *lower = [text lowercaseString] ?: @"";
    return [lower containsString:@"not supported"] ||
           [lower containsString:@"unsupported"] ||
           [lower containsString:@"upgrade"] ||
           [lower containsString:@"update"] ||
           [lower containsString:@"compatible"] ||
           [lower containsString:@"fenix"];
}

static uintptr_t GCBDeviceAttributesProductNumber(id self, SEL _cmd) {
    uintptr_t value = origDeviceAttributesProductNumber ? origDeviceAttributesProductNumber(self, _cmd) : 0;
    if (GCBFileExists(@"spoof_product") && value == 3290) {
        GCBLog(@"DeviceAttributes.productNumber spoof %@ %lu -> 3113 stack=%@", self, (unsigned long)value, GCBStack());
        return 3113;
    }
    GCBLog(@"DeviceAttributes.productNumber %@ -> %lu", self, (unsigned long)value);
    return value;
}

static uintptr_t GCBDeviceAttributesSoftwareVersion(id self, SEL _cmd) {
    uintptr_t value = origDeviceAttributesSoftwareVersion ? origDeviceAttributesSoftwareVersion(self, _cmd) : 0;
    if (GCBFileExists(@"spoof_software") && value == 2802) {
        GCBLog(@"DeviceAttributes.softwareVersion spoof %@ %lu -> 1000", self, (unsigned long)value);
        return 1000;
    }
    GCBLog(@"DeviceAttributes.softwareVersion %@ -> %lu", self, (unsigned long)value);
    return value;
}

static unsigned short GCBMessageProductNumber(id self, SEL _cmd) {
    unsigned short value = origMessageProductNumber ? origMessageProductNumber(self, _cmd) : 0;
    if (GCBFileExists(@"spoof_product") && value == 3290) {
        GCBLog(@"DeviceInfoRequest.productNumber spoof %@ %u -> 3113 stack=%@", self, value, GCBStack());
        return 3113;
    }
    GCBLog(@"DeviceInfoRequest.productNumber %@ -> %u", self, value);
    return value;
}

static unsigned short GCBMessageProtocolVersion(id self, SEL _cmd) {
    unsigned short value = origMessageProtocolVersion ? origMessageProtocolVersion(self, _cmd) : 0;
    if (GCBFileExists(@"spoof_protocol") && value == 150) {
        GCBLog(@"DeviceInfoRequest.protocolVersion spoof %@ %u -> 100", self, value);
        return 100;
    }
    GCBLog(@"DeviceInfoRequest.protocolVersion %@ -> %u", self, value);
    return value;
}

static unsigned short GCBMessageSoftwareVersion(id self, SEL _cmd) {
    unsigned short value = origMessageSoftwareVersion ? origMessageSoftwareVersion(self, _cmd) : 0;
    if (GCBFileExists(@"spoof_software") && value == 2802) {
        GCBLog(@"DeviceInfoRequest.softwareVersion spoof %@ %u -> 1000", self, value);
        return 1000;
    }
    GCBLog(@"DeviceInfoRequest.softwareVersion %@ -> %u", self, value);
    return value;
}

static void GCBCancelPeripheralConnection(id self, SEL _cmd, id peripheral) {
    NSString *desc = [peripheral description] ?: @"<nil>";
    NSString *name = nil;
    if ([peripheral respondsToSelector:@selector(name)]) {
        name = [peripheral performSelector:@selector(name)];
    }
    GCBLog(@"CBCentralManager.cancelPeripheralConnection name=%@ desc=%@ stack=%@", name, desc, GCBStack());
    if (GCBFileExists(@"suppress_cancel") && [name containsString:@"fenix 6"]) {
        GCBLog(@"Suppressed CoreBluetooth cancel for %@", name);
        return;
    }
    if (origCancelPeripheralConnection) origCancelPeripheralConnection(self, _cmd, peripheral);
}

static NSString *GCBLocalizedString(id self, SEL _cmd, NSString *key, NSString *value, NSString *table) {
    NSString *result = origLocalizedString ? origLocalizedString(self, _cmd, key, value, table) : value;
    if (GCBInterestingText(key) || GCBInterestingText(result)) {
        GCBLog(@"localized key=%@ table=%@ result=%@ stack=%@", key, table, result, GCBStack());
    }
    return result;
}

static id GCBAlertController(id self, SEL _cmd, NSString *title, NSString *message, NSInteger style) {
    if (GCBInterestingText(title) || GCBInterestingText(message)) {
        GCBLog(@"UIAlertController title=%@ message=%@ style=%ld stack=%@", title, message, (long)style, GCBStack());
    }
    return origAlertController ? origAlertController(self, _cmd, title, message, style) : nil;
}

static void GCBHookInstance(Class cls, SEL selector, IMP replacement, IMP *originalOut) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) {
        GCBLog(@"missing instance method %@ on %s", NSStringFromSelector(selector), class_getName(cls));
        return;
    }
    const char *types = method_getTypeEncoding(method);
    *originalOut = method_setImplementation(method, replacement);
    GCBLog(@"hooked instance %s %@ types=%s", class_getName(cls), NSStringFromSelector(selector), types ?: "?");
}

static void GCBHookClass(Class cls, SEL selector, IMP replacement, IMP *originalOut) {
    Class meta = object_getClass(cls);
    Method method = class_getClassMethod(cls, selector);
    if (!method) {
        GCBLog(@"missing class method %@ on %s", NSStringFromSelector(selector), class_getName(cls));
        return;
    }
    const char *types = method_getTypeEncoding(method);
    *originalOut = method_setImplementation(method, replacement);
    GCBLog(@"hooked class %s %@ types=%s", class_getName(meta), NSStringFromSelector(selector), types ?: "?");
}

static void GCBDumpMethodsForClassName(const char *name) {
    Class cls = objc_getClass(name);
    if (!cls) return;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    NSMutableArray *parts = [NSMutableArray array];
    for (unsigned int i = 0; i < count && i < 80; i++) {
        SEL sel = method_getName(methods[i]);
        const char *types = method_getTypeEncoding(methods[i]);
        [parts addObject:[NSString stringWithFormat:@"%s:%s", sel_getName(sel), types ?: "?"]];
    }
    free(methods);
    GCBLog(@"methods %s %@", name, [parts componentsJoinedByString:@", "]);
}

static void GCBDumpInterestingClasses(void) {
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    NSArray *needles = @[@"BLEPair", @"BluetoothLowEnergy", @"GCMBLE", @"DeviceInfo", @"DeviceAttributes", @"GarminDevice", @"Handshake", @"GFDI", @"Product", @"Support"];
    NSUInteger logged = 0;
    for (unsigned int i = 0; i < count && logged < 120; i++) {
        NSString *name = [NSString stringWithUTF8String:class_getName(classes[i])];
        for (NSString *needle in needles) {
            if ([name containsString:needle]) {
                GCBLog(@"class %@", name);
                GCBDumpMethodsForClassName(class_getName(classes[i]));
                logged++;
                break;
            }
        }
    }
    free(classes);
}

static void GCBInstallHooks(void) {
    GCBLog(@"GarminConnectBypass loaded bundle=%@", [[NSBundle mainBundle] bundleIdentifier]);
    GCBHookInstance([NSBundle class], @selector(localizedStringForKey:value:table:), (IMP)GCBLocalizedString, (IMP *)&origLocalizedString);
    GCBHookClass([UIAlertController class], @selector(alertControllerWithTitle:message:preferredStyle:), (IMP)GCBAlertController, (IMP *)&origAlertController);
    GCBHookInstance(objc_getClass("CBCentralManager"), @selector(cancelPeripheralConnection:), (IMP)GCBCancelPeripheralConnection, (IMP *)&origCancelPeripheralConnection);

    Class attr = objc_getClass("_TtC16GarminDeviceSync16DeviceAttributes");
    if (attr) {
        GCBHookInstance(attr, @selector(productNumber), (IMP)GCBDeviceAttributesProductNumber, (IMP *)&origDeviceAttributesProductNumber);
        GCBHookInstance(attr, @selector(softwareVersion), (IMP)GCBDeviceAttributesSoftwareVersion, (IMP *)&origDeviceAttributesSoftwareVersion);
    } else {
        GCBLog(@"DeviceAttributes class not found");
    }

    Class info = objc_getClass("_TtC22GarminDeviceIOMessages17DeviceInfoRequest");
    if (info) {
        GCBHookInstance(info, @selector(productNumber), (IMP)GCBMessageProductNumber, (IMP *)&origMessageProductNumber);
        GCBHookInstance(info, @selector(protocolVersion), (IMP)GCBMessageProtocolVersion, (IMP *)&origMessageProtocolVersion);
        GCBHookInstance(info, @selector(softwareVersion), (IMP)GCBMessageSoftwareVersion, (IMP *)&origMessageSoftwareVersion);
    } else {
        GCBLog(@"DeviceInfoRequest class not found");
    }
}

__attribute__((constructor))
static void GCBInit(void) {
    @autoreleasepool {
        GCBInstallHooks();
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            GCBDumpInterestingClasses();
        });
    }
}
