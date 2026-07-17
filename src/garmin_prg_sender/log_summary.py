from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .protocol import GarminMessage


@dataclass(frozen=True)
class PacketLogSummary:
    path: Path
    rows: int
    tx_rows: int
    rx_rows: int
    parse_errors: int
    tx_data_packets: int
    rx_data_statuses: int
    last_data_offset: int | None
    last_status: str | None
    last_error: str | None
    sync_complete_sent: bool


def summarize_packet_log(path: Path) -> PacketLogSummary:
    rows = 0
    tx_rows = 0
    rx_rows = 0
    parse_errors = 0
    tx_data_packets = 0
    rx_data_statuses = 0
    last_data_offset = None
    last_status = None
    last_error = None
    sync_complete_sent = False

    for row in _read_rows(path):
        rows += 1
        direction = row.get("direction")
        if direction == "tx":
            tx_rows += 1
            if row.get("message_type") == GarminMessage.FILE_TRANSFER_DATA:
                tx_data_packets += 1
            if row.get("message_type") == GarminMessage.SYSTEM_EVENT and row.get("system_event") == "SYNC_COMPLETE":
                sync_complete_sent = True
        elif direction == "rx":
            rx_rows += 1
            original = row.get("original_message_type")
            if original == GarminMessage.FILE_TRANSFER_DATA:
                rx_data_statuses += 1
                if isinstance(row.get("data_offset"), int):
                    last_data_offset = row["data_offset"]

        if "parse_error" in row:
            parse_errors += 1
            last_error = str(row["parse_error"])

        status = _status_text(row)
        if status:
            last_status = status
        error = _row_error_text(row)
        if error:
            last_error = error

    return PacketLogSummary(
        path=path,
        rows=rows,
        tx_rows=tx_rows,
        rx_rows=rx_rows,
        parse_errors=parse_errors,
        tx_data_packets=tx_data_packets,
        rx_data_statuses=rx_data_statuses,
        last_data_offset=last_data_offset,
        last_status=last_status,
        last_error=last_error,
        sync_complete_sent=sync_complete_sent,
    )


def print_packet_log_summary(path: Path) -> None:
    summary = summarize_packet_log(path)
    print(f"Packet log: {summary.path}")
    print(f"Rows: {summary.rows} ({summary.tx_rows} tx, {summary.rx_rows} rx)")
    print(f"Parse errors: {summary.parse_errors}")
    print(f"Data packets sent: {summary.tx_data_packets}")
    print(f"Data statuses received: {summary.rx_data_statuses}")
    if summary.last_data_offset is not None:
        print(f"Last acknowledged offset: {summary.last_data_offset}")
    else:
        print("Last acknowledged offset: none")
    print(f"Last status: {summary.last_status or 'none'}")
    print(f"Last error: {summary.last_error or 'none'}")
    print(f"Sync-complete sent: {'yes' if summary.sync_complete_sent else 'no'}")


def _read_rows(path: Path):
    with path.open("r", encoding="utf-8") as handle:
        for line_number, line in enumerate(handle, start=1):
            stripped = line.strip().lstrip("\ufeff")
            if not stripped:
                continue
            try:
                row = json.loads(stripped)
            except json.JSONDecodeError as exc:
                yield {"parse_error": f"line {line_number}: {exc}"}
                continue
            if isinstance(row, dict):
                yield row
            else:
                yield {"parse_error": f"line {line_number}: row is not an object"}


def _status_text(row: dict[str, Any]) -> str | None:
    parts = []
    if row.get("status"):
        parts.append(str(row["status"]))
    for key in ("create_status", "upload_status", "transfer_status"):
        if row.get(key):
            parts.append(f"{key}={row[key]}")
    if not parts:
        return None
    return " ".join(parts)


def _row_error_text(row: dict[str, Any]) -> str | None:
    status = row.get("status")
    if status and status != "ACK":
        return _status_text(row)
    for key in ("create_status", "upload_status", "transfer_status"):
        value = row.get(key)
        if value and value != "OK":
            return _status_text(row)
    return None
