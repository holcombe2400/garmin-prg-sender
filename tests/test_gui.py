from pathlib import Path
import sys
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from garmin_prg_sender.gui import (  # noqa: E402
    GuiPaths,
    command_base,
    latest_log_path,
    progress_percent_from_output,
    verification_status_from_output,
)


class GuiHelperTests(unittest.TestCase):
    def test_command_base_uses_project_python_and_sender(self):
        paths = GuiPaths(
            root=Path("C:/sender"),
            python=Path("C:/sender/.venv/Scripts/python.exe"),
            sender=Path("C:/sender/send_prg.py"),
            logs=Path("C:/sender/logs"),
        )

        self.assertEqual(command_base(paths), [str(paths.python), "-u", "-B", str(paths.sender)])

    def test_latest_log_path_returns_newest_upload_log(self):
        with tempfile.TemporaryDirectory() as tmp:
            logs = Path(tmp)
            older = logs / "upload-old.jsonl"
            newer = logs / "upload-new.jsonl"
            older.write_text("{}", encoding="utf-8")
            time.sleep(0.01)
            newer.write_text("{}", encoding="utf-8")

            self.assertEqual(latest_log_path(logs), newer)

    def test_latest_log_path_includes_phone_sync_stage_logs(self):
        with tempfile.TemporaryDirectory() as tmp:
            logs = Path(tmp)
            older = logs / "upload-old.jsonl"
            newer = logs / "stage-for-phone-sync-latest.jsonl"
            older.write_text("{}", encoding="utf-8")
            time.sleep(0.01)
            newer.write_text("{}", encoding="utf-8")

            self.assertEqual(latest_log_path(logs), newer)

    def test_verification_status_from_output(self):
        self.assertEqual(
            verification_status_from_output("Transfer succeeded but app is not registered\n"),
            "Transfer succeeded but app is not registered",
        )
        self.assertEqual(
            verification_status_from_output("Unable to query installed apps: timeout\n"),
            "Unable to query installed apps",
        )
        self.assertEqual(
            verification_status_from_output("PRG staged for Garmin Connect phone sync\n"),
            "Upload complete. Turn phone Bluetooth back on.",
        )
        self.assertEqual(
            verification_status_from_output("GFDI registration succeeded; handle=42.\n"),
            "Connected to watch. Ready to send.",
        )
        self.assertEqual(
            verification_status_from_output("Garmon is not registered\n"),
            "Garmon is not registered",
        )
        self.assertEqual(
            verification_status_from_output("BLE verification result: target is registered.\n"),
            "BLE verification result: target is registered",
        )
        self.assertEqual(
            verification_status_from_output("SoftDisc Probe 011629 is registered\n"),
            "SoftDisc Probe 011629 is registered",
        )
        self.assertEqual(
            verification_status_from_output("MTP did not return within 45 seconds; skipping final MTP snapshot.\n"),
            "MTP did not return",
        )
        self.assertIsNone(verification_status_from_output("Uploaded 1/2 bytes (50%)"))

    def test_progress_percent_from_output(self):
        self.assertEqual(progress_percent_from_output("Uploaded 4706/90140 bytes (5%)\n"), 5)
        self.assertEqual(progress_percent_from_output("Uploaded 90140/90140 bytes (100%)\n"), 100)
        self.assertIsNone(progress_percent_from_output("PRG staged for Garmin Connect phone sync\n"))


if __name__ == "__main__":
    unittest.main()
