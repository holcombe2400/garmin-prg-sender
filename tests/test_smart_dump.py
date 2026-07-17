from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from garmin_prg_sender.smart_dump import (  # noqa: E402
    build_http_unknown_status_response,
    describe_smart_payload,
    find_http_raw_requests,
)


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


def header(key: str, value: str) -> bytes:
    return field_bytes(5, field_bytes(1, key.encode("utf-8")) + field_bytes(2, value.encode("utf-8")))


class SmartDumpTests(unittest.TestCase):
    def test_describe_http_raw_request_redacts_sensitive_values(self):
        raw_request = b"".join(
            [
                field_bytes(1, b"https://apps.garmin.com/connectiq?token=secret&normal=1"),
                field_varint(3, 1),
                header("Authorization", "Bearer secret"),
                header("Accept", "application/json"),
                field_varint(6, 1),
            ]
        )
        smart = field_bytes(2, field_bytes(5, raw_request))

        lines = describe_smart_payload(smart)
        text = "\n".join(lines)

        self.assertIn("CONNECT_IQ_HTTP_SERVICE", text)
        self.assertIn("method=GET", text)
        self.assertIn("token=REDACTED", text)
        self.assertIn("Authorization: REDACTED", text)
        self.assertIn("Accept: application/json", text)
        self.assertNotIn("Bearer secret", text)

        requests = find_http_raw_requests(smart)
        self.assertEqual(len(requests), 1)
        self.assertEqual(requests[0].method_name, "GET")
        self.assertTrue(requests[0].use_data_xfer)

    def test_build_http_unknown_status_response_is_decodable(self):
        lines = describe_smart_payload(build_http_unknown_status_response())
        text = "\n".join(lines)

        self.assertIn("CONNECT_IQ_HTTP_SERVICE", text)
        self.assertIn("Http.RawResponse status=UNKNOWN_STATUS", text)

    def test_describe_data_transfer_request(self):
        request = field_bytes(
            1,
            field_varint(1, 123)
            + field_varint(2, 456)
            + field_varint(3, 789),
        )
        smart = field_bytes(7, request)

        text = "\n".join(describe_smart_payload(smart))

        self.assertIn("DATA_TRANSFER_SERVICE", text)
        self.assertIn("DataDownloadRequest id=123 offset=456 maxChunkSize=789", text)


if __name__ == "__main__":
    unittest.main()
