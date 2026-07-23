from __future__ import annotations

import asyncio
from dataclasses import dataclass
from typing import Callable

from .protocol import (
    CreateStatus,
    CreateFileStatus,
    FileTransferDataStatus,
    GarminMessage,
    GenericStatus,
    PRG_SUBTYPE,
    PRG_TYPE,
    ProtocolError,
    TransferStatus,
    UploadChunker,
    UploadRequestStatus,
    build_create_file,
    build_file_transfer_data,
    build_sync_ready,
    build_sync_complete,
    build_upload_request,
    build_system_event,
    parse_gfdi,
    SystemEvent,
)
from .transport import GarminTransport


@dataclass(frozen=True)
class UploadProgress:
    offset: int
    total: int

    @property
    def percent(self) -> int:
        if self.total == 0:
            return 100
        return int((100 * self.offset) / self.total)


@dataclass(frozen=True)
class UploadResult:
    file_index: int
    file_number: int
    total: int


class GarminPrgUploader:
    def __init__(
        self,
        transport: GarminTransport,
        *,
        max_packet_size: int = 375,
        timeout: float = 20.0,
        max_retries: int = 3,
        sync_timeout: float | None = None,
        post_sync_delay: float = 2.0,
        wait_for_sync_ack: bool = True,
        send_sync_ready: bool = True,
        send_first_connect_events: bool = False,
        send_final_sync_complete: bool = True,
        progress_callback: Callable[[UploadProgress], None] | None = None,
    ) -> None:
        self.transport = transport
        self.max_packet_size = max_packet_size
        self.timeout = timeout
        self.max_retries = max_retries
        self.sync_timeout = timeout if sync_timeout is None else sync_timeout
        self.post_sync_delay = post_sync_delay
        self.wait_for_sync_ack = wait_for_sync_ack
        self.send_sync_ready = send_sync_ready
        self.send_first_connect_events = send_first_connect_events
        self.send_final_sync_complete = send_final_sync_complete
        self.progress_callback = progress_callback

    async def upload(self, data: bytes) -> UploadResult:
        if self.send_sync_ready:
            await self._send_system_event(build_sync_ready(), SystemEvent.SYNC_READY)
        if self.send_first_connect_events:
            await self._send_system_event(build_system_event(SystemEvent.PAIR_COMPLETE), SystemEvent.PAIR_COMPLETE)
            await self._send_system_event(build_sync_complete(), SystemEvent.SYNC_COMPLETE)
            await self._send_system_event(build_system_event(SystemEvent.SETUP_WIZARD_COMPLETE), SystemEvent.SETUP_WIZARD_COMPLETE)

        await self.transport.send_gfdi(build_create_file(len(data)))
        create_status = await self._receive_status(CreateFileStatus)
        if not create_status.can_proceed:
            raise ProtocolError(_describe_create_file_failure(create_status, len(data)))
        if create_status.data_type != PRG_TYPE or create_status.subtype != PRG_SUBTYPE:
            raise ProtocolError(f"Watch created unexpected file type {create_status.data_type}/{create_status.subtype}")
        self._report_progress(0, len(data))

        await self.transport.send_gfdi(build_upload_request(create_status.file_index, len(data)))
        upload_status = await self._receive_status(UploadRequestStatus)
        if not upload_status.can_proceed:
            raise ProtocolError(f"Upload request failed: {upload_status}")
        if upload_status.max_file_size and len(data) > upload_status.max_file_size:
            raise ProtocolError(f"Watch reported max file size {upload_status.max_file_size}, PRG is {len(data)} bytes")
        if upload_status.data_offset > len(data):
            raise ProtocolError(f"Watch requested offset beyond PRG size: {upload_status.data_offset} > {len(data)}")

        initial_crc = upload_status.crc_seed
        if upload_status.data_offset > 0 and upload_status.crc_seed == 0:
            initial_crc = None
        chunker = UploadChunker(data, self.max_packet_size, initial_offset=upload_status.data_offset, initial_crc=initial_crc)
        self._report_progress(upload_status.data_offset, len(data))
        retries = 0
        while True:
            chunk = chunker.next_chunk()
            if chunk is None:
                break
            await self.transport.send_gfdi(build_file_transfer_data(chunk.data, chunk.offset, chunk.running_crc))
            transfer_status = await self._receive_status(FileTransferDataStatus)
            if not transfer_status.can_proceed:
                if self._can_retry_transfer(transfer_status, len(data), retries):
                    retries += 1
                    chunker.seek(transfer_status.data_offset)
                    self._report_progress(transfer_status.data_offset, len(data))
                    continue
                raise ProtocolError(f"File chunk failed: {transfer_status}")
            expected_offset = chunk.offset + len(chunk.data)
            if transfer_status.data_offset != expected_offset:
                if transfer_status.data_offset < expected_offset and self._can_retry_offset(transfer_status.data_offset, len(data), retries):
                    retries += 1
                    chunker.seek(transfer_status.data_offset)
                    self._report_progress(transfer_status.data_offset, len(data))
                    continue
                raise ProtocolError(f"Watch acknowledged offset {transfer_status.data_offset}, expected {expected_offset}")
            retries = 0
            self._report_progress(transfer_status.data_offset, len(data))

        result = UploadResult(create_status.file_index, create_status.file_number, len(data))
        if self.send_final_sync_complete:
            await self.send_system_event(SystemEvent.SYNC_COMPLETE)
        if self.send_final_sync_complete and self.post_sync_delay > 0:
            await asyncio.sleep(self.post_sync_delay)
        return result

    async def send_system_event(self, event: SystemEvent, value: int = 0) -> None:
        await self._send_system_event(build_system_event(event, value), event)

    async def _send_system_event(self, packet: bytes, event: SystemEvent) -> None:
        await self.transport.send_gfdi(packet)
        if self.wait_for_sync_ack:
            sync_status = await self._receive_status(
                GenericStatus,
                original_message_type=GarminMessage.SYSTEM_EVENT,
                timeout=self.sync_timeout,
            )
            if not sync_status.can_proceed:
                raise ProtocolError(f"System event {event.name} failed: {sync_status}")

    def _report_progress(self, offset: int, total: int) -> None:
        if self.progress_callback is not None:
            self.progress_callback(UploadProgress(offset, total))

    def _can_retry_transfer(self, status: FileTransferDataStatus, total: int, retries: int) -> bool:
        return (
            status.transfer_status
            in {
                TransferStatus.RESEND,
                TransferStatus.CRC_MISMATCH,
                TransferStatus.OFFSET_MISMATCH,
                TransferStatus.SYNC_PAUSED,
            }
            and retries < self.max_retries
            and 0 <= status.data_offset <= total
        )

    def _can_retry_offset(self, offset: int, total: int, retries: int) -> bool:
        return retries < self.max_retries and 0 <= offset <= total

    async def _receive_status(self, expected_type, *, original_message_type: int | None = None, timeout: float | None = None):
        while True:
            packet = await self.transport.receive_gfdi(timeout=self.timeout if timeout is None else timeout)
            message = parse_gfdi(packet)
            if isinstance(message, expected_type):
                if original_message_type is not None and getattr(message, "original_message_type", None) != original_message_type:
                    continue
                return message


def _format_bytes(size: int) -> str:
    if size < 1024:
        return f"{size} bytes"
    if size < 1024 * 1024:
        return f"{size / 1024:.1f} KB"
    return f"{size / 1024 / 1024:.2f} MB"


def _describe_create_file_failure(status: CreateFileStatus, file_size: int) -> str:
    if status.status.name != "ACK":
        return f"Watch did not ACK PRG file creation: {status}"
    if status.create_status == CreateStatus.NO_SLOTS:
        return (
            "Watch rejected PRG file creation: NO_SLOTS. "
            "Remove an unused Connect IQ app slot, then try again. "
            f"Raw status: {status}"
        )
    if status.create_status in {CreateStatus.NO_SPACE, CreateStatus.NO_SPACE_FOR_TYPE}:
        return (
            f"Watch rejected PRG file creation: {status.create_status.name} for {_format_bytes(file_size)}. "
            "The PRG is probably too large for the fenix 6 PRG staging/app area, "
            "or storage for this file type is full. Try a smaller PRG or free watch storage. "
            f"Raw status: {status}"
        )
    if status.create_status == CreateStatus.UNSUPPORTED:
        return (
            "Watch rejected PRG file creation: UNSUPPORTED. "
            "This firmware did not accept PRG 255/17 over this path. "
            f"Raw status: {status}"
        )
    if status.create_status == CreateStatus.DUPLICATE:
        return (
            "Watch rejected PRG file creation: DUPLICATE. "
            "The same PRG may already be staged. Let Garmin Connect sync, then retry if needed. "
            f"Raw status: {status}"
        )
    return f"Watch rejected PRG file creation: {status.create_status.name}. Raw status: {status}"
