#import "GNProtocol.h"

const uint8_t GNPRGType = 255;
const uint8_t GNPRGSubtype = 17;

static const uint16_t GNCRCConstants[] = {
    0x0000, 0xcc01, 0xd801, 0x1400, 0xf001, 0x3c00, 0x2800, 0xe401,
    0xa001, 0x6c00, 0x7800, 0xb401, 0x5000, 0x9c01, 0x8801, 0x4400
};

static void GNAppendU8(NSMutableData *data, uint8_t value) {
    [data appendBytes:&value length:1];
}

static void GNAppendU16(NSMutableData *data, uint16_t value) {
    uint8_t bytes[] = { value & 0xff, (value >> 8) & 0xff };
    [data appendBytes:bytes length:2];
}

static void GNAppendU32(NSMutableData *data, uint32_t value) {
    uint8_t bytes[] = {
        value & 0xff,
        (value >> 8) & 0xff,
        (value >> 16) & 0xff,
        (value >> 24) & 0xff
    };
    [data appendBytes:bytes length:4];
}

static void GNAppendU64(NSMutableData *data, uint64_t value) {
    for (NSUInteger i = 0; i < 8; i++) {
        GNAppendU8(data, (uint8_t)((value >> (8 * i)) & 0xff));
    }
}

uint16_t GNReadU16(NSData *data, NSUInteger offset) {
    if (offset + 2 > data.length) return 0;
    const uint8_t *bytes = data.bytes;
    return (uint16_t)bytes[offset] | ((uint16_t)bytes[offset + 1] << 8);
}

uint32_t GNReadU32(NSData *data, NSUInteger offset) {
    if (offset + 4 > data.length) return 0;
    const uint8_t *bytes = data.bytes;
    return (uint32_t)bytes[offset]
        | ((uint32_t)bytes[offset + 1] << 8)
        | ((uint32_t)bytes[offset + 2] << 16)
        | ((uint32_t)bytes[offset + 3] << 24);
}

uint16_t GNGarminCRC(NSData *data, uint16_t initialCRC) {
    uint16_t crc = initialCRC;
    const uint8_t *bytes = data.bytes;
    for (NSUInteger i = 0; i < data.length; i++) {
        uint8_t b = bytes[i];
        crc = (((crc >> 4) & 0x0fff) ^ GNCRCConstants[crc & 0x0f]) ^ GNCRCConstants[b & 0x0f];
        crc = (((crc >> 4) & 0x0fff) ^ GNCRCConstants[crc & 0x0f]) ^ GNCRCConstants[(b >> 4) & 0x0f];
    }
    return crc;
}

NSData *GNFrameGFDI(uint16_t messageType, NSData *payload) {
    NSMutableData *body = [NSMutableData data];
    GNAppendU16(body, (uint16_t)(2 + 2 + payload.length + 2));
    GNAppendU16(body, messageType);
    if (payload.length) [body appendData:payload];
    uint16_t crc = GNGarminCRC(body, 0);
    GNAppendU16(body, crc);
    return body;
}

NSData *GNBuildCreateFile(NSUInteger fileSize) {
    NSMutableData *payload = [NSMutableData data];
    GNAppendU32(payload, (uint32_t)fileSize);
    GNAppendU8(payload, GNPRGType);
    GNAppendU8(payload, GNPRGSubtype);
    GNAppendU16(payload, 0);
    GNAppendU8(payload, 0);
    GNAppendU8(payload, 0);
    GNAppendU16(payload, 0xffff);
    GNAppendU16(payload, 0);
    uint64_t nonce = ((uint64_t)arc4random() << 32) | arc4random();
    GNAppendU64(payload, nonce);
    return GNFrameGFDI(GNGarminMessageCreateFile, payload);
}

NSData *GNBuildUploadRequest(uint16_t fileIndex, NSUInteger fileSize, uint32_t dataOffset, uint16_t crcSeed) {
    NSMutableData *payload = [NSMutableData data];
    GNAppendU16(payload, fileIndex);
    GNAppendU32(payload, (uint32_t)fileSize);
    GNAppendU32(payload, dataOffset);
    GNAppendU16(payload, crcSeed);
    return GNFrameGFDI(GNGarminMessageUploadRequest, payload);
}

NSData *GNBuildFileTransferData(NSData *chunk, uint32_t dataOffset, uint16_t runningCRC) {
    NSMutableData *payload = [NSMutableData data];
    GNAppendU8(payload, 0);
    GNAppendU16(payload, runningCRC);
    GNAppendU32(payload, dataOffset);
    [payload appendData:chunk];
    return GNFrameGFDI(GNGarminMessageFileTransferData, payload);
}

NSData *GNBuildSystemEvent(uint8_t event, uint8_t value) {
    NSMutableData *payload = [NSMutableData data];
    GNAppendU8(payload, event);
    GNAppendU8(payload, value);
    return GNFrameGFDI(GNGarminMessageSystemEvent, payload);
}

NSData *GNCobsEncode(NSData *data) {
    const uint8_t *input = data.bytes;
    NSMutableData *encoded = [NSMutableData data];
    uint8_t zero = 0;
    [encoded appendBytes:&zero length:1];
    NSUInteger position = 0;
    BOOL lastByteWasZero = NO;

    while (position < data.length) {
        NSUInteger start = position;
        while (position < data.length && input[position] != 0) position += 1;
        NSUInteger zeroIndex = position;
        if (position < data.length && input[position] == 0) {
            position += 1;
            lastByteWasZero = YES;
        } else {
            lastByteWasZero = NO;
        }

        NSUInteger payloadSize = zeroIndex - start;
        while (payloadSize >= 0xfe) {
            uint8_t code = 0xff;
            [encoded appendBytes:&code length:1];
            [encoded appendBytes:input + start length:0xfe];
            start += 0xfe;
            payloadSize -= 0xfe;
        }
        uint8_t code = (uint8_t)(payloadSize + 1);
        [encoded appendBytes:&code length:1];
        if (payloadSize) [encoded appendBytes:input + start length:payloadSize];
    }

    if (lastByteWasZero) {
        uint8_t code = 0x01;
        [encoded appendBytes:&code length:1];
    }
    [encoded appendBytes:&zero length:1];
    return encoded;
}

static NSData *GNCobsDecodeFrame(NSData *frame, NSError **error) {
    const uint8_t *bytes = frame.bytes;
    NSMutableData *decoded = [NSMutableData data];
    NSUInteger index = 0;
    while (index < frame.length) {
        uint8_t code = bytes[index++];
        if (code == 0) break;
        NSUInteger payloadSize = code - 1;
        if (index + payloadSize > frame.length) {
            if (error) *error = [NSError errorWithDomain:@"GNProtocol" code:1 userInfo:@{NSLocalizedDescriptionKey: @"COBS payload runs past frame end"}];
            return nil;
        }
        if (payloadSize) [decoded appendBytes:bytes + index length:payloadSize];
        index += payloadSize;
        if (code != 0xff && index < frame.length) {
            uint8_t zero = 0;
            [decoded appendBytes:&zero length:1];
        }
    }
    return decoded;
}

NSDictionary *GNParseGFDIStatus(NSData *packet, NSError **error) {
    if (packet.length < 6) {
        if (error) *error = [NSError errorWithDomain:@"GNProtocol" code:2 userInfo:@{NSLocalizedDescriptionKey: @"GFDI packet too short"}];
        return nil;
    }
    uint16_t length = GNReadU16(packet, 0);
    if (length != packet.length) {
        if (error) *error = [NSError errorWithDomain:@"GNProtocol" code:3 userInfo:@{NSLocalizedDescriptionKey: @"GFDI length mismatch"}];
        return nil;
    }
    uint16_t expected = GNReadU16(packet, length - 2);
    uint16_t actual = GNGarminCRC([packet subdataWithRange:NSMakeRange(0, length - 2)], 0);
    if (expected != actual) {
        if (error) *error = [NSError errorWithDomain:@"GNProtocol" code:4 userInfo:@{NSLocalizedDescriptionKey: @"GFDI CRC mismatch"}];
        return nil;
    }

    uint16_t messageType = GNReadU16(packet, 2);
    if (messageType & 0x8000) messageType = (messageType & 0xff) + 5000;
    NSData *body = [packet subdataWithRange:NSMakeRange(4, packet.length - 6)];
    if (messageType != GNGarminMessageResponse) {
        return @{@"kind": @"parsed", @"messageType": @(messageType), @"raw": body};
    }
    if (body.length < 3) {
        if (error) *error = [NSError errorWithDomain:@"GNProtocol" code:5 userInfo:@{NSLocalizedDescriptionKey: @"Status body too short"}];
        return nil;
    }
    uint16_t original = GNReadU16(body, 0);
    const uint8_t *b = body.bytes;
    uint8_t status = b[2];
    NSData *rest = [body subdataWithRange:NSMakeRange(3, body.length - 3)];
    NSMutableDictionary *result = [@{@"kind": @"generic", @"originalMessageType": @(original), @"status": @(status)} mutableCopy];

    if (original == GNGarminMessageCreateFile && status == 0 && rest.length >= 7) {
        const uint8_t *r = rest.bytes;
        result[@"kind"] = @"createFile";
        result[@"createStatus"] = @(r[0]);
        result[@"fileIndex"] = @(GNReadU16(rest, 1));
        result[@"dataType"] = @(r[3]);
        result[@"subtype"] = @(r[4]);
        result[@"fileNumber"] = @(GNReadU16(rest, 5));
    } else if (original == GNGarminMessageUploadRequest && status == 0 && rest.length >= 11) {
        const uint8_t *r = rest.bytes;
        result[@"kind"] = @"uploadRequest";
        result[@"uploadStatus"] = @(r[0]);
        result[@"dataOffset"] = @(GNReadU32(rest, 1));
        result[@"maxFileSize"] = @(GNReadU32(rest, 5));
        result[@"crcSeed"] = @(GNReadU16(rest, 9));
    } else if (original == GNGarminMessageFileTransferData && status == 0 && rest.length >= 5) {
        const uint8_t *r = rest.bytes;
        result[@"kind"] = @"fileTransferData";
        result[@"transferStatus"] = @(r[0]);
        result[@"dataOffset"] = @(GNReadU32(rest, 1));
    }
    return result;
}

NSString *GNHexPreview(NSData *data, NSUInteger maxBytes) {
    const uint8_t *bytes = data.bytes;
    NSUInteger count = MIN(maxBytes, data.length);
    NSMutableString *hex = [NSMutableString stringWithCapacity:count * 3];
    for (NSUInteger i = 0; i < count; i++) {
        if (i) [hex appendString:@" "];
        [hex appendFormat:@"%02x", bytes[i]];
    }
    if (data.length > maxBytes) [hex appendString:@" ..."];
    return hex;
}

@interface GNCobsDecoder ()
@property (nonatomic, strong) NSMutableData *buffer;
@end

@implementation GNCobsDecoder

- (instancetype)init {
    self = [super init];
    if (self) _buffer = [NSMutableData data];
    return self;
}

- (NSArray<NSData *> *)feed:(NSData *)data error:(NSError **)error {
    [self.buffer appendData:data];
    NSMutableArray<NSData *> *messages = [NSMutableArray array];
    while (self.buffer.length >= 4) {
        const uint8_t *bytes = self.buffer.bytes;
        NSRange start = NSMakeRange(NSNotFound, 0);
        NSRange end = NSMakeRange(NSNotFound, 0);
        for (NSUInteger i = 0; i < self.buffer.length; i++) {
            if (bytes[i] == 0) {
                start = NSMakeRange(i, 1);
                break;
            }
        }
        if (start.location == NSNotFound) {
            [self.buffer setLength:0];
            return messages;
        }
        for (NSUInteger i = start.location + 1; i < self.buffer.length; i++) {
            if (bytes[i] == 0) {
                end = NSMakeRange(i, 1);
                break;
            }
        }
        if (end.location == NSNotFound) return messages;
        if (start.location > 0) {
            [self.buffer replaceBytesInRange:NSMakeRange(0, start.location) withBytes:NULL length:0];
            continue;
        }
        NSData *frame = [self.buffer subdataWithRange:NSMakeRange(1, end.location - 1)];
        [self.buffer replaceBytesInRange:NSMakeRange(0, end.location + 1) withBytes:NULL length:0];
        NSData *decoded = GNCobsDecodeFrame(frame, error);
        if (decoded) [messages addObject:decoded];
        else return messages;
    }
    return messages;
}

@end

@interface GNUploadChunker ()
@property (nonatomic, strong) NSData *data;
@property (nonatomic, assign) NSUInteger maxPayloadSize;
@property (nonatomic, assign, readwrite) uint32_t offset;
@property (nonatomic, assign, readwrite) uint16_t runningCRC;
@end

@implementation GNUploadChunker

- (instancetype)initWithData:(NSData *)data maxPacketSize:(NSUInteger)maxPacketSize initialOffset:(uint32_t)offset initialCRC:(uint16_t)crc {
    self = [super init];
    if (self) {
        _data = data;
        [self setMaxPacketSize:maxPacketSize];
        _offset = offset;
        _runningCRC = crc;
    }
    return self;
}

- (void)setMaxPacketSize:(NSUInteger)maxPacketSize {
    self.maxPayloadSize = MAX(1, maxPacketSize > 13 ? maxPacketSize - 13 : 1);
}

- (void)seek:(uint32_t)offset runningCRC:(NSNumber *)runningCRC {
    self.offset = MIN(offset, (uint32_t)self.data.length);
    if (runningCRC) {
        self.runningCRC = runningCRC.unsignedShortValue;
    } else {
        self.runningCRC = GNGarminCRC([self.data subdataWithRange:NSMakeRange(0, self.offset)], 0);
    }
}

- (NSDictionary *)nextChunkUntil:(NSUInteger)stopOffset {
    NSUInteger limit = MIN(stopOffset, self.data.length);
    if (self.offset >= limit) return nil;
    NSUInteger length = MIN(self.maxPayloadSize, limit - self.offset);
    NSData *chunk = [self.data subdataWithRange:NSMakeRange(self.offset, length)];
    uint32_t current = self.offset;
    self.runningCRC = GNGarminCRC(chunk, self.runningCRC);
    self.offset += (uint32_t)length;
    return @{@"offset": @(current), @"data": chunk, @"crc": @(self.runningCRC)};
}

@end
