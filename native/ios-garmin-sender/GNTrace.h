#import <Foundation/Foundation.h>

@interface GNTrace : NSObject

@property (nonatomic, assign, getter=isEnabled) BOOL enabled;

- (void)recordLayer:(NSString *)layer
          direction:(NSString *)direction
               data:(NSData *)data
           metadata:(NSDictionary *)metadata;
- (NSString *)exportTraceToDirectory:(NSString *)directory;
- (void)clear;

@end
