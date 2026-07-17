from __future__ import annotations

import asyncio
import struct
import uuid
from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Optional

from .protocol import CobsDecoder, cobs_encode


BASE_UUID = "6A4E%04X-667B-11E3-949A-0800200C9A66"
V2_SERVICE_UUID = uuid.UUID(BASE_UUID % 0x2800)
V1_SERVICE_UUID = uuid.UUID("6A4E2401-667B-11E3-949A-0800200C9A66")
V1_SEND_UUID = uuid.UUID("6A4E4C80-667B-11E3-949A-0800200C9A66")
V1_RECEIVE_UUID = uuid.UUID("6A4ECD28-667B-11E3-949A-0800200C9A66")
V0_SERVICE_UUID = uuid.UUID("9B012401-BC30-CE9A-E111-0F67E491ABDE")
V0_SEND_UUID = uuid.UUID("DF334C80-E6A7-D082-274D-78FC66F85E16")
V0_RECEIVE_UUID = uuid.UUID("4ACBCD28-7425-868E-F447-915C8F00D0CB")

GADGETBRIDGE_CLIENT_ID = 2
REQUEST_REGISTER_ML = 0
REQUEST_REGISTER_ML_RESP = 1
REQUEST_CLOSE_ALL = 5
REQUEST_CLOSE_ALL_RESP = 6
SERVICE_GFDI = 1


class TransportError(RuntimeError):
    pass


class GarminTransport(ABC):
    max_write_size: int

    def __init__(self) -> None:
        self.messages: asyncio.Queue[bytes] = asyncio.Queue()

    @abstractmethod
    async def initialize(self) -> None:
        pass

    @abstractmethod
    async def send_gfdi(self, packet: bytes) -> None:
        pass

    async def receive_gfdi(self, timeout: float = 20.0) -> bytes:
        return await asyncio.wait_for(self.messages.get(), timeout=timeout)


@dataclass(frozen=True)
class CharacteristicPair:
    receive_uuid: uuid.UUID
    send_uuid: uuid.UUID


@dataclass(frozen=True)
class GarminSupportInfo:
    v2_pair: Optional[CharacteristicPair]
    v1_pair: Optional[CharacteristicPair]
    characteristic_uuids: tuple[uuid.UUID, ...]

    @property
    def has_gfdi(self) -> bool:
        return self.v2_pair is not None or self.v1_pair is not None


class BleakV1Transport(GarminTransport):
    def __init__(self, client, pair: CharacteristicPair, max_write_size: int) -> None:
        super().__init__()
        self.client = client
        self.pair = pair
        self.max_write_size = max_write_size
        self.decoder = CobsDecoder()

    async def initialize(self) -> None:
        await self.client.start_notify(str(self.pair.receive_uuid), self._on_notify)

    async def send_gfdi(self, packet: bytes) -> None:
        payload = cobs_encode(packet)
        max_fragment = max(1, self.max_write_size - 1)
        for i in range(0, len(payload), max_fragment):
            await self.client.write_gatt_char(str(self.pair.send_uuid), payload[i : i + max_fragment], response=False)

    def _on_notify(self, _sender, data: bytearray) -> None:
        for message in self.decoder.feed(bytes(data)):
            self.messages.put_nowait(message)


class BleakV2Transport(GarminTransport):
    def __init__(self, client, pair: CharacteristicPair, max_write_size: int) -> None:
        super().__init__()
        self.client = client
        self.pair = pair
        self.max_write_size = max_write_size
        self.decoder = CobsDecoder()
        self.gfdi_handle: Optional[int] = None
        self.registration_error: Optional[TransportError] = None

    async def initialize(self) -> None:
        await self.client.start_notify(str(self.pair.receive_uuid), self._on_notify)
        await self._write_raw(_close_all_services())
        try:
            await asyncio.wait_for(self._wait_for_gfdi_handle(), timeout=15.0)
        except asyncio.TimeoutError as exc:
            raise TransportError("Timed out registering v2 GFDI service") from exc

    async def send_gfdi(self, packet: bytes) -> None:
        if self.gfdi_handle is None:
            raise TransportError("v2 GFDI handle is not registered")
        payload = cobs_encode(packet)
        max_fragment = max(1, self.max_write_size - 1)
        for i in range(0, len(payload), max_fragment):
            fragment = bytes([self.gfdi_handle]) + payload[i : i + max_fragment]
            await self._write_raw(fragment)

    async def _write_raw(self, payload: bytes) -> None:
        await self.client.write_gatt_char(str(self.pair.send_uuid), payload, response=False)

    async def _wait_for_gfdi_handle(self) -> None:
        while self.gfdi_handle is None:
            if self.registration_error is not None:
                raise self.registration_error
            await asyncio.sleep(0.05)

    def _on_notify(self, _sender, data: bytearray) -> None:
        value = bytes(data)
        if not value:
            return
        handle = value[0]
        if handle == 0:
            self._handle_management(value[1:])
            return
        if self.gfdi_handle is not None and handle == self.gfdi_handle:
            for message in self.decoder.feed(value[1:]):
                self.messages.put_nowait(message)

    def _handle_management(self, data: bytes) -> None:
        if len(data) < 9:
            return
        request_type = data[0]
        client_id = struct.unpack_from("<Q", data, 1)[0]
        if client_id != GADGETBRIDGE_CLIENT_ID:
            return

        if request_type == REQUEST_CLOSE_ALL_RESP:
            asyncio.create_task(self._write_raw(_register_service(SERVICE_GFDI, reliable=False)))
            return

        if request_type == REQUEST_REGISTER_ML_RESP:
            if len(data) < 14:
                return
            service_code, status, handle, reliable = struct.unpack_from("<HBBB", data, 9)
            if service_code != SERVICE_GFDI:
                return
            if status != 0:
                self.registration_error = TransportError(f"Watch rejected v2 GFDI registration with status {status}")
                return
            if reliable:
                self.registration_error = TransportError("Watch registered GFDI as reliable MLR; this sender does not implement MLR yet")
                return
            self.gfdi_handle = handle


def _close_all_services() -> bytes:
    return struct.pack("<BBQH", 0, REQUEST_CLOSE_ALL, GADGETBRIDGE_CLIENT_ID, 0)


def _register_service(service: int, reliable: bool = False) -> bytes:
    reliable_value = 2 if reliable else 0
    return struct.pack("<BBQHB", 0, REQUEST_REGISTER_ML, GADGETBRIDGE_CLIENT_ID, service, reliable_value)


async def create_ble_transport(client, force: str = "auto", max_write_size: Optional[int] = None) -> GarminTransport:
    services = client.services
    if max_write_size is None:
        max_write_size = _guess_max_write_size(client)

    if force in ("auto", "v2"):
        pair = _find_v2_pair(services)
        if pair is not None:
            transport = BleakV2Transport(client, pair, max_write_size)
            await transport.initialize()
            return transport
        if force == "v2":
            raise TransportError("No Garmin v2 ML GFDI characteristic pair found")

    if force in ("auto", "v1"):
        pair = _find_v1_pair(services)
        if pair is not None:
            transport = BleakV1Transport(client, pair, max_write_size)
            await transport.initialize()
            return transport
        if force == "v1":
            raise TransportError("No Garmin v1/v0 GFDI characteristic pair found")

    raise TransportError("No supported Garmin GFDI transport found")


def inspect_garmin_support(services) -> GarminSupportInfo:
    chars = _all_characteristic_uuids(services)
    return GarminSupportInfo(
        v2_pair=_find_v2_pair(services),
        v1_pair=_find_v1_pair(services),
        characteristic_uuids=tuple(sorted(chars, key=str)),
    )


def _guess_max_write_size(client) -> int:
    for service in client.services:
        for char in service.characteristics:
            size = getattr(char, "max_write_without_response_size", None)
            if isinstance(size, int) and size > 20:
                return size
    return 20


def _find_v2_pair(services) -> Optional[CharacteristicPair]:
    chars = _all_characteristic_uuids(services)
    for i in range(0x2810, 0x2815):
        receive = uuid.UUID(BASE_UUID % i)
        send = uuid.UUID(BASE_UUID % (i + 0x10))
        if receive in chars and send in chars:
            return CharacteristicPair(receive, send)
    return None


def _find_v1_pair(services) -> Optional[CharacteristicPair]:
    chars = _all_characteristic_uuids(services)
    if V1_RECEIVE_UUID in chars and V1_SEND_UUID in chars:
        return CharacteristicPair(V1_RECEIVE_UUID, V1_SEND_UUID)
    if V0_RECEIVE_UUID in chars and V0_SEND_UUID in chars:
        return CharacteristicPair(V0_RECEIVE_UUID, V0_SEND_UUID)
    return None


def _all_characteristic_uuids(services) -> set[uuid.UUID]:
    return {uuid.UUID(str(char.uuid).upper()) for service in services for char in service.characteristics}
