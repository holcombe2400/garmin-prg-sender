#import <Foundation/Foundation.h>

extern const uint8_t GNPRGType;
extern const uint8_t GNPRGSubtype;

typedef NS_ENUM(uint16_t, GNGarminMessage) {
    GNGarminMessageResponse = 5000,
    GNGarminMessageUploadRequest = 5003,
    GNGarminMessageFileTransferData = 5004,
    GNGarminMessageCreateFile = 5005,
    GNGarminMessageSystemEvent = 5030,
};

typedef NS_ENUM(uint8_t, GNSystemEvent) {
    GNSystemEventSyncComplete = 0,
    GNSystemEventSyncReady = 8,
};

uint16_t GNGarminCRC(NSData *data, uint16_t initialCRC);
NSData *GNCobsEncode(NSData *data);
NSData *GNFrameGFDI(uint16_t messageType, NSData *payload);
NSData *GNBuildCreateFile(NSUInteger fileSize);
NSData *GNBuildUploadRequest(uint16_t fileIndex, NSUInteger fileSize, uint32_t dataOffset, uint16_t crcSeed);
NSData *GNBuildFileTransferData(NSData *chunk, uint32_t dataOffset, uint16_t runningCRC);
NSData *GNBuildSystemEvent(uint8_t event, uint8_t value);
NSDictionary *GNParseGFDIStatus(NSData *packet, NSError **error);
NSString *GNHexPreview(NSData *data, NSUInteger maxBytes);
uint16_t GNReadU16(NSData *data, NSUInteger offset);
uint32_t GNReadU32(NSData *data, NSUInteger offset);

@interface GNCobsDecoder : NSObject
- (NSArray<NSData *> *)feed:(NSData *)data error:(NSError **)error;
@end

@interface GNUploadChunker : NSObject
@property (nonatomic, assign, readonly) uint32_t offset;
@property (nonatomic, assign, readonly) uint16_t runningCRC;
- (instancetype)initWithData:(NSData *)data maxPacketSize:(NSUInteger)maxPacketSize initialOffset:(uint32_t)offset initialCRC:(uint16_t)crc;
- (void)setMaxPacketSize:(NSUInteger)maxPacketSize;
- (void)seek:(uint32_t)offset runningCRC:(NSNumber *)runningCRC;
- (NSDictionary *)nextChunkUntil:(NSUInteger)stopOffset;
@end
