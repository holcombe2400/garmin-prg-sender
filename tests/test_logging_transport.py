from pathlib import Path
import json
import struct
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from garmin_prg_sender.logging_transport import PacketLoggingTransport  # noqa: E402
from garmin_prg_sender.protocol import GarminMessage, Status, SystemEvent, TransferStatus, frame_gfdi  # noqa: E402


class FakeTransport:
    max_write_size = 20

    def __init__(self, reply: bytes):
        self.reply = reply
        self.sent = []

    async def send_gfdi(self, packet: bytes) -> None:
        self.sent.append(packet)

    async def receive_gfdi(self, timeout: float = 20.0) -> bytes:
        return self.reply


class LoggingTransportTests(unittest.IsolatedAsyncioTestCase):
    async def test_logs_compact_tx_and_rx_rows(self):
        tx_packet = frame_gfdi(GarminMessage.SYSTEM_EVENT, b"\x00\x00")
        rx_payload = struct.pack("<HBBI", GarminMessage.FILE_TRANSFER_DATA, Status.ACK, TransferStatus.OK, 12)
        rx_packet = frame_gfdi(GarminMessage.RESPONSE, rx_payload)

        with tempfile.TemporaryDirectory() as tmp:
            log_path = Path(tmp) / "packets.jsonl"
            transport = PacketLoggingTransport(FakeTransport(rx_packet), log_path, max_payload_bytes=4)
            await transport.send_gfdi(tx_packet)
            await transport.receive_gfdi()
            transport.close()

            rows = [json.loads(line) for line in log_path.read_text(encoding="utf-8").splitlines()]

        self.assertEqual(rows[0]["direction"], "tx")
        self.assertEqual(rows[0]["message_type"], GarminMessage.SYSTEM_EVENT)
        self.assertEqual(rows[0]["system_event"], SystemEvent.SYNC_COMPLETE.name)
        self.assertTrue(rows[0]["hex_truncated"])
        self.assertEqual(rows[1]["direction"], "rx")
        self.assertEqual(rows[1]["original_message_type"], GarminMessage.FILE_TRANSFER_DATA)
        self.assertEqual(rows[1]["transfer_status"], "OK")
        self.assertEqual(rows[1]["data_offset"], 12)

    async def test_log_file_is_replaced_for_each_run(self):
        tx_packet = frame_gfdi(GarminMessage.SYSTEM_EVENT, b"\x00\x00")
        with tempfile.TemporaryDirectory() as tmp:
            log_path = Path(tmp) / "packets.jsonl"
            log_path.write_text('{"old": true}\n', encoding="utf-8")
            transport = PacketLoggingTransport(FakeTransport(tx_packet), log_path, max_payload_bytes=4)
            await transport.send_gfdi(tx_packet)
            transport.close()

            rows = [json.loads(line) for line in log_path.read_text(encoding="utf-8").splitlines()]

        self.assertEqual(len(rows), 1)
        self.assertNotIn("old", rows[0])

    async def test_logs_supported_file_types_status(self):
        name = b"PRG"
        rx_payload = struct.pack("<HB", GarminMessage.SUPPORTED_FILE_TYPES_REQUEST, Status.ACK) + bytes([1, 255, 17, len(name)]) + name
        rx_packet = frame_gfdi(GarminMessage.RESPONSE, rx_payload)

        with tempfile.TemporaryDirectory() as tmp:
            log_path = Path(tmp) / "packets.jsonl"
            transport = PacketLoggingTransport(FakeTransport(rx_packet), log_path, max_payload_bytes=64)
            await transport.receive_gfdi()
            transport.close()

            rows = [json.loads(line) for line in log_path.read_text(encoding="utf-8").splitlines()]

        self.assertEqual(rows[0]["original_message_type"], GarminMessage.SUPPORTED_FILE_TYPES_REQUEST)
        self.assertEqual(rows[0]["supported_file_type_count"], 1)
        self.assertTrue(rows[0]["prg_supported"])


if __name__ == "__main__":
    unittest.main()
