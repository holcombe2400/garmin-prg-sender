#import <Foundation/Foundation.h>

@protocol GNSenderDelegate <NSObject>
- (void)senderDidLog:(NSString *)message;
- (void)senderDidUpdateStatus:(NSString *)status;
- (void)senderDidUpdateProgressOffset:(NSUInteger)offset total:(NSUInteger)total;
@end

@interface GNSender : NSObject

@property (nonatomic, weak) id<GNSenderDelegate> delegate;
@property (nonatomic, assign) NSUInteger gfdiPacketSize;
@property (nonatomic, assign) NSUInteger bleFragmentSize;
@property (nonatomic, assign) NSUInteger pipelineWindow;
@property (nonatomic, assign) BOOL reliableMlr;

- (void)startScan;
- (void)connectFirstDiscoveredPeripheral;
- (void)uploadPRGAtPath:(NSString *)path;
- (NSString *)exportTrace;
- (void)stop;

@end
