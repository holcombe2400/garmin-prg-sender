from __future__ import annotations

import uuid
from dataclasses import dataclass
from typing import Iterable

from .protocol import (
    GarminMessage,
    GenericStatus,
    ProtocolError,
    ProtobufPacket,
    ProtobufStatus,
    Status,
    build_generic_status,
    build_protobuf_request,
    build_protobuf_status,
    parse_gfdi,
)
from .transport import GarminTransport


GARMON_APP_ID = "d036558e-537b-4aa3-aac9-c23c7ba27344"
GARMON_APP_NAME = "Garmon"

APP_TYPE_NAMES = {
    0: "UNKNOWN_APP_TYPE",
    1: "WATCH_APP",
    2: "WIDGET",
    3: "WATCH_FACE",
    4: "DATA_FIELD",
    5: "ALL",
    6: "NONE",
    7: "AUDIO_CONTENT_PROVIDER",
    8: "ACTIVITY",
}


@dataclass(frozen=True)
class InstalledApp:
    store_app_id: bytes
    app_type: int | None
    name: str
    disabled: bool | None
    version: int | None = None
    file_name: str | None = None
    file_size: int | None = None
    native_app_id: int | None = None
    favorite: bool | None = None

    @property
    def app_type_name(self) -> str:
        if self.app_type is None:
            return "UNKNOWN"
        return APP_TYPE_NAMES.get(self.app_type, str(self.app_type))

    @property
    def uuid_candidates(self) -> tuple[str, ...]:
        if len(self.store_app_id) != 16:
            return ()
        values = {
            str(uuid.UUID(bytes=self.store_app_id)),
            str(uuid.UUID(bytes_le=self.store_app_id)),
        }
        return tuple(sorted(values))

    @property
    def display_id(self) -> str:
        candidates = self.uuid_candidates
        if candidates:
            return candidates[0]
        return self.store_app_id.hex()


@dataclass(frozen=True)
class InstalledAppsResult:
    available_space: int | None
    available_slots: int | None
    apps: tuple[InstalledApp, ...]

    def find(self, *, app_id: str | None = None, app_name: str | None = None) -> InstalledApp | None:
        target_uuid = _normalize_uuid(app_id) if app_id else None
        target_name = app_name.casefold() if app_name else None
        for app in self.apps:
            if target_uuid is not None and target_uuid in {_normalize_uuid(candidate) for candidate in app.uuid_candidates}:
                return app
            if target_name is not None and app.name.casefold() == target_name:
                return app
        return None


class GarminProtobufClient:
    def __init__(self, transport: GarminTransport, *, timeout: float = 20.0, request_id: int = 1) -> None:
        self.transport = transport
        self.timeout = timeout
        self.request_id = request_id & 0xFFFF or 1
        self._fragments: dict[int, bytearray] = {}

    async def query_installed_apps(self) -> InstalledAppsResult:
        request = build_get_installed_apps_request()
        await self.transport.send_gfdi(build_protobuf_request(self.request_id, request))

        while True:
            packet = await self.transport.receive_gfdi(timeout=self.timeout)
            message = parse_gfdi(packet)

            if isinstance(message, ProtobufStatus):
                self._check_status(message)
                continue
            if isinstance(message, GenericStatus):
                self._check_generic_status(message)
                continue
            if not isinstance(message, ProtobufPacket):
                continue
            if message.message_type != GarminMessage.PROTOBUF_RESPONSE or message.request_id != self.request_id:
                continue

            await self.transport.send_gfdi(_ack_for_protobuf_response(message))
            smart_payload = self._add_response_fragment(message)
            if smart_payload is not None:
                return parse_installed_apps_response(smart_payload)

    def _check_status(self, status: ProtobufStatus) -> None:
        if status.request_id != self.request_id:
            return
        if status.original_message_type not in (GarminMessage.PROTOBUF_REQUEST, GarminMessage.PROTOBUF_RESPONSE):
            return
        if not status.can_proceed:
            raise ProtocolError(f"Protobuf status rejected request: {status}")

    def _check_generic_status(self, status: GenericStatus) -> None:
        if status.original_message_type not in (GarminMessage.PROTOBUF_REQUEST, GarminMessage.PROTOBUF_RESPONSE):
            return
        if status.status != Status.ACK:
            raise ProtocolError(f"Protobuf request was not acknowledged: {status}")

    def _add_response_fragment(self, packet: ProtobufPacket) -> bytes | None:
        if packet.is_single_packet:
            return packet.data

        buffer = self._fragments.setdefault(packet.request_id, bytearray())
        if packet.data_offset != len(buffer):
            raise ProtocolError(f"Unexpected protobuf response offset {packet.data_offset}, expected {len(buffer)}")
        buffer.extend(packet.data)
        if len(buffer) < packet.total_length:
            return None
        payload = bytes(buffer[: packet.total_length])
        del self._fragments[packet.request_id]
        return payload


def build_get_installed_apps_request(app_type: int = 5) -> bytes:
    get_request = _field_varint(1, app_type)
    installed_apps_service = _field_message(1, get_request)
    return _field_message(3, installed_apps_service)


def parse_installed_apps_response(smart_payload: bytes) -> InstalledAppsResult:
    for field in _iter_fields(smart_payload):
        if field.number != 3 or field.wire_type != 2:
            continue
        result = _parse_installed_apps_service(field.value)
        if result is not None:
            return result
    raise ProtocolError("No installed-apps response found in protobuf payload")


def format_installed_app(app: InstalledApp) -> str:
    parts = [app.name or "(unnamed)", app.app_type_name, app.display_id]
    if app.file_name:
        parts.append(f"file={app.file_name}")
    if app.file_size is not None:
        parts.append(f"size={app.file_size}")
    if app.version is not None:
        parts.append(f"version={app.version}")
    return "  " + "  ".join(parts)


def _ack_for_protobuf_response(packet: ProtobufPacket) -> bytes:
    if packet.is_single_packet:
        return build_generic_status(GarminMessage.PROTOBUF_RESPONSE)
    return build_protobuf_status(GarminMessage.PROTOBUF_RESPONSE, packet.request_id, packet.data_offset)


def _parse_installed_apps_service(data: bytes) -> InstalledAppsResult | None:
    for field in _iter_fields(data):
        if field.number == 2 and field.wire_type == 2:
            return _parse_get_installed_apps_response(field.value)
    return None


def _parse_get_installed_apps_response(data: bytes) -> InstalledAppsResult:
    available_space = None
    available_slots = None
    apps: list[InstalledApp] = []

    for field in _iter_fields(data):
        if field.number == 1 and field.wire_type == 0:
            available_space = int(field.value)
        elif field.number == 2 and field.wire_type == 0:
            available_slots = int(field.value)
        elif field.number == 3 and field.wire_type == 2:
            apps.append(_parse_installed_app(field.value))

    return InstalledAppsResult(available_space, available_slots, tuple(apps))


def _parse_installed_app(data: bytes) -> InstalledApp:
    store_app_id = b""
    app_type = None
    name = ""
    disabled = None
    version = None
    file_name = None
    file_size = None
    native_app_id = None
    favorite = None

    for field in _iter_fields(data):
        if field.number == 1 and field.wire_type == 2:
            store_app_id = field.value
        elif field.number == 2 and field.wire_type == 0:
            app_type = int(field.value)
        elif field.number == 3 and field.wire_type == 2:
            name = _decode_utf8(field.value)
        elif field.number == 4 and field.wire_type == 0:
            disabled = bool(field.value)
        elif field.number == 5 and field.wire_type == 0:
            version = int(field.value)
        elif field.number == 6 and field.wire_type == 2:
            file_name = _decode_utf8(field.value)
        elif field.number == 7 and field.wire_type == 0:
            file_size = int(field.value)
        elif field.number == 8 and field.wire_type == 0:
            native_app_id = int(field.value)
        elif field.number == 9 and field.wire_type == 0:
            favorite = bool(field.value)

    return InstalledApp(store_app_id, app_type, name, disabled, version, file_name, file_size, native_app_id, favorite)


def _decode_utf8(data: bytes) -> str:
    return data.decode("utf-8", errors="replace")


def _normalize_uuid(value: str) -> str:
    return str(uuid.UUID(value))


@dataclass(frozen=True)
class _ProtoField:
    number: int
    wire_type: int
    value: int | bytes


def _iter_fields(data: bytes) -> Iterable[_ProtoField]:
    offset = 0
    while offset < len(data):
        key, offset = _read_varint(data, offset)
        number = key >> 3
        wire_type = key & 0x07
        if number <= 0:
            raise ProtocolError(f"Invalid protobuf field number {number}")
        if wire_type == 0:
            value, offset = _read_varint(data, offset)
            yield _ProtoField(number, wire_type, value)
        elif wire_type == 1:
            end = offset + 8
            if end > len(data):
                raise ProtocolError("Truncated protobuf fixed64 field")
            yield _ProtoField(number, wire_type, data[offset:end])
            offset = end
        elif wire_type == 2:
            length, offset = _read_varint(data, offset)
            end = offset + length
            if end > len(data):
                raise ProtocolError("Truncated protobuf length-delimited field")
            yield _ProtoField(number, wire_type, data[offset:end])
            offset = end
        elif wire_type == 5:
            end = offset + 4
            if end > len(data):
                raise ProtocolError("Truncated protobuf fixed32 field")
            yield _ProtoField(number, wire_type, data[offset:end])
            offset = end
        else:
            raise ProtocolError(f"Unsupported protobuf wire type {wire_type}")


def _field_varint(number: int, value: int) -> bytes:
    return _encode_varint((number << 3) | 0) + _encode_varint(value)


def _field_message(number: int, value: bytes) -> bytes:
    return _encode_varint((number << 3) | 2) + _encode_varint(len(value)) + value


def _read_varint(data: bytes, offset: int) -> tuple[int, int]:
    value = 0
    shift = 0
    while True:
        if offset >= len(data):
            raise ProtocolError("Truncated protobuf varint")
        byte = data[offset]
        offset += 1
        value |= (byte & 0x7F) << shift
        if byte < 0x80:
            return value, offset
        shift += 7
        if shift >= 64:
            raise ProtocolError("Protobuf varint is too long")


def _encode_varint(value: int) -> bytes:
    if value < 0:
        raise ValueError("protobuf varint cannot be negative")
    out = bytearray()
    while value >= 0x80:
        out.append((value & 0x7F) | 0x80)
        value >>= 7
    out.append(value)
    return bytes(out)
