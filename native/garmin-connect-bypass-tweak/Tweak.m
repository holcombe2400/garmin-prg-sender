#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>

static const uint8_t GCBPRGType = 255;
static const uint8_t GCBPRGSubtype = 17;

static uintptr_t (*origDeviceAttributesProductNumber)(id, SEL);
static uintptr_t (*origDeviceAttributesSoftwareVersion)(id, SEL);
static unsigned short (*origMessageProductNumber)(id, SEL);
static unsigned short (*origMessageProtocolVersion)(id, SEL);
static unsigned short (*origMessageSoftwareVersion)(id, SEL);
static void (*origCancelPeripheralConnection)(id, SEL, id);
static NSString *(*origLocalizedString)(id, SEL, NSString *, NSString *, NSString *);
static id (*origAlertController)(id, SEL, NSString *, NSString *, NSInteger);
static id (*origGDIFileSenderInitWithDelegate)(id, SEL, id, id);
static void (*origGDIFileSenderSendFileToEdge)(id, SEL, id, NSUInteger, NSUInteger, id, NSUInteger);
static id GCBLastFileSender;
static UIButton *GCBUploadButton;

static NSString *GCBDirPath(void) {
    static NSString *dir;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dir = [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/GarminConnectBypass"] copy];
    });
    return dir;
}

static NSString *GCBLogPath(void) {
    return [GCBDirPath() stringByAppendingPathComponent:@"live.log"];
}

#ifdef memset
#undef memset
#endif
void *memset(void *ptr, int value, unsigned long count) {
    unsigned char *p = (unsigned char *)ptr;
    while (count--) *p++ = (unsigned char)value;
    return ptr;
}

static BOOL GCBFileExists(NSString *name) {
    NSString *path = [GCBDirPath() stringByAppendingPathComponent:name];
    return [[NSFileManager defaultManager] fileExistsAtPath:path];
}

static NSString *GCBReadTrimmedControlFile(NSString *name) {
    NSString *path = [GCBDirPath() stringByAppendingPathComponent:name];
    NSString *value = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static void GCBLog(NSString *format, ...) {
    @autoreleasepool {
        NSString *logPath = GCBLogPath();
        [[NSFileManager defaultManager] createDirectoryAtPath:GCBDirPath() withIntermediateDirectories:YES attributes:nil error:nil];
        va_list args;
        va_start(args, format);
        NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
        va_end(args);
        NSDateFormatter *formatter = [NSDateFormatter new];
        formatter.dateFormat = @"HH:mm:ss.SSS";
        NSString *line = [NSString stringWithFormat:@"%@  %@\n", [formatter stringFromDate:[NSDate date]], message];
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        if (![[NSFileManager defaultManager] fileExistsAtPath:logPath]) {
            [data writeToFile:logPath atomically:YES];
            return;
        }
        NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:logPath];
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

static NSString *GCBTypeEncodingForSelector(Class cls, SEL selector) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) return @"<missing>";
    const char *types = method_getTypeEncoding(method);
    return types ? [NSString stringWithUTF8String:types] : @"?";
}

static BOOL GCBLooksLikePRGAtPath(NSString *path, NSUInteger *sizeOut) {
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    NSNumber *size = attrs[NSFileSize];
    if (sizeOut) *sizeOut = size ? size.unsignedIntegerValue : 0;
    if (!size || size.unsignedIntegerValue < 3) return NO;
    NSData *prefix = [NSData dataWithContentsOfFile:path options:0 error:nil];
    if (prefix.length < 3) return NO;
    const uint8_t *bytes = prefix.bytes;
    return bytes[0] == 0xd0 && bytes[1] == 0x00 && bytes[2] == 0xd0;
}

static NSString *GCBPRGPath(void) {
    NSString *configured = GCBReadTrimmedControlFile(@"prg_path");
    NSArray *candidates = configured.length
        ? @[configured]
        : @[
            [GCBDirPath() stringByAppendingPathComponent:@"input.prg"],
            @"/var/mobile/Documents/GarminNativeSender/input.prg"
        ];
    for (NSString *path in candidates) {
        BOOL isDir = NO;
        if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir] && !isDir) return path;
    }
    return candidates.firstObject;
}

static void GCBShowAlert(NSString *title, NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *root = [UIApplication sharedApplication].keyWindow.rootViewController;
        while (root.presentedViewController) root = root.presentedViewController;
        if (!root) return;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [root presentViewController:alert animated:YES completion:nil];
    });
}

static void GCBSetInvocationArg(NSInvocation *inv, NSUInteger index, const char *type, id objectValue, unsigned long long intValue) {
    while (*type == 'r' || *type == 'n' || *type == 'N' || *type == 'o' || *type == 'O' || *type == 'R' || *type == 'V') type++;
    if (type[0] == '@') {
        id value = objectValue;
        [inv setArgument:&value atIndex:index];
    } else if (type[0] == 'c' || type[0] == 'C' || type[0] == 'B') {
        unsigned char value = (unsigned char)intValue;
        [inv setArgument:&value atIndex:index];
    } else if (type[0] == 's' || type[0] == 'S') {
        unsigned short value = (unsigned short)intValue;
        [inv setArgument:&value atIndex:index];
    } else if (type[0] == 'i' || type[0] == 'I' || type[0] == 'l' || type[0] == 'L') {
        unsigned int value = (unsigned int)intValue;
        [inv setArgument:&value atIndex:index];
    } else if (type[0] == 'q' || type[0] == 'Q') {
        unsigned long long value = intValue;
        [inv setArgument:&value atIndex:index];
    } else {
        GCBLog(@"Upload PRG cannot set arg %lu type=%s", (unsigned long)index, type);
    }
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

static id GCBGDIFileSenderInitWithDelegate(id self, SEL _cmd, id delegate, id taskManager) {
    id value = origGDIFileSenderInitWithDelegate ? origGDIFileSenderInitWithDelegate(self, _cmd, delegate, taskManager) : self;
    GCBLastFileSender = value;
    GCBLog(@"File sender init captured self=%p class=%@ delegateClass=%@ taskManagerClass=%@",
           value, value ? NSStringFromClass([value class]) : @"<nil>",
           delegate ? NSStringFromClass([delegate class]) : @"<nil>",
           taskManager ? NSStringFromClass([taskManager class]) : @"<nil>");
    return value;
}

static void GCBGDIFileSenderSendFileToEdge(id self, SEL _cmd, id file, NSUInteger dataType, NSUInteger subType, id deviceFilePath, NSUInteger identifier) {
    GCBLastFileSender = self;
    GCBLog(@"GDIFileSender sendFileToEdge self=%p file=%p fileClass=%@ dataType=%lu subType=%lu deviceFilePathClass=%@ identifier=%lu stack=%@",
           self, file, file ? NSStringFromClass([file class]) : @"<nil>", (unsigned long)dataType, (unsigned long)subType,
           deviceFilePath ? NSStringFromClass([deviceFilePath class]) : @"<nil>", (unsigned long)identifier, GCBStack());
    if (origGDIFileSenderSendFileToEdge) origGDIFileSenderSendFileToEdge(self, _cmd, file, dataType, subType, deviceFilePath, identifier);
}

static void GCBUploadPRGNow(void) {
    NSString *path = GCBPRGPath();
    NSUInteger size = 0;
    if (!GCBLooksLikePRGAtPath(path, &size)) {
        GCBLog(@"Upload PRG refused. Missing/invalid PRG at %@", path);
        GCBShowAlert(@"Upload PRG", [NSString stringWithFormat:@"Put a valid .prg at:\n%@", path]);
        return;
    }
    id sender = GCBLastFileSender;
    SEL selector = @selector(sendFileToEdge:withDataType:withSubType:deviceFilePath:identifier:);
    if (!sender || ![sender respondsToSelector:selector]) {
        GCBLog(@"Upload PRG requested but no live GDIFileSender is captured yet. path=%@ size=%lu", path, (unsigned long)size);
        GCBShowAlert(@"Upload PRG", @"Garmin Connect has not exposed its file sender yet. Start a sync once, then tap Upload PRG again.");
        return;
    }

    NSMethodSignature *signature = [sender methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments < 7) {
        GCBLog(@"Upload PRG cannot invoke sendFileToEdge signature=%@ argCount=%lu", signature, (unsigned long)signature.numberOfArguments);
        GCBShowAlert(@"Upload PRG", @"Garmin file sender signature was not usable. I logged the details.");
        return;
    }
    NSData *prgData = [NSData dataWithContentsOfFile:path options:0 error:nil];
    if (!prgData.length) {
        GCBLog(@"Upload PRG could not read %@", path);
        GCBShowAlert(@"Upload PRG", @"Could not read the PRG file.");
        return;
    }

    NSUInteger identifier = (((NSUInteger)[[NSDate date] timeIntervalSince1970]) ^ (NSUInteger)arc4random());
    id nilPath = nil;
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:signature];
    inv.target = sender;
    inv.selector = selector;
    GCBSetInvocationArg(inv, 2, [signature getArgumentTypeAtIndex:2], prgData, 0);
    GCBSetInvocationArg(inv, 3, [signature getArgumentTypeAtIndex:3], nil, GCBPRGType);
    GCBSetInvocationArg(inv, 4, [signature getArgumentTypeAtIndex:4], nil, GCBPRGSubtype);
    GCBSetInvocationArg(inv, 5, [signature getArgumentTypeAtIndex:5], nilPath, 0);
    GCBSetInvocationArg(inv, 6, [signature getArgumentTypeAtIndex:6], nil, identifier);
    [inv retainArguments];

    GCBLog(@"Upload PRG invoking sender=%p path=%@ size=%lu type=%u subtype=%u identifier=%lu signature=%@",
           sender, path, (unsigned long)size, GCBPRGType, GCBPRGSubtype, (unsigned long)identifier, signature);
    [inv invoke];
    GCBShowAlert(@"Upload PRG", [NSString stringWithFormat:@"Started via Garmin Connect sender.\n%lu bytes", (unsigned long)size]);
}

static void GCBUploadButtonTapped(id self, SEL _cmd) {
    GCBLog(@"Upload PRG button tapped");
    GCBUploadPRGNow();
}

static void GCBInstallUploadButton(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = [UIApplication sharedApplication].keyWindow;
        if (!window || GCBUploadButton.superview == window) return;
        if (!GCBUploadButton) {
            GCBUploadButton = [UIButton buttonWithType:UIButtonTypeSystem];
            GCBUploadButton.frame = CGRectMake(12, 76, 92, 38);
            GCBUploadButton.autoresizingMask = UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleBottomMargin;
            GCBUploadButton.backgroundColor = [UIColor colorWithRed:0.00 green:0.42 blue:0.86 alpha:0.92];
            GCBUploadButton.layer.cornerRadius = 8;
            GCBUploadButton.layer.borderWidth = 1;
            GCBUploadButton.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.35].CGColor;
            GCBUploadButton.titleLabel.font = [UIFont boldSystemFontOfSize:13];
            [GCBUploadButton setTitle:@"Upload PRG" forState:UIControlStateNormal];
            [GCBUploadButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            [GCBUploadButton addTarget:[UIApplication sharedApplication] action:@selector(gcb_uploadPRGButtonTapped) forControlEvents:UIControlEventTouchUpInside];
        }
        [window addSubview:GCBUploadButton];
        [window bringSubviewToFront:GCBUploadButton];
        GCBLog(@"Upload PRG button installed window=%@", window);
    });
}

@interface UIApplication (GarminConnectBypassUpload)
- (void)gcb_uploadPRGButtonTapped;
@end

@implementation UIApplication (GarminConnectBypassUpload)
- (void)gcb_uploadPRGButtonTapped {
    GCBUploadButtonTapped(self, _cmd);
}
@end

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

static Class GCBFindClassWithInstanceSelector(SEL selector, NSString *nameHint) {
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    Class found = Nil;
    NSMutableArray *matches = [NSMutableArray array];
    for (unsigned int i = 0; i < count; i++) {
        Class cls = classes[i];
        if (!class_getInstanceMethod(cls, selector)) continue;
        NSString *name = [NSString stringWithUTF8String:class_getName(cls)];
        [matches addObject:name ?: @"<unknown>"];
        if (!found && (!nameHint.length || [name containsString:nameHint])) found = cls;
        if (!found) found = cls;
    }
    GCBLog(@"selector %@ matches %@", NSStringFromSelector(selector), [matches componentsJoinedByString:@", "]);
    free(classes);
    return found;
}

static void GCBDumpInterestingClasses(void) {
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    NSArray *needles = @[@"BLEPair", @"BluetoothLowEnergy", @"GCMBLE", @"DeviceInfo", @"DeviceAttributes", @"GarminDevice", @"Handshake", @"GFDI", @"Product", @"Support", @"FileSender", @"FileTransfer", @"CreateFile", @"UploadRequest", @"QueuedDownload", @"Synchronization", @"Download", @"Device"];
    NSUInteger logged = 0;
    for (unsigned int i = 0; i < count && logged < 260; i++) {
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

    Class nominalFileSender = objc_getClass("GDIFileSender");
    if (nominalFileSender) {
        GCBDumpMethodsForClassName("GDIFileSender");
    } else {
        GCBLog(@"GDIFileSender class not found");
    }

    SEL sendFileSelector = @selector(sendFileToEdge:withDataType:withSubType:deviceFilePath:identifier:);
    Class fileSender = nominalFileSender;
    if (!fileSender || !class_getInstanceMethod(fileSender, sendFileSelector)) {
        fileSender = GCBFindClassWithInstanceSelector(sendFileSelector, @"FileSender");
    }
    if (fileSender) {
        GCBLog(@"using file sender class %s", class_getName(fileSender));
        GCBHookInstance(fileSender, @selector(initWithDelegate:taskManager:), (IMP)GCBGDIFileSenderInitWithDelegate, (IMP *)&origGDIFileSenderInitWithDelegate);
        GCBHookInstance(fileSender, sendFileSelector, (IMP)GCBGDIFileSenderSendFileToEdge, (IMP *)&origGDIFileSenderSendFileToEdge);
        GCBLog(@"file sender sendFileToEdge types=%@", GCBTypeEncodingForSelector(fileSender, sendFileSelector));
    } else {
        GCBLog(@"No runtime class owns %@", NSStringFromSelector(sendFileSelector));
    }

    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        GCBInstallUploadButton();
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        GCBInstallUploadButton();
    });
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
