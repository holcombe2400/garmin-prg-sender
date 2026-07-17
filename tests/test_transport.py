from pathlib import Path
import struct
import sys
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from garmin_prg_sender.protocol import GarminMessage, frame_gfdi  # noqa: E402
from garmin_prg_sender.transport import (  # noqa: E402
    GADGETBRIDGE_CLIENT_ID,
    REQUEST_REGISTER_ML_RESP,
    SERVICE_GFDI,
    BleakV1Transport,
    BleakV2Transport,
    CharacteristicPair,
    TransportError,
)


class FakeClient:
    def __init__(self):
        self.writes = []

    async def start_notify(self, uuid_text, callback):
        self.notify_uuid = uuid_text
        self.callback = callback

    async def write_gatt_char(self, uuid_text, payload, response=False):
        self.writes.append((uuid_text, bytes(payload), response))


class TransportTests(unittest.IsolatedAsyncioTestCase):
    async def test_v1_fragments_use_conservative_write_size(self):
        client = FakeClient()
        pair = CharacteristicPair(uuid.uuid4(), uuid.uuid4())
        transport = BleakV1Transport(client, pair, max_write_size=20)
        packet = frame_gfdi(GarminMessage.SYSTEM_EVENT, bytes(range(40)))

        await transport.send_gfdi(packet)

        self.assertGreater(len(client.writes), 1)
        self.assertTrue(all(len(payload) <= 19 for _uuid, payload, _response in client.writes))

    async def test_v2_registration_error_is_reported_without_timeout(self):
        client = FakeClient()
        pair = CharacteristicPair(uuid.uuid4(), uuid.uuid4())
        transport = BleakV2Transport(client, pair, max_write_size=20)
        response = struct.pack(
            "<BQHBBB",
            REQUEST_REGISTER_ML_RESP,
            GADGETBRIDGE_CLIENT_ID,
            SERVICE_GFDI,
            3,
            0,
            0,
        )

        transport._handle_management(response)

        with self.assertRaises(TransportError):
            await transport._wait_for_gfdi_handle()


if __name__ == "__main__":
    unittest.main()
