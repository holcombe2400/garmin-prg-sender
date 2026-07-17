from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from garmin_prg_sender.windows_diagnostic import address_from_device_id, format_ble_address, parse_ble_address  # noqa: E402


class WindowsDiagnosticTests(unittest.TestCase):
    def test_address_from_windows_device_id(self):
        device_id = "BluetoothLE#BluetoothLE90:de:80:08:55:aa-f0:99:19:75:41:3e"
        self.assertEqual(address_from_device_id(device_id), "F0:99:19:75:41:3E")

    def test_parse_and_format_ble_address(self):
        self.assertEqual(format_ble_address(parse_ble_address("f0-99-19-75-41-3e")), "F0:99:19:75:41:3E")

    def test_rejects_non_address_device_id(self):
        self.assertIsNone(address_from_device_id("BluetoothLE#not-an-address"))


if __name__ == "__main__":
    unittest.main()
