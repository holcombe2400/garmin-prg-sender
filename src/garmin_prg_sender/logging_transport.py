from __future__ import annotations

import json
import time
from pathlib import Path
from typing import Any

from .protocol import (
    CreateFileStatus,
    FileTransferDataStatus,
    GarminMessage,
    ParsedMessage,
    ProtocolError,
    ProtobufPacket,
    ProtobufStatus,
    SetFileFlagsStatus,
    SystemEvent,
    SupportedFileTypesStatus,
    UploadRequestStatus,
    parse_gfdi,
)
from .smart_dump import describe_smart_payload


class PacketLoggingTransport:
    def __init__(self, inner: Any, path: Path, *, max_payload_bytes: int = 64, append: bool = False) -> None:
        self.inner = inner
        self.max_payload_bytes = max(0, max_payload_bytes)
        self.max_write_size = getattr(inner, "max_write_size", 20)
        path.parent.mkdir(parents=True, exist_ok=True)
        self._file = path.open("a" if append else "w", encoding="utf-8")

    async def initialize(self) -> None:
        initialize = getattr(self.inner, "initialize", None)
        if initialize is not None:
            await initialize()

    async def send_gfdi(self, packet: bytes) -> None:
        self._log("tx", packet)
        await self.inner.send_gfdi(packet)

    async def receive_gfdi(self, timeout: float = 20.0) -> bytes:
        packet = await self.inner.receive_gfdi(timeout=timeout)
        self._log("rx", packet)
        return packet

    def close(self) -> None:
        self._file.close()

    def _log(self, direction: str, packet: bytes) -> None:
        row: dict[str, Any] = {
            "time": time.time(),
            "direction": direction,
            "length": len(packet),
            "hex_prefix": packet[: self.max_payload_bytes].hex(" "),
            "hex_truncated": len(packet) > self.max_payload_bytes,
        }
        try:
            parsed = parse_gfdi(packet)
            row["message_type"] = int(getattr(parsed, "message_type", 5000))
            if hasattr(parsed, "original_message_type"):
                row["original_message_type"] = int(parsed.original_message_type)
            elif isinstance(parsed, CreateFileStatus):
                row["original_message_type"] = int(GarminMessage.CREATE_FILE)
            elif isinstance(parsed, UploadRequestStatus):
                row["original_message_type"] = int(GarminMessage.UPLOAD_REQUEST)
            elif isinstance(parsed, FileTransferDataStatus):
                row["original_message_type"] = int(GarminMessage.FILE_TRANSFER_DATA)
            elif isinstance(parsed, SetFileFlagsStatus):
                row["original_message_type"] = int(GarminMessage.SET_FILE_FLAG)
            elif isinstance(parsed, SupportedFileTypesStatus):
                row["original_message_type"] = int(GarminMessage.SUPPORTED_FILE_TYPES_REQUEST)
            elif isinstance(parsed, ProtobufStatus):
                row["original_message_type"] = int(parsed.original_message_type)
            if hasattr(parsed, "status"):
                row["status"] = getattr(parsed.status, "name", str(parsed.status))
            for attr in ("create_status", "upload_status", "transfer_status", "flags_status"):
                value = getattr(parsed, attr, None)
                if value is not None:
                    row[attr] = getattr(value, "name", str(value))
            if isinstance(parsed, SupportedFileTypesStatus):
                row["supported_file_type_count"] = len(parsed.file_types)
                row["prg_supported"] = any(item.is_prg for item in parsed.file_types)
            if isinstance(parsed, ProtobufStatus):
                row["protobuf_chunk_status"] = getattr(parsed.chunk_status, "name", str(parsed.chunk_status))
                row["protobuf_status_code"] = getattr(parsed.status_code, "name", str(parsed.status_code))
            if isinstance(parsed, ProtobufPacket):
                row["request_id"] = int(parsed.request_id)
                row["data_offset"] = int(parsed.data_offset)
                row["total_length"] = int(parsed.total_length)
                row["data_length"] = int(parsed.data_length)
                if parsed.is_single_packet:
                    row["smart_summary"] = describe_smart_payload(parsed.data)[:20]
            if isinstance(parsed, ParsedMessage) and parsed.message_type == GarminMessage.SYSTEM_EVENT and parsed.raw:
                event = _system_event_name(parsed.raw[0])
                row["system_event"] = event
                if len(parsed.raw) > 1:
                    row["system_event_value"] = int(parsed.raw[1])
            for attr in ("file_index", "file_identifier", "flags", "data_offset", "max_file_size", "crc_seed", "request_id"):
                value = getattr(parsed, attr, None)
                if value is not None:
                    row[attr] = int(value)
        except ProtocolError as exc:
            row["parse_error"] = str(exc)

        self._file.write(json.dumps(row, sort_keys=True) + "\n")
        self._file.flush()


def _system_event_name(value: int) -> str:
    try:
        return SystemEvent(value).name
    except ValueError:
        return str(value)
