from pathlib import Path
import json
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from garmin_prg_sender.log_summary import summarize_packet_log  # noqa: E402
from garmin_prg_sender.protocol import GarminMessage, SystemEvent  # noqa: E402


class LogSummaryTests(unittest.TestCase):
    def test_summary_tracks_offsets_and_sync_complete(self):
        rows = [
            {"direction": "tx", "message_type": int(GarminMessage.FILE_TRANSFER_DATA), "length": 20},
            {
                "direction": "rx",
                "message_type": int(GarminMessage.RESPONSE),
                "original_message_type": int(GarminMessage.FILE_TRANSFER_DATA),
                "status": "ACK",
                "transfer_status": "OK",
                "data_offset": 12,
            },
            {
                "direction": "tx",
                "message_type": int(GarminMessage.SYSTEM_EVENT),
                "system_event": SystemEvent.SYNC_COMPLETE.name,
                "length": 8,
            },
        ]

        path = _write_rows(rows)
        self.addCleanup(lambda: path.unlink(missing_ok=True))
        summary = summarize_packet_log(path)

        self.assertEqual(summary.rows, 3)
        self.assertEqual(summary.tx_data_packets, 1)
        self.assertEqual(summary.rx_data_statuses, 1)
        self.assertEqual(summary.last_data_offset, 12)
        self.assertEqual(summary.last_error, None)
        self.assertTrue(summary.sync_complete_sent)

    def test_summary_does_not_treat_sync_ready_as_sync_complete(self):
        rows = [
            {
                "direction": "tx",
                "message_type": int(GarminMessage.SYSTEM_EVENT),
                "system_event": SystemEvent.SYNC_READY.name,
                "length": 8,
            },
        ]

        path = _write_rows(rows)
        self.addCleanup(lambda: path.unlink(missing_ok=True))
        summary = summarize_packet_log(path)

        self.assertFalse(summary.sync_complete_sent)

    def test_ack_with_non_ok_transfer_status_is_error(self):
        rows = [
            {
                "direction": "rx",
                "message_type": int(GarminMessage.RESPONSE),
                "original_message_type": int(GarminMessage.FILE_TRANSFER_DATA),
                "status": "ACK",
                "transfer_status": "CRC_MISMATCH",
                "data_offset": 0,
            }
        ]

        path = _write_rows(rows)
        self.addCleanup(lambda: path.unlink(missing_ok=True))
        summary = summarize_packet_log(path)

        self.assertEqual(summary.last_status, "ACK transfer_status=CRC_MISMATCH")
        self.assertEqual(summary.last_error, "ACK transfer_status=CRC_MISMATCH")

    def test_summary_accepts_utf8_bom_on_first_line(self):
        path = _write_rows([{"direction": "tx", "message_type": int(GarminMessage.SYSTEM_EVENT)}], bom=True)
        self.addCleanup(lambda: path.unlink(missing_ok=True))

        summary = summarize_packet_log(path)

        self.assertEqual(summary.parse_errors, 0)
        self.assertEqual(summary.tx_rows, 1)


def _write_rows(rows, bom=False):
    handle = tempfile.NamedTemporaryFile("w", delete=False, encoding="utf-8", suffix=".jsonl")
    with handle:
        if bom:
            handle.write("\ufeff")
        for row in rows:
            handle.write(json.dumps(row) + "\n")
    return Path(handle.name)


if __name__ == "__main__":
    unittest.main()
