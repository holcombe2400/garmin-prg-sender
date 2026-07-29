#import "GNSender.h"
#import "GNProtocol.h"
#import "GNTrace.h"
#import <CoreBluetooth/CoreBluetooth.h>

static NSString * const GNV2ServiceUUID = @"6A4E2800-667B-11E3-949A-0800200C9A66";
static NSString * const GNFE1FServiceUUID = @"FE1F";
static const uint64_t GNGadgetbridgeClientID = 2;
static const uint8_t GNMlrFlagMask = 0x80;
static const uint8_t GNMlrHandleMask = 0x70;
static const uint8_t GNMlrReqMask = 0x0f;
static const uint8_t GNMlrSeqMask = 0x3f;
static const uint8_t GNMlrMaxSeq = 0x3f;
static const NSUInteger GNMlrInitialWindow = 0x20;
static const NSTimeInterval GNGfdiTimeout = 30.0;
static NSString * const GNTraceDirectory = @"/var/mobile/Documents/GarminNativeSender";

typedef BOOL (^GNStatusMatcher)(NSDictionary *status);

static NSString *GNLocalHex(NSData *data) {
    const uint8_t *bytes = data.bytes;
    NSMutableString *hex = [NSMutableString stringWithCapacity:data.length * 2];
    for (NSUInteger i = 0; i < data.length; i++) {
        [hex appendFormat:@"%02x", bytes[i]];
    }
    return hex;
}

@interface GNStatusWaiter : NSObject
@property (nonatomic, copy) GNStatusMatcher matcher;
@property (nonatomic, strong) dispatch_semaphore_t semaphore;
@property (nonatomic, strong) NSDictionary *result;
@end

@implementation GNStatusWaiter
@end

@interface GNSentFragment : NSObject
@property (nonatomic, strong) NSData *packet;
@end

@implementation GNSentFragment
@end

@interface GNSender () <CBCentralManagerDelegate, CBPeripheralDelegate>
@property (nonatomic, strong) CBCentralManager *central;
@property (nonatomic, strong) NSMutableArray<CBPeripheral *> *discovered;
@property (nonatomic, strong) NSMutableSet<NSUUID *> *garminIdentifiers;
@property (nonatomic, strong) CBPeripheral *peripheral;
@property (nonatomic, strong) CBCharacteristic *rx;
@property (nonatomic, strong) CBCharacteristic *tx;
@property (nonatomic, strong) GNCobsDecoder *decoder;
@property (nonatomic, strong) GNTrace *trace;
@property (nonatomic, strong) NSMutableArray<NSData *> *decodedQueue;
@property (nonatomic, strong) NSMutableArray<GNStatusWaiter *> *waiters;
@property (nonatomic, strong) dispatch_queue_t uploadQueue;
@property (nonatomic, assign) uint8_t gfdiHandle;
@property (nonatomic, assign) BOOL hasGfdiHandle;
@property (nonatomic, assign) BOOL mlrActive;
@property (nonatomic, assign) uint8_t lastSendAck;
@property (nonatomic, assign) uint8_t nextSendSeq;
@property (nonatomic, assign) uint8_t nextRcvSeq;
@property (nonatomic, assign) uint8_t lastRcvAck;
@property (nonatomic, assign) NSUInteger mlrWindow;
@property (nonatomic, strong) NSMutableArray<NSData *> *mlrQueue;
@property (nonatomic, strong) NSMutableArray<GNSentFragment *> *sentFragments;
@property (nonatomic, assign) NSUInteger retransmissionGeneration;
@property (nonatomic, assign) NSTimeInterval retransmissionTimeout;
@property (nonatomic, assign) BOOL stopped;
@property (nonatomic, assign) BOOL readyForUpload;
@property (nonatomic, assign) BOOL autoConnectAttempted;
@property (nonatomic, assign) NSUInteger bytesSentSinceStart;
@property (nonatomic, strong) NSDate *uploadStartedAt;
@property (nonatomic, strong) NSTimer *scanCycleTimer;
@property (nonatomic, assign) NSUInteger scanCycleIndex;
@end

@implementation GNSender

- (instancetype)init {
    self = [super init];
    if (self) {
        _gfdiPacketSize = 3072;
        _bleFragmentSize = 20;
        _pipelineWindow = 8;
        _reliableMlr = YES;
        _discovered = [NSMutableArray array];
        _garminIdentifiers = [NSMutableSet set];
        _decoder = [[GNCobsDecoder alloc] init];
        _trace = [[GNTrace alloc] init];
        _decodedQueue = [NSMutableArray array];
        _waiters = [NSMutableArray array];
        _uploadQueue = dispatch_queue_create("com.holcombe.garminnativesender.upload", DISPATCH_QUEUE_SERIAL);
        _mlrQueue = [NSMutableArray array];
        _sentFragments = [NSMutableArray arrayWithCapacity:64];
        for (NSUInteger i = 0; i < 64; i++) [_sentFragments addObject:[GNSentFragment new]];
        _mlrWindow = GNMlrInitialWindow;
        _retransmissionTimeout = 1.0;
        _central = [[CBCentralManager alloc] initWithDelegate:self queue:dispatch_get_main_queue()];
    }
    return self;
}

- (void)startScan {
    self.stopped = NO;
    self.autoConnectAttempted = NO;
    [self.discovered removeAllObjects];
    [self.garminIdentifiers removeAllObjects];
    self.scanCycleIndex = 0;
    [self log:@"Starting Garmin pair hunter. Cycling generic, FE1F, Garmin GFDI, combined, and solicited scans..."];
    if (self.central.state != CBManagerStatePoweredOn) {
        [self log:[NSString stringWithFormat:@"Bluetooth is not powered on yet; state=%ld", (long)self.central.state]];
        return;
    }
    [self.scanCycleTimer invalidate];
    [self runNextScanCycle];
    self.scanCycleTimer = [NSTimer scheduledTimerWithTimeInterval:5.0
                                                           target:self
                                                         selector:@selector(runNextScanCycle)
                                                         userInfo:nil
                                                          repeats:YES];
    [self updateStatus:@"Pair hunting..."];
}

- (NSMutableDictionary *)garminScanOptionsWithSolicitedServices:(NSArray<CBUUID *> *)solicitedServices {
    NSMutableDictionary *options = [@{
        CBCentralManagerScanOptionAllowDuplicatesKey: @YES,
        @"kCBScanOptionAllowDuplicates": @YES,
        @"kCBScanOptionActiveScan": @YES,
        @"kCBScanOptionScanWindow": @48,
        @"kCBScanOptionScanInterval": @64,
    } mutableCopy];
    if (solicitedServices.count) {
        options[@"kCBScanOptionSolicitedServiceUUIDs"] = solicitedServices;
    }
    return options;
}

- (void)runNextScanCycle {
    if (self.stopped || self.central.state != CBManagerStatePoweredOn) return;

    CBUUID *fe1f = [CBUUID UUIDWithString:GNFE1FServiceUUID];
    CBUUID *gfdi = [CBUUID UUIDWithString:GNV2ServiceUUID];
    NSArray<NSDictionary *> *cycles = @[
        @{@"label": @"generic active scan", @"services": @[], @"solicited": @[fe1f, gfdi]},
        @{@"label": @"FE1F service scan", @"services": @[fe1f], @"solicited": @[fe1f, gfdi]},
        @{@"label": @"Garmin GFDI service scan", @"services": @[gfdi], @"solicited": @[fe1f, gfdi]},
        @{@"label": @"combined Garmin service scan", @"services": @[fe1f, gfdi], @"solicited": @[fe1f, gfdi]},
        @{@"label": @"generic solicited Garmin scan", @"services": @[], @"solicited": @[fe1f, gfdi]},
    ];
    NSDictionary *cycle = cycles[self.scanCycleIndex % cycles.count];
    self.scanCycleIndex++;

    NSArray<CBUUID *> *services = cycle[@"services"];
    NSArray<CBUUID *> *solicited = cycle[@"solicited"];
    NSMutableDictionary *options = [self garminScanOptionsWithSolicitedServices:solicited];
    [self.central stopScan];
    [self log:[NSString stringWithFormat:@"Pair hunter cycle %lu: %@ services=%@ options=%@",
               (unsigned long)self.scanCycleIndex,
               cycle[@"label"],
               services.count ? services : @"nil",
               options]];
    [self.central scanForPeripheralsWithServices:services.count ? services : nil options:options];
}

- (void)connectFirstDiscoveredPeripheral {
    if (!self.discovered.count) {
        [self log:@"No connectable BLE peripheral discovered yet. Tap Scan Garmin first and wait 10-20 seconds."];
        return;
    }
    CBPeripheral *selected = nil;
    for (CBPeripheral *peripheral in self.discovered) {
        if ([self.garminIdentifiers containsObject:peripheral.identifier]) {
            selected = peripheral;
            break;
        }
    }
    selected = selected ?: self.discovered.firstObject;
    self.peripheral = selected;
    self.peripheral.delegate = self;
    [self.scanCycleTimer invalidate];
    self.scanCycleTimer = nil;
    [self.central stopScan];
    if (![self.garminIdentifiers containsObject:self.peripheral.identifier]) {
        [self log:@"No Garmin-like candidate was marked, trying the first connectable BLE device seen."];
    }
    [self log:[NSString stringWithFormat:@"Connecting to %@ %@", self.peripheral.name ?: @"Unnamed", self.peripheral.identifier.UUIDString]];
    [self updateStatus:@"Connecting..."];
    [self.central connectPeripheral:self.peripheral options:nil];
}

- (void)uploadPRGAtPath:(NSString *)path {
    if (!self.readyForUpload) {
        [self log:@"Transport is not ready. Connect and wait for GFDI registration first."];
        return;
    }
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data.length) {
        [self log:[NSString stringWithFormat:@"No PRG found at %@", path]];
        return;
    }
    const uint8_t *bytes = data.bytes;
    if (data.length < 3 || bytes[0] != 0xd0 || bytes[1] != 0x00 || bytes[2] != 0xd0) {
        [self log:@"File does not start with Garmin PRG magic D0 00 D0."];
        return;
    }
    self.stopped = NO;
    [self.trace clear];
    dispatch_async(self.uploadQueue, ^{
        [self runUpload:data];
    });
}

- (NSString *)exportTrace {
    return [self.trace exportTraceToDirectory:GNTraceDirectory];
}

- (void)stop {
    self.stopped = YES;
    self.readyForUpload = NO;
    [self.scanCycleTimer invalidate];
    self.scanCycleTimer = nil;
    [self.central stopScan];
    if (self.peripheral) [self.central cancelPeripheralConnection:self.peripheral];
    [self log:@"Stopped and disconnected."];
    [self updateStatus:@"Stopped."];
}

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    [self log:[NSString stringWithFormat:@"Bluetooth state changed: %ld", (long)central.state]];
}

- (void)centralManager:(CBCentralManager *)central
 didDiscoverPeripheral:(CBPeripheral *)peripheral
     advertisementData:(NSDictionary<NSString *,id> *)advertisementData
                  RSSI:(NSNumber *)RSSI {
    (void)central;
    NSString *name = peripheral.name ?: advertisementData[CBAdvertisementDataLocalNameKey] ?: @"";
    NSMutableArray<CBUUID *> *services = [NSMutableArray array];
    for (NSString *key in @[CBAdvertisementDataServiceUUIDsKey,
                            CBAdvertisementDataOverflowServiceUUIDsKey,
                            CBAdvertisementDataSolicitedServiceUUIDsKey]) {
        NSArray *values = advertisementData[key];
        if ([values isKindOfClass:[NSArray class]]) {
            [services addObjectsFromArray:values];
        }
    }
    NSMutableArray<NSString *> *serviceNames = [NSMutableArray array];
    BOOL hasFE1F = NO;
    BOOL hasGarminV2 = NO;
    for (CBUUID *uuid in services) {
        NSString *uuidString = [uuid.UUIDString uppercaseString] ?: @"";
        if (!uuidString.length || [serviceNames containsObject:uuidString]) continue;
        [serviceNames addObject:uuidString];
        if ([uuidString isEqualToString:@"FE1F"]) hasFE1F = YES;
        if ([uuidString isEqualToString:GNV2ServiceUUID] || [uuidString hasPrefix:@"6A4E28"]) hasGarminV2 = YES;
    }
    BOOL isConnectable = [advertisementData[CBAdvertisementDataIsConnectable] boolValue];
    NSData *manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey];
    BOOL looksGarmin = hasFE1F || hasGarminV2 || [name.lowercaseString containsString:@"garmin"] || [name.lowercaseString containsString:@"fenix"];
    [self.trace recordLayer:@"adv" direction:@"rx" data:[NSData data] metadata:@{
        @"name": name ?: @"",
        @"rssi": RSSI ?: @0,
        @"services": [serviceNames componentsJoinedByString:@","],
        @"manufacturer": manufacturerData ? GNLocalHex(manufacturerData) : @"",
        @"connectable": @(isConnectable),
        @"garminCandidate": @(looksGarmin)
    }];
    if (looksGarmin) {
        [self.garminIdentifiers addObject:peripheral.identifier];
    }
    if (![self.discovered containsObject:peripheral]) {
        NSString *label = name.length ? name : @"Unnamed";
        [self log:[NSString stringWithFormat:@"Seen BLE%@ %@ %@ RSSI=%@ services=%@",
                   looksGarmin ? @" candidate" : @"",
                   label,
                   peripheral.identifier.UUIDString,
                   RSSI,
                   serviceNames.count ? [serviceNames componentsJoinedByString:@","] : @"none"]];
        if (isConnectable || looksGarmin) {
            if (looksGarmin) {
                [self.discovered insertObject:peripheral atIndex:0];
                [self updateStatus:@"Garmin candidate found. Auto-connecting..."];
                if (!self.autoConnectAttempted) {
                    self.autoConnectAttempted = YES;
                    [self log:@"Auto-connect triggered for Garmin candidate."];
                    [self connectFirstDiscoveredPeripheral];
                }
            } else {
                [self.discovered addObject:peripheral];
                [self updateStatus:[NSString stringWithFormat:@"Saw %lu connectable BLE device(s). Waiting for Garmin...",
                                    (unsigned long)self.discovered.count]];
            }
        }
    }
}

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral {
    (void)central;
    [self log:[NSString stringWithFormat:@"Connected: %@", peripheral.description]];
    if ([peripheral respondsToSelector:@selector(maximumWriteValueLengthForType:)]) {
        NSUInteger withoutResponse = [peripheral maximumWriteValueLengthForType:CBCharacteristicWriteWithoutResponse];
        NSUInteger withResponse = [peripheral maximumWriteValueLengthForType:CBCharacteristicWriteWithResponse];
        [self log:[NSString stringWithFormat:@"Native write limits: withoutResponse=%lu withResponse=%lu", (unsigned long)withoutResponse, (unsigned long)withResponse]];
        if (withoutResponse > 0) self.bleFragmentSize = MIN(self.bleFragmentSize, withoutResponse);
    }
    [self log:@"Discovering all services so we can map Garmin pairing mode."];
    [peripheral discoverServices:nil];
}

- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    (void)central;
    (void)peripheral;
    self.readyForUpload = NO;
    [self log:[NSString stringWithFormat:@"Disconnected: %@", error.localizedDescription ?: @"nil"]];
    [self updateStatus:@"Disconnected."];
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error {
    if (error) {
        [self log:[NSString stringWithFormat:@"Service discovery failed: %@", error.localizedDescription]];
        return;
    }
    for (CBService *service in peripheral.services) {
        [self log:[NSString stringWithFormat:@"Service %@", service.UUID.UUIDString]];
        if ([[service.UUID.UUIDString uppercaseString] isEqualToString:GNV2ServiceUUID]) {
            [peripheral discoverCharacteristics:nil forService:service];
        } else if ([[service.UUID.UUIDString uppercaseString] isEqualToString:GNFE1FServiceUUID]) {
            [self log:@"FE1F pairing/advertising service is present; discovering its characteristics too."];
            [peripheral discoverCharacteristics:nil forService:service];
        }
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error {
    (void)service;
    if (error) {
        [self log:[NSString stringWithFormat:@"Characteristic discovery failed: %@", error.localizedDescription]];
        return;
    }
    NSMutableDictionary<NSString *, CBCharacteristic *> *byShort = [NSMutableDictionary dictionary];
    for (CBCharacteristic *characteristic in service.characteristics) {
        NSString *uuid = [characteristic.UUID.UUIDString uppercaseString];
        [self log:[NSString stringWithFormat:@"Characteristic %@ properties=0x%lx", uuid, (unsigned long)characteristic.properties]];
        if ([uuid hasPrefix:@"6A4E28"]) {
            NSString *shortPart = [uuid substringWithRange:NSMakeRange(4, 4)];
            byShort[shortPart] = characteristic;
        }
    }
    for (NSUInteger value = 0x2810; value <= 0x2814; value++) {
        NSString *rxKey = [NSString stringWithFormat:@"%04lX", (unsigned long)value];
        NSString *txKey = [NSString stringWithFormat:@"%04lX", (unsigned long)(value + 0x10)];
        if (byShort[rxKey] && byShort[txKey]) {
            self.rx = byShort[rxKey];
            self.tx = byShort[txKey];
            [self log:[NSString stringWithFormat:@"Using Garmin v2 pair %@/%@", rxKey, txKey]];
            [peripheral setNotifyValue:YES forCharacteristic:self.rx];
            return;
        }
    }
    [self log:@"No Garmin v2 281x/282x pair found."];
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    (void)peripheral;
    if (error) {
        [self log:[NSString stringWithFormat:@"Notify enable failed: %@", error.localizedDescription]];
        return;
    }
    if (characteristic == self.rx && characteristic.isNotifying) {
        [self log:@"Notifications enabled. Closing existing ML handles."];
        [self writeRaw:[self closeAllPacket] label:@"ML close all"];
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    (void)peripheral;
    if (error) {
        [self log:[NSString stringWithFormat:@"Notify failed: %@", error.localizedDescription]];
        return;
    }
    NSData *data = characteristic.value ?: [NSData data];
    [self.trace recordLayer:@"ble" direction:@"rx" data:data metadata:@{@"characteristic": characteristic.UUID.UUIDString ?: @""}];
    [self handleNotify:data];
}

- (void)handleNotify:(NSData *)data {
    if (!data.length) return;
    const uint8_t *bytes = data.bytes;
    if ((bytes[0] & GNMlrFlagMask) && self.mlrActive) {
        [self handleMlrPacket:data];
        return;
    }
    uint8_t handle = bytes[0];
    NSData *body = [data subdataWithRange:NSMakeRange(1, data.length - 1)];
    if (handle == 0) {
        [self handleManagement:body];
    } else if (self.hasGfdiHandle && handle == self.gfdiHandle) {
        [self feedGfdiBytes:body];
    }
}

- (void)handleManagement:(NSData *)body {
    if (body.length < 9) return;
    const uint8_t *bytes = body.bytes;
    uint8_t request = bytes[0];
    uint64_t client = 0;
    for (NSUInteger i = 0; i < 8; i++) client |= ((uint64_t)bytes[1 + i]) << (8 * i);
    if (client != GNGadgetbridgeClientID) return;
    if (request == 6) {
        [self log:@"Close-all acknowledged. Registering GFDI service."];
        [self writeRaw:[self registerGfdiPacket] label:@"ML register GFDI"];
        return;
    }
    if (request == 1 && body.length >= 14) {
        uint16_t service = GNReadU16(body, 9);
        uint8_t status = bytes[11];
        uint8_t handle = bytes[12];
        uint8_t reliable = bytes[13];
        if (service != 1) return;
        if (status != 0) {
            [self log:[NSString stringWithFormat:@"GFDI registration rejected status=%u", status]];
            return;
        }
        self.gfdiHandle = handle;
        self.hasGfdiHandle = YES;
        self.mlrActive = reliable != 0;
        [self resetMlr];
        self.readyForUpload = YES;
        [self log:[NSString stringWithFormat:@"GFDI registered handle=%u reliableMLR=%@", handle, self.mlrActive ? @"yes" : @"no"]];
        [self updateStatus:@"Ready. Tap Upload PRG."];
    }
}

- (void)feedGfdiBytes:(NSData *)data {
    NSError *error = nil;
    NSArray<NSData *> *messages = [self.decoder feed:data error:&error];
    if (error) [self log:[NSString stringWithFormat:@"COBS decode error: %@", error.localizedDescription]];
    for (NSData *message in messages) {
        [self.trace recordLayer:@"gfdi" direction:@"rx" data:message metadata:@{}];
        [self enqueueDecodedGfdi:message];
    }
}

- (void)enqueueDecodedGfdi:(NSData *)packet {
    NSError *error = nil;
    NSDictionary *status = GNParseGFDIStatus(packet, &error);
    if (error) {
        [self log:[NSString stringWithFormat:@"GFDI parse error: %@", error.localizedDescription]];
        return;
    }
    for (GNStatusWaiter *waiter in [self.waiters copy]) {
        if (waiter.matcher(status)) {
            waiter.result = status;
            [self.waiters removeObject:waiter];
            dispatch_semaphore_signal(waiter.semaphore);
            return;
        }
    }
    [self.decodedQueue addObject:packet];
}

- (NSData *)closeAllPacket {
    NSMutableData *packet = [NSMutableData data];
    uint8_t values[] = {0, 5};
    [packet appendBytes:values length:2];
    for (NSUInteger i = 0; i < 8; i++) {
        uint8_t b = (uint8_t)((GNGadgetbridgeClientID >> (8 * i)) & 0xff);
        [packet appendBytes:&b length:1];
    }
    uint8_t zeros[] = {0, 0};
    [packet appendBytes:zeros length:2];
    return packet;
}

- (NSData *)registerGfdiPacket {
    NSMutableData *packet = [NSMutableData data];
    uint8_t header[] = {0, 0};
    [packet appendBytes:header length:2];
    for (NSUInteger i = 0; i < 8; i++) {
        uint8_t b = (uint8_t)((GNGadgetbridgeClientID >> (8 * i)) & 0xff);
        [packet appendBytes:&b length:1];
    }
    uint8_t service[] = {1, 0, self.reliableMlr ? 2 : 0};
    [packet appendBytes:service length:3];
    return packet;
}

- (void)writeRaw:(NSData *)data label:(NSString *)label {
    if (!data.length || !self.tx || self.stopped) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.trace recordLayer:@"ble" direction:@"tx" data:data metadata:@{@"label": label ?: @"", @"characteristic": self.tx.UUID.UUIDString ?: @""}];
        [self.peripheral writeValue:data forCharacteristic:self.tx type:CBCharacteristicWriteWithoutResponse];
    });
}

- (void)sendGfdi:(NSData *)packet label:(NSString *)label {
    [self.trace recordLayer:@"gfdi" direction:@"tx" data:packet metadata:@{@"label": label ?: @""}];
    NSData *encoded = GNCobsEncode(packet);
    if (self.mlrActive) {
        [self performOnMainSync:^{
            [self enqueueMlrMessageOnMain:encoded];
        }];
        return;
    }
    NSUInteger payloadSize = MAX(1, self.bleFragmentSize - 1);
    for (NSUInteger offset = 0; offset < encoded.length; offset += payloadSize) {
        NSUInteger len = MIN(payloadSize, encoded.length - offset);
        NSMutableData *fragment = [NSMutableData dataWithCapacity:len + 1];
        uint8_t handle = self.gfdiHandle;
        [fragment appendBytes:&handle length:1];
        [fragment appendData:[encoded subdataWithRange:NSMakeRange(offset, len)]];
        [self writeRaw:fragment label:label];
    }
}

- (void)resetMlr {
    self.lastSendAck = 0;
    self.nextSendSeq = 0;
    self.nextRcvSeq = 0;
    self.lastRcvAck = 0;
    self.mlrWindow = GNMlrInitialWindow;
    self.retransmissionTimeout = 1.0;
    self.retransmissionGeneration += 1;
    [self.mlrQueue removeAllObjects];
    for (GNSentFragment *fragment in self.sentFragments) fragment.packet = nil;
}

- (void)enqueueMlrMessageOnMain:(NSData *)message {
    NSUInteger payloadSize = MAX(1, self.bleFragmentSize - 2);
    [self log:[NSString stringWithFormat:@"MLR shape: %lu encoded bytes, BLE write %lu, MLR payload %lu",
               (unsigned long)message.length,
               (unsigned long)self.bleFragmentSize,
               (unsigned long)payloadSize]];
    for (NSUInteger offset = 0; offset < message.length; offset += payloadSize) {
        NSUInteger len = MIN(payloadSize, message.length - offset);
        [self.mlrQueue addObject:[message subdataWithRange:NSMakeRange(offset, len)]];
    }
    [self pumpMlr];
}

- (void)pumpMlr {
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL wrote = NO;
        while (!self.stopped && self.mlrQueue.count && [self mlrUnackedCount] < self.mlrWindow) {
            NSData *payload = self.mlrQueue.firstObject;
            [self.mlrQueue removeObjectAtIndex:0];
            uint8_t req = self.nextRcvSeq;
            uint8_t seq = self.nextSendSeq;
            NSMutableData *packet = [NSMutableData dataWithCapacity:payload.length + 2];
            uint8_t b0 = GNMlrFlagMask | ((self.gfdiHandle & 0x07) << 4) | ((req >> 2) & GNMlrReqMask);
            uint8_t b1 = ((req & 0x03) << 6) | (seq & GNMlrSeqMask);
            [packet appendBytes:&b0 length:1];
            [packet appendBytes:&b1 length:1];
            [packet appendData:payload];
            self.sentFragments[seq].packet = packet;
            self.nextSendSeq = [self nextSeq:self.nextSendSeq];
            [self writeRaw:packet label:@"MLR data"];
            wrote = YES;
        }
        if (wrote || [self mlrUnackedCount] > 0) [self scheduleRetransmission];
    });
}

- (void)handleMlrPacket:(NSData *)packet {
    if (packet.length < 2) return;
    const uint8_t *bytes = packet.bytes;
    uint8_t handle = (bytes[0] & GNMlrHandleMask) >> 4;
    if (handle != (self.gfdiHandle & 0x07)) return;
    uint8_t req = ((bytes[0] & GNMlrReqMask) << 2) | ((bytes[1] >> 6) & 0x03);
    uint8_t seq = bytes[1] & GNMlrSeqMask;
    if (req != self.lastRcvAck) [self processMlrAck:req];
    if (packet.length <= 2) return;
    if (seq == self.nextRcvSeq) {
        [self feedGfdiBytes:[packet subdataWithRange:NSMakeRange(2, packet.length - 2)]];
        self.nextRcvSeq = [self nextSeq:self.nextRcvSeq];
        [self scheduleMlrAck];
    } else {
        [self log:[NSString stringWithFormat:@"MLR out of sequence: expected %u got %u", self.nextRcvSeq, seq]];
        [self sendMlrAck];
    }
}

- (void)processMlrAck:(uint8_t)req {
    uint8_t acked = [self sequenceDistanceFrom:self.lastRcvAck to:req];
    if (!acked) return;
    for (uint8_t seq = self.lastRcvAck; seq != req; seq = [self nextSeq:seq]) {
        self.sentFragments[seq].packet = nil;
    }
    self.lastRcvAck = req;
    self.retransmissionTimeout = 1.0;
    self.retransmissionGeneration += 1;
    if ([self mlrUnackedCount] > 0) [self scheduleRetransmission];
    [self pumpMlr];
}

- (void)scheduleRetransmission {
    if ([self mlrUnackedCount] == 0) return;
    self.retransmissionGeneration += 1;
    NSUInteger generation = self.retransmissionGeneration;
    NSTimeInterval timeout = self.retransmissionTimeout;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.stopped || generation != self.retransmissionGeneration || [self mlrUnackedCount] == 0) return;
        self.mlrWindow = MAX((NSUInteger)1, self.mlrWindow / 2);
        self.retransmissionTimeout = MIN(self.retransmissionTimeout * 2.0, 20.0);
        [self log:[NSString stringWithFormat:@"MLR retransmission timeout; window now %lu", (unsigned long)self.mlrWindow]];
        for (uint8_t seq = self.lastRcvAck; seq != self.nextSendSeq; seq = [self nextSeq:seq]) {
            NSData *packet = self.sentFragments[seq].packet;
            if (packet) [self writeRaw:packet label:@"MLR retransmit"];
        }
        [self scheduleRetransmission];
    });
}

- (void)scheduleMlrAck {
    uint8_t pending = [self sequenceDistanceFrom:self.lastSendAck to:self.nextRcvSeq];
    if (pending >= 5) {
        [self sendMlrAck];
        return;
    }
    uint8_t expected = self.nextRcvSeq;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(20 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
        if (self.nextRcvSeq == expected) [self sendMlrAck];
    });
}

- (void)sendMlrAck {
    uint8_t req = self.nextRcvSeq;
    uint8_t seq = 0;
    NSMutableData *packet = [NSMutableData dataWithCapacity:2];
    uint8_t b0 = GNMlrFlagMask | ((self.gfdiHandle & 0x07) << 4) | ((req >> 2) & GNMlrReqMask);
    uint8_t b1 = ((req & 0x03) << 6) | (seq & GNMlrSeqMask);
    [packet appendBytes:&b0 length:1];
    [packet appendBytes:&b1 length:1];
    self.lastSendAck = self.nextRcvSeq;
    [self writeRaw:packet label:@"MLR ACK"];
}

- (uint8_t)nextSeq:(uint8_t)value {
    return (value + 1) & GNMlrMaxSeq;
}

- (uint8_t)sequenceDistanceFrom:(uint8_t)from to:(uint8_t)to {
    return (to - from + GNMlrMaxSeq + 1) % (GNMlrMaxSeq + 1);
}

- (NSUInteger)mlrUnackedCount {
    return [self sequenceDistanceFrom:self.lastRcvAck to:self.nextSendSeq];
}

- (void)runUpload:(NSData *)data {
    self.uploadStartedAt = [NSDate date];
    [self log:@"Sending SYNC_READY."];
    [self sendGfdi:GNBuildSystemEvent(GNSystemEventSyncReady, 0) label:@"SYNC_READY"];
    if (![self waitForOriginal:GNGarminMessageSystemEvent timeout:GNGfdiTimeout]) return;

    [self log:[NSString stringWithFormat:@"Creating PRG file slot (%lu bytes).", (unsigned long)data.length]];
    [self sendGfdi:GNBuildCreateFile(data.length) label:@"CREATE_FILE"];
    NSDictionary *create = [self waitForKind:@"createFile" timeout:GNGfdiTimeout];
    if (!create || [create[@"status"] unsignedCharValue] != 0 || [create[@"createStatus"] unsignedCharValue] != 0) {
        [self log:[NSString stringWithFormat:@"Create file failed: %@", create]];
        return;
    }
    uint16_t fileIndex = [create[@"fileIndex"] unsignedShortValue];
    [self progress:0 total:data.length];

    [self log:[NSString stringWithFormat:@"Starting upload to file index %u.", fileIndex]];
    [self sendGfdi:GNBuildUploadRequest(fileIndex, data.length, 0, 0) label:@"UPLOAD_REQUEST"];
    NSDictionary *upload = [self waitForKind:@"uploadRequest" timeout:GNGfdiTimeout];
    if (!upload || [upload[@"status"] unsignedCharValue] != 0 || [upload[@"uploadStatus"] unsignedCharValue] != 0) {
        [self log:[NSString stringWithFormat:@"Upload request failed: %@", upload]];
        return;
    }
    uint32_t offset = [upload[@"dataOffset"] unsignedIntValue];
    uint16_t seed = [upload[@"crcSeed"] unsignedShortValue];
    GNUploadChunker *chunker = [[GNUploadChunker alloc] initWithData:data
                                                       maxPacketSize:self.gfdiPacketSize
                                                       initialOffset:offset
                                                          initialCRC:seed];
    [self progress:offset total:data.length];

    while (!self.stopped) {
        NSMutableArray<NSDictionary *> *batch = [NSMutableArray array];
        for (NSUInteger i = 0; i < MAX(1, self.pipelineWindow); i++) {
            NSDictionary *chunk = [chunker nextChunkUntil:data.length];
            if (!chunk) break;
            NSData *packet = GNBuildFileTransferData(chunk[@"data"], [chunk[@"offset"] unsignedIntValue], [chunk[@"crc"] unsignedShortValue]);
            [self sendGfdi:packet label:@"FILE_TRANSFER_DATA"];
            [batch addObject:chunk];
        }
        if (!batch.count) break;
        for (NSDictionary *chunk in batch) {
            NSDictionary *status = [self waitForKind:@"fileTransferData" timeout:GNGfdiTimeout];
            if (!status || [status[@"status"] unsignedCharValue] != 0 || [status[@"transferStatus"] unsignedCharValue] != 0) {
                [self log:[NSString stringWithFormat:@"File transfer failed near offset %@: %@", chunk[@"offset"], status]];
                return;
            }
            uint32_t expected = [chunk[@"offset"] unsignedIntValue] + (uint32_t)[chunk[@"data"] length];
            uint32_t acked = [status[@"dataOffset"] unsignedIntValue];
            if (acked != expected) {
                [self log:[NSString stringWithFormat:@"Offset mismatch: expected %u got %u", expected, acked]];
                return;
            }
            [self progress:acked total:data.length];
        }
    }

    [self log:@"Sending SYNC_COMPLETE."];
    [self sendGfdi:GNBuildSystemEvent(GNSystemEventSyncComplete, 0) label:@"SYNC_COMPLETE"];
    [self waitForOriginal:GNGarminMessageSystemEvent timeout:GNGfdiTimeout];
    [self log:@"Sending DEVICE_DISCONNECT registration trigger."];
    [self sendGfdi:GNBuildSystemEvent(GNSystemEventDeviceDisconnect, 0) label:@"DEVICE_DISCONNECT"];
    [self waitForOriginal:GNGarminMessageSystemEvent timeout:5.0];
    NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:self.uploadStartedAt];
    double kbps = elapsed > 0 ? (double)data.length / 1024.0 / elapsed : 0;
    [self log:[NSString stringWithFormat:@"Upload complete. %.1f KB/s average over %.0fs.", kbps, elapsed]];
    [self updateStatus:@"Upload complete. Watch should disconnect/index if trigger worked."];
}

- (NSDictionary *)waitForKind:(NSString *)kind timeout:(NSTimeInterval)timeout {
    return [self waitForStatusMatching:^BOOL(NSDictionary *status) {
        return [status[@"kind"] isEqualToString:kind];
    } timeout:timeout];
}

- (BOOL)waitForOriginal:(uint16_t)messageType timeout:(NSTimeInterval)timeout {
    NSDictionary *status = [self waitForStatusMatching:^BOOL(NSDictionary *candidate) {
        return [candidate[@"originalMessageType"] unsignedShortValue] == messageType;
    } timeout:timeout];
    return status && [status[@"status"] unsignedCharValue] == 0;
}

- (NSDictionary *)waitForStatusMatching:(GNStatusMatcher)matcher timeout:(NSTimeInterval)timeout {
    __block GNStatusWaiter *waiter = [GNStatusWaiter new];
    waiter.matcher = matcher;
    waiter.semaphore = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_main_queue(), ^{
        for (NSData *packet in [self.decodedQueue copy]) {
            NSError *error = nil;
            NSDictionary *status = GNParseGFDIStatus(packet, &error);
            if (!error && matcher(status)) {
                waiter.result = status;
                [self.decodedQueue removeObject:packet];
                dispatch_semaphore_signal(waiter.semaphore);
                return;
            }
        }
        [self.waiters addObject:waiter];
    });
    long result = dispatch_semaphore_wait(waiter.semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)));
    if (result != 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.waiters removeObject:waiter];
        });
        [self log:@"Timed out waiting for Garmin status packet."];
        return nil;
    }
    return waiter.result;
}

- (void)performOnMainSync:(dispatch_block_t)block {
    if ([NSThread isMainThread]) {
        block();
    } else {
        dispatch_sync(dispatch_get_main_queue(), block);
    }
}

- (void)log:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate senderDidLog:message];
    });
}

- (void)updateStatus:(NSString *)status {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate senderDidUpdateStatus:status];
    });
}

- (void)progress:(NSUInteger)offset total:(NSUInteger)total {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate senderDidUpdateProgressOffset:offset total:total];
    });
}

@end
