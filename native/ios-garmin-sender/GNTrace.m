#import "GNTrace.h"

static NSString *GNEscapeJSONString(NSString *value) {
    NSMutableString *escaped = [value mutableCopy];
    [escaped replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"\"" withString:@"\\\"" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"\n" withString:@"\\n" options:0 range:NSMakeRange(0, escaped.length)];
    [escaped replaceOccurrencesOfString:@"\r" withString:@"\\r" options:0 range:NSMakeRange(0, escaped.length)];
    return escaped;
}

static NSString *GNHex(NSData *data) {
    const uint8_t *bytes = data.bytes;
    NSMutableString *hex = [NSMutableString stringWithCapacity:data.length * 2];
    for (NSUInteger i = 0; i < data.length; i++) {
        [hex appendFormat:@"%02x", bytes[i]];
    }
    return hex;
}

@interface GNTrace ()
@property (nonatomic, strong) NSMutableArray<NSString *> *jsonLines;
@property (nonatomic, assign) NSUInteger sequence;
@end

@implementation GNTrace

- (instancetype)init {
    self = [super init];
    if (self) {
        _enabled = YES;
        _jsonLines = [NSMutableArray array];
    }
    return self;
}

- (void)recordLayer:(NSString *)layer
          direction:(NSString *)direction
               data:(NSData *)data
           metadata:(NSDictionary *)metadata {
    if (!self.enabled || !data) return;
    self.sequence += 1;
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSMutableString *line = [NSMutableString string];
    [line appendFormat:@"{\"index\":%lu,\"unixTime\":%.3f,\"layer\":\"%@\",\"direction\":\"%@\",\"length\":%lu,\"hex\":\"%@\"",
     (unsigned long)self.sequence,
     now,
     GNEscapeJSONString(layer ?: @""),
     GNEscapeJSONString(direction ?: @""),
     (unsigned long)data.length,
     GNHex(data)];
    NSArray *keys = [[metadata allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *key in keys) {
        id value = metadata[key];
        if ([value isKindOfClass:[NSNumber class]]) {
            [line appendFormat:@",\"%@\":%@", GNEscapeJSONString(key), value];
        } else {
            [line appendFormat:@",\"%@\":\"%@\"", GNEscapeJSONString(key), GNEscapeJSONString([value description])];
        }
    }
    [line appendString:@"}"];
    [self.jsonLines addObject:line];
}

- (NSString *)exportTraceToDirectory:(NSString *)directory {
    if (!directory.length) return nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyyMMdd-HHmmss";
    NSString *name = [NSString stringWithFormat:@"garmin-native-trace-%@.jsonl", [formatter stringFromDate:[NSDate date]]];
    NSString *path = [directory stringByAppendingPathComponent:name];
    NSString *body = [self.jsonLines componentsJoinedByString:@"\n"];
    if (body.length) body = [body stringByAppendingString:@"\n"];
    NSError *error = nil;
    if (![body writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        return [NSString stringWithFormat:@"trace export failed: %@", error.localizedDescription];
    }
    return path;
}

- (void)clear {
    [self.jsonLines removeAllObjects];
    self.sequence = 0;
}

@end
