from pathlib import Path
import struct
import sys
import unittest
import uuid

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from garmin_prg_sender.protobuf import (  # noqa: E402
    GARMON_APP_ID,
    GARMON_APP_NAME,
    GarminProtobufClient,
    build_get_installed_apps_request,
    parse_installed_apps_response,
)
from garmin_prg_sender.protocol import (  # noqa: E402
    GarminMessage,
    Status,
    build_generic_status,
    build_protobuf_packet,
    parse_gfdi,
)


class FakeTransport:
    def __init__(self, replies):
        self.replies = list(replies)
        self.sent = []

    async def send_gfdi(self, packet: bytes) -> None:
        self.sent.append(packet)

    async def receive_gfdi(self, timeout: float = 20.0) -> bytes:
        return self.replies.pop(0)


def field_varint(number: int, value: int) -> bytes:
    return encode_varint((number << 3) | 0) + encode_varint(value)


def field_bytes(number: int, value: bytes) -> bytes:
    return encode_varint((number << 3) | 2) + encode_varint(len(value)) + value


def encode_varint(value: int) -> bytes:
    out = bytearray()
    while value >= 0x80:
        out.append((value & 0x7F) | 0x80)
        value >>= 7
    out.append(value)
    return bytes(out)


def sample_installed_apps_payload() -> bytes:
    app = b"".join(
        [
            field_bytes(1, uuid.UUID(GARMON_APP_ID).bytes),
            field_varint(2, 1),
            field_bytes(3, GARMON_APP_NAME.encode("utf-8")),
            field_varint(4, 0),
            field_bytes(6, b"Garmon.prg"),
            field_varint(7, 43148),
        ]
    )
    response = b"".join(
        [
            field_varint(1, 123456),
            field_varint(2, 12),
            field_bytes(3, app),
        ]
    )
    service = field_bytes(2, response)
    return field_bytes(3, service)


class GarminProtobufTests(unittest.TestCase):
    def test_build_get_installed_apps_request_matches_gadgetbridge_shape(self):
        self.assertEqual(build_get_installed_apps_request(), bytes.fromhex("1a 04 0a 02 08 05"))

    def test_parse_installed_apps_response_and_find_garmon(self):
        result = parse_installed_apps_response(sample_installed_apps_payload())

        self.assertEqual(result.available_space, 123456)
        self.assertEqual(result.available_slots, 12)
        self.assertEqual(len(result.apps), 1)
        self.assertEqual(result.apps[0].name, "Garmon")
        self.assertIsNotNone(result.find(app_id=GARMON_APP_ID, app_name=GARMON_APP_NAME))


class GarminProtobufClientTests(unittest.IsolatedAsyncioTestCase):
    async def test_query_installed_apps_acks_response(self):
        transport = FakeTransport(
            [
                build_generic_status(GarminMessage.PROTOBUF_REQUEST, Status.ACK),
                build_protobuf_packet(GarminMessage.PROTOBUF_RESPONSE, 1, sample_installed_apps_payload()),
            ]
        )
        client = GarminProtobufClient(transport, timeout=1, request_id=1)

        result = await client.query_installed_apps()

        self.assertIsNotNone(result.find(app_id=GARMON_APP_ID, app_name=GARMON_APP_NAME))
        request = parse_gfdi(transport.sent[0])
        self.assertEqual(request.message_type, GarminMessage.PROTOBUF_REQUEST)
        ack = parse_gfdi(transport.sent[-1])
        self.assertEqual(ack.original_message_type, GarminMessage.PROTOBUF_RESPONSE)


if __name__ == "__main__":
    unittest.main()
