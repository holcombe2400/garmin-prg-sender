from __future__ import annotations

import os
import struct
from dataclasses import dataclass
from enum import IntEnum
from pathlib import Path
from typing import Optional


PRG_MAGIC = b"\xd0\x00\xd0"
PRG_TYPE = 255
PRG_SUBTYPE = 17
MAX_EXPECTED_PRG_SIZE = 10 * 1024 * 1024


class GarminMessage(IntEnum):
    RESPONSE = 5000
    DOWNLOAD_REQUEST = 5002
    UPLOAD_REQUEST = 5003
    FILE_TRANSFER_DATA = 5004
    CREATE_FILE = 5005
    SET_FILE_FLAG = 5008
    FIT_DEFINITION = 5011
    FIT_DATA = 5012
    WEATHER_REQUEST = 5014
    DEVICE_INFORMATION = 5024
    DEVICE_SETTINGS = 5026
    SYSTEM_EVENT = 5030
    SUPPORTED_FILE_TYPES_REQUEST = 5031
    NOTIFICATION_UPDATE = 5033
    NOTIFICATION_CONTROL = 5034
    NOTIFICATION_DATA = 5035
    NOTIFICATION_SUBSCRIPTION = 5036
    SYNCHRONIZATION = 5037
    FIND_MY_PHONE_REQUEST = 5039
    FIND_MY_PHONE_CANCEL = 5040
    MUSIC_CONTROL = 5041
    MUSIC_CONTROL_CAPABILITIES = 5042
    PROTOBUF_REQUEST = 5043
    PROTOBUF_RESPONSE = 5044
    MUSIC_CONTROL_ENTITY_UPDATE = 5049
    CONFIGURATION = 5050
    CURRENT_TIME_REQUEST = 5052
    AUTH_NEGOTIATION = 5101


class Status(IntEnum):
    ACK = 0
    NAK = 1
    UNSUPPORTED = 2
    DECODE_ERROR = 3
    CRC_ERROR = 4
    LENGTH_ERROR = 5


class CreateStatus(IntEnum):
    OK = 0
    DUPLICATE = 1
    NO_SPACE = 2
    UNSUPPORTED = 3
    NO_SLOTS = 4
    NO_SPACE_FOR_TYPE = 5


class UploadStatus(IntEnum):
    OK = 0
    INDEX_UNKNOWN = 1
    INDEX_NOT_WRITEABLE = 2
    NO_SPACE_LEFT = 3
    INVALID = 4
    NOT_READY = 5
    CRC_INCORRECT = 6


class TransferStatus(IntEnum):
    OK = 0
    RESEND = 1
    ABORT = 2
    CRC_MISMATCH = 3
    OFFSET_MISMATCH = 4
    SYNC_PAUSED = 5


class FlagsStatus(IntEnum):
    APPLIED = 0
    ERROR = 1


class ProtobufChunkStatus(IntEnum):
    KEPT = 0
    DISCARDED = 1


class ProtobufStatusCode(IntEnum):
    NO_ERROR = 0
    UNKNOWN_REQUEST_ID = 100
    DUPLICATE_PACKET = 101
    MISSING_PACKET = 102
    EXCEEDED_TOTAL_PROTOBUF_LENGTH = 103
    PROTOBUF_PARSE_ERROR = 200
    UNKNOWN = 201


class SystemEvent(IntEnum):
    SYNC_COMPLETE = 0
    SYNC_FAIL = 1
    FACTORY_RESET = 2
    PAIR_START = 3
    PAIR_COMPLETE = 4
    PAIR_FAIL = 5
    HOST_DID_ENTER_FOREGROUND = 6
    HOST_DID_ENTER_BACKGROUND = 7
    SYNC_READY = 8
    NEW_DOWNLOAD_AVAILABLE = 9
    DEVICE_SOFTWARE_UPDATE = 10
    DEVICE_DISCONNECT = 11
    TUTORIAL_COMPLETE = 12
    SETUP_WIZARD_START = 13
    SETUP_WIZARD_COMPLETE = 14
    SETUP_WIZARD_SKIPPED = 15
    TIME_UPDATED = 16


INSTALL_SYNC_BIT = 1 << 17
SET_FILE_FLAG_ARCHIVE = 0x10


class ProtocolError(RuntimeError):
    pass


@dataclass(frozen=True)
class ParsedMessage:
    message_type: int
    raw: bytes


@dataclass(frozen=True)
class CreateFileStatus:
    status: Status
    create_status: CreateStatus
    file_index: int
    data_type: int
    subtype: int
    file_number: int

    @property
    def can_proceed(self) -> bool:
        return self.status == Status.ACK and self.create_status == CreateStatus.OK


@dataclass(frozen=True)
class UploadRequestStatus:
    status: Status
    upload_status: UploadStatus
    data_offset: int
    max_file_size: int
    crc_seed: int

    @property
    def can_proceed(self) -> bool:
        return self.status == Status.ACK and self.upload_status == UploadStatus.OK


@dataclass(frozen=True)
class FileTransferDataStatus:
    status: Status
    transfer_status: TransferStatus
    data_offset: int

    @property
    def can_proceed(self) -> bool:
        return self.status == Status.ACK and self.transfer_status == TransferStatus.OK


@dataclass(frozen=True)
class GenericStatus:
    original_message_type: int
    status: Status

    @property
    def can_proceed(self) -> bool:
        return self.status == Status.ACK


@dataclass(frozen=True)
class SetFileFlagsStatus:
    status: Status
    flags_status: FlagsStatus | int
    file_identifier: int
    flags: int

    @property
    def can_proceed(self) -> bool:
        return self.status == Status.ACK and self.flags_status == FlagsStatus.APPLIED


@dataclass(frozen=True)
class SupportedFileType:
    data_type: int
    subtype: int
    name: str

    @property
    def is_prg(self) -> bool:
        return self.data_type == PRG_TYPE and self.subtype == PRG_SUBTYPE


@dataclass(frozen=True)
class SupportedFileTypesStatus:
    status: Status
    file_types: tuple[SupportedFileType, ...]

    @property
    def can_proceed(self) -> bool:
        return self.status == Status.ACK


@dataclass(frozen=True)
class ProtobufPacket:
    message_type: int
    request_id: int
    data_offset: int
    total_length: int
    data_length: int
    data: bytes

    @property
    def is_single_packet(self) -> bool:
        return self.data_offset == 0 and self.total_length == self.data_length

    @property
    def end_offset(self) -> int:
        return self.data_offset + self.data_length


@dataclass(frozen=True)
class ProtobufStatus:
    original_message_type: int
    status: Status
    request_id: int
    data_offset: int
    chunk_status: ProtobufChunkStatus | int
    status_code: ProtobufStatusCode | int

    @property
    def can_proceed(self) -> bool:
        return (
            self.status == Status.ACK
            and self.chunk_status == ProtobufChunkStatus.KEPT
            and self.status_code == ProtobufStatusCode.NO_ERROR
        )


CRC_CONSTANTS = (
    0x0000,
    0xCC01,
    0xD801,
    0x1400,
    0xF001,
    0x3C00,
    0x2800,
    0xE401,
    0xA001,
    0x6C00,
    0x7800,
    0xB401,
    0x5000,
    0x9C01,
    0x8801,
    0x4400,
)


def garmin_crc(data: bytes, initial_crc: int = 0) -> int:
    crc = initial_crc & 0xFFFF
    for b in data:
        crc = (((crc >> 4) & 0x0FFF) ^ CRC_CONSTANTS[crc & 0x0F]) ^ CRC_CONSTANTS[b & 0x0F]
        crc = (((crc >> 4) & 0x0FFF) ^ CRC_CONSTANTS[crc & 0x0F]) ^ CRC_CONSTANTS[(b >> 4) & 0x0F]
    return crc & 0xFFFF


def frame_gfdi(message_type: int, payload: bytes = b"") -> bytes:
    body = struct.pack("<HH", 0, message_type) + payload
    length = len(body) + 2
    body = struct.pack("<H", length) + body[2:]
    crc = garmin_crc(body)
    return body + struct.pack("<H", crc)


def parse_gfdi(
    packet: bytes,
) -> (
    ParsedMessage
    | CreateFileStatus
    | UploadRequestStatus
    | FileTransferDataStatus
    | GenericStatus
    | SetFileFlagsStatus
    | SupportedFileTypesStatus
    | ProtobufPacket
    | ProtobufStatus
):
    if len(packet) < 6:
        raise ProtocolError(f"GFDI packet too short: {len(packet)} bytes")
    (length,) = struct.unpack_from("<H", packet, 0)
    if length != len(packet):
        raise ProtocolError(f"GFDI length mismatch: header={length}, actual={len(packet)}")
    expected_crc = struct.unpack_from("<H", packet, length - 2)[0]
    actual_crc = garmin_crc(packet[:-2])
    if expected_crc != actual_crc:
        raise ProtocolError(f"GFDI CRC mismatch: expected=0x{expected_crc:04x}, actual=0x{actual_crc:04x}")

    payload = packet[2:-2]
    message_type = struct.unpack_from("<H", payload, 0)[0]
    if message_type & 0x8000:
        message_type = (message_type & 0xFF) + 5000
    body = payload[2:]

    if message_type != GarminMessage.RESPONSE:
        if message_type in (GarminMessage.PROTOBUF_REQUEST, GarminMessage.PROTOBUF_RESPONSE):
            return _parse_protobuf_packet(message_type, body)
        return ParsedMessage(message_type=message_type, raw=body)

    if len(body) < 3:
        raise ProtocolError("Status packet body is too short")
    original = struct.unpack_from("<H", body, 0)[0]
    status = Status(body[2])
    rest = body[3:]

    if original == GarminMessage.CREATE_FILE:
        if status != Status.ACK:
            return GenericStatus(original, status)
        if len(rest) < 7:
            raise ProtocolError("CREATE_FILE status body is too short")
        create_status = CreateStatus(rest[0])
        file_index = struct.unpack_from("<H", rest, 1)[0]
        data_type = rest[3]
        subtype = rest[4]
        file_number = struct.unpack_from("<H", rest, 5)[0]
        return CreateFileStatus(status, create_status, file_index, data_type, subtype, file_number)

    if original == GarminMessage.UPLOAD_REQUEST:
        if status != Status.ACK:
            return GenericStatus(original, status)
        if len(rest) < 11:
            raise ProtocolError("UPLOAD_REQUEST status body is too short")
        upload_status = UploadStatus(rest[0])
        data_offset, max_file_size, crc_seed = struct.unpack_from("<IIH", rest, 1)
        return UploadRequestStatus(status, upload_status, data_offset, max_file_size, crc_seed)

    if original == GarminMessage.FILE_TRANSFER_DATA:
        if status != Status.ACK:
            return GenericStatus(original, status)
        if len(rest) < 5:
            raise ProtocolError("FILE_TRANSFER_DATA status body is too short")
        transfer_status = TransferStatus(rest[0])
        (data_offset,) = struct.unpack_from("<I", rest, 1)
        return FileTransferDataStatus(status, transfer_status, data_offset)

    if original == GarminMessage.SET_FILE_FLAG:
        if status != Status.ACK:
            return GenericStatus(original, status)
        if len(rest) < 4:
            raise ProtocolError("SET_FILE_FLAG status body is too short")
        flags_status = _flags_status(rest[0])
        # Gadgetbridge adds one here; keep the raw command file index semantics in this sender.
        file_identifier = struct.unpack_from("<H", rest, 1)[0]
        flags = rest[3]
        return SetFileFlagsStatus(status, flags_status, file_identifier, flags)

    if original == GarminMessage.SUPPORTED_FILE_TYPES_REQUEST:
        if status != Status.ACK:
            return GenericStatus(original, status)
        return _parse_supported_file_types_status(status, rest)

    if original in (GarminMessage.PROTOBUF_REQUEST, GarminMessage.PROTOBUF_RESPONSE) and rest:
        if len(rest) < 8:
            raise ProtocolError("PROTOBUF status body is too short")
        request_id, data_offset = struct.unpack_from("<HI", rest, 0)
        chunk_status = _protobuf_chunk_status(rest[6])
        status_code = _protobuf_status_code(rest[7])
        return ProtobufStatus(original, status, request_id, data_offset, chunk_status, status_code)

    return GenericStatus(original, status)


def _flags_status(value: int) -> FlagsStatus | int:
    try:
        return FlagsStatus(value)
    except ValueError:
        return value


def _parse_supported_file_types_status(status: Status, body: bytes) -> SupportedFileTypesStatus:
    if not body:
        raise ProtocolError("SUPPORTED_FILE_TYPES status body is too short")
    count = body[0]
    offset = 1
    file_types: list[SupportedFileType] = []
    for _ in range(count):
        if offset + 3 > len(body):
            raise ProtocolError("SUPPORTED_FILE_TYPES entry is truncated")
        data_type = body[offset]
        subtype = body[offset + 1]
        name_length = body[offset + 2]
        offset += 3
        end = offset + name_length
        if end > len(body):
            raise ProtocolError("SUPPORTED_FILE_TYPES name is truncated")
        name = body[offset:end].decode("utf-8", errors="replace")
        offset = end
        file_types.append(SupportedFileType(data_type, subtype, name))
    return SupportedFileTypesStatus(status, tuple(file_types))


def _parse_protobuf_packet(message_type: int, body: bytes) -> ProtobufPacket:
    if len(body) < 14:
        raise ProtocolError("PROTOBUF packet body is too short")
    request_id, data_offset, total_length, data_length = struct.unpack_from("<HIII", body, 0)
    data = body[14:]
    if len(data) != data_length:
        raise ProtocolError(f"PROTOBUF payload length mismatch: header={data_length}, actual={len(data)}")
    if data_offset + data_length > total_length:
        raise ProtocolError("PROTOBUF payload runs past total length")
    return ProtobufPacket(message_type, request_id, data_offset, total_length, data_length, data)


def _protobuf_chunk_status(value: int) -> ProtobufChunkStatus | int:
    try:
        return ProtobufChunkStatus(value)
    except ValueError:
        return value


def _protobuf_status_code(value: int) -> ProtobufStatusCode | int:
    try:
        return ProtobufStatusCode(value)
    except ValueError:
        return value


def build_create_file(file_size: int, *, nonce: Optional[int] = None) -> bytes:
    if nonce is None:
        nonce = int.from_bytes(os.urandom(8), "little", signed=False)
    payload = struct.pack(
        "<IBBHBBHHQ",
        file_size,
        PRG_TYPE,
        PRG_SUBTYPE,
        0,
        0,
        0,
        0xFFFF,
        0,
        nonce & 0xFFFFFFFFFFFFFFFF,
    )
    return frame_gfdi(GarminMessage.CREATE_FILE, payload)


def build_upload_request(file_index: int, file_size: int, data_offset: int = 0, crc_seed: int = 0) -> bytes:
    payload = struct.pack("<HIIH", file_index, file_size, data_offset, crc_seed)
    return frame_gfdi(GarminMessage.UPLOAD_REQUEST, payload)


def build_file_transfer_data(chunk: bytes, data_offset: int, running_crc: int) -> bytes:
    payload = struct.pack("<BHI", 0, running_crc, data_offset) + chunk
    return frame_gfdi(GarminMessage.FILE_TRANSFER_DATA, payload)


def build_system_event(event: SystemEvent, value: int = 0) -> bytes:
    payload = struct.pack("<BB", event, value)
    return frame_gfdi(GarminMessage.SYSTEM_EVENT, payload)


def build_supported_file_types_request() -> bytes:
    return frame_gfdi(GarminMessage.SUPPORTED_FILE_TYPES_REQUEST)


def build_set_file_flag_archive(file_index: int) -> bytes:
    payload = struct.pack("<HB", file_index, SET_FILE_FLAG_ARCHIVE)
    return frame_gfdi(GarminMessage.SET_FILE_FLAG, payload)


def build_synchronization(sync_type: int, bitmask: int = INSTALL_SYNC_BIT, *, bitmask_size: int = 4) -> bytes:
    if sync_type < 0 or sync_type > 255:
        raise ValueError("sync_type must fit in one byte")
    if bitmask_size == 4:
        payload = struct.pack("<BBI", sync_type, bitmask_size, bitmask & 0xFFFFFFFF)
    elif bitmask_size == 8:
        payload = struct.pack("<BBQ", sync_type, bitmask_size, bitmask & 0xFFFFFFFFFFFFFFFF)
    else:
        raise ValueError("bitmask_size must be 4 or 8")
    return frame_gfdi(GarminMessage.SYNCHRONIZATION, payload)


def build_generic_status(original_message_type: int, status: Status = Status.ACK) -> bytes:
    return frame_gfdi(GarminMessage.RESPONSE, struct.pack("<HB", int(original_message_type), int(status)))


def build_protobuf_status(
    original_message_type: int,
    request_id: int,
    data_offset: int,
    *,
    status: Status = Status.ACK,
    chunk_status: ProtobufChunkStatus = ProtobufChunkStatus.KEPT,
    status_code: ProtobufStatusCode = ProtobufStatusCode.NO_ERROR,
) -> bytes:
    payload = struct.pack(
        "<HBHIBB",
        int(original_message_type),
        int(status),
        request_id & 0xFFFF,
        data_offset,
        int(chunk_status),
        int(status_code),
    )
    return frame_gfdi(GarminMessage.RESPONSE, payload)


def build_protobuf_packet(
    message_type: GarminMessage,
    request_id: int,
    data: bytes,
    *,
    data_offset: int = 0,
    total_length: int | None = None,
) -> bytes:
    if total_length is None:
        total_length = len(data)
    payload = struct.pack("<HIII", request_id & 0xFFFF, data_offset, total_length, len(data)) + data
    return frame_gfdi(message_type, payload)


def build_protobuf_request(request_id: int, data: bytes) -> bytes:
    return build_protobuf_packet(GarminMessage.PROTOBUF_REQUEST, request_id, data)


def build_sync_ready() -> bytes:
    return build_system_event(SystemEvent.SYNC_READY, 0)


def build_sync_complete() -> bytes:
    return build_system_event(SystemEvent.SYNC_COMPLETE, 0)


def load_prg(path: Path) -> bytes:
    data = path.read_bytes()
    if len(data) > MAX_EXPECTED_PRG_SIZE:
        raise ProtocolError(f"PRG is larger than expected maximum ({len(data)} > {MAX_EXPECTED_PRG_SIZE})")
    if not data.startswith(PRG_MAGIC):
        got = data[:3].hex(" ").upper()
        raise ProtocolError(f"Not a Garmin PRG accepted by Gadgetbridge; expected D0 00 D0, got {got}")
    return data


def cobs_encode(data: bytes) -> bytes:
    encoded = bytearray([0])
    position = 0
    last_byte_was_zero = False

    while position < len(data):
        start = position
        while position < len(data) and data[position] != 0:
            position += 1
        zero_index = position
        if position < len(data) and data[position] == 0:
            position += 1
            last_byte_was_zero = True
        else:
            last_byte_was_zero = False

        payload_size = zero_index - start
        while payload_size >= 0xFE:
            encoded.append(0xFF)
            encoded.extend(data[start : start + 0xFE])
            start += 0xFE
            payload_size -= 0xFE

        encoded.append(payload_size + 1)
        encoded.extend(data[start : start + payload_size])

    if last_byte_was_zero:
        encoded.append(0x01)

    encoded.append(0)
    return bytes(encoded)


class CobsDecoder:
    def __init__(self) -> None:
        self._buffer = bytearray()

    def feed(self, data: bytes) -> list[bytes]:
        self._buffer.extend(data)
        messages: list[bytes] = []

        while True:
            if len(self._buffer) < 4:
                return messages
            try:
                start = self._buffer.index(0)
                end = self._buffer.index(0, start + 1)
            except ValueError:
                return messages
            if start:
                del self._buffer[:start]
                start = 0
                end = self._buffer.index(0, 1)

            frame = bytes(self._buffer[start + 1 : end])
            del self._buffer[: end + 1]
            messages.append(_cobs_decode_frame(frame))


def _cobs_decode_frame(frame: bytes) -> bytes:
    decoded = bytearray()
    index = 0
    while index < len(frame):
        code = frame[index]
        index += 1
        if code == 0:
            break
        payload_size = code - 1
        if index + payload_size > len(frame):
            raise ProtocolError("COBS payload runs past frame end")
        decoded.extend(frame[index : index + payload_size])
        index += payload_size
        if code != 0xFF and index < len(frame):
            decoded.append(0)
    return bytes(decoded)


@dataclass
class UploadChunk:
    offset: int
    data: bytes
    running_crc: int


class UploadChunker:
    def __init__(self, data: bytes, max_packet_size: int = 375, *, initial_offset: int = 0, initial_crc: Optional[int] = None) -> None:
        if max_packet_size <= 13:
            raise ValueError("max_packet_size must be greater than 13")
        if initial_offset < 0 or initial_offset > len(data):
            raise ValueError("initial_offset must be within the upload data")
        self.data = data
        self.max_payload_size = max_packet_size - 13
        self.offset = initial_offset
        self.running_crc = garmin_crc(data[:initial_offset]) if initial_crc is None else initial_crc & 0xFFFF

    def seek(self, offset: int, running_crc: Optional[int] = None) -> None:
        if offset < 0 or offset > len(self.data):
            raise ValueError("offset must be within the upload data")
        self.offset = offset
        self.running_crc = garmin_crc(self.data[:offset]) if running_crc is None else running_crc & 0xFFFF

    def next_chunk(self) -> Optional[UploadChunk]:
        if self.offset >= len(self.data):
            return None
        chunk = self.data[self.offset : self.offset + self.max_payload_size]
        current_offset = self.offset
        self.running_crc = garmin_crc(chunk, self.running_crc)
        self.offset += len(chunk)
        return UploadChunk(current_offset, chunk, self.running_crc)
