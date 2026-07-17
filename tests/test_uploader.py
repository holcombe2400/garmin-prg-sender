from pathlib import Path
import struct
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from garmin_prg_sender.protocol import (  # noqa: E402
    CreateStatus,
    GarminMessage,
    ProtocolError,
    Status,
    TransferStatus,
    UploadStatus,
    frame_gfdi,
    garmin_crc,
    parse_gfdi,
)
from garmin_prg_sender.uploader import GarminPrgUploader  # noqa: E402


class FakeTransport:
    def __init__(self, replies):
        self.replies = list(replies)
        self.sent = []

    async def send_gfdi(self, packet: bytes) -> None:
        self.sent.append(packet)

    async def receive_gfdi(self, timeout: float = 20.0) -> bytes:
        return self.replies.pop(0)


def create_status(file_index: int = 1, data_type: int = 255, subtype: int = 17) -> bytes:
    payload = struct.pack(
        "<HBBHBBH",
        GarminMessage.CREATE_FILE,
        Status.ACK,
        CreateStatus.OK,
        file_index,
        data_type,
        subtype,
        0,
    )
    return frame_gfdi(GarminMessage.RESPONSE, payload)


def upload_status(size: int, offset: int = 0, crc_seed: int = 0) -> bytes:
    payload = struct.pack(
        "<HBBIIH",
        GarminMessage.UPLOAD_REQUEST,
        Status.ACK,
        UploadStatus.OK,
        offset,
        size,
        crc_seed,
    )
    return frame_gfdi(GarminMessage.RESPONSE, payload)


def transfer_status(offset: int, status: TransferStatus = TransferStatus.OK) -> bytes:
    payload = struct.pack(
        "<HBBI",
        GarminMessage.FILE_TRANSFER_DATA,
        Status.ACK,
        status,
        offset,
    )
    return frame_gfdi(GarminMessage.RESPONSE, payload)


def generic_status(original_message: int, status: Status = Status.ACK) -> bytes:
    payload = struct.pack("<HB", original_message, status)
    return frame_gfdi(GarminMessage.RESPONSE, payload)


def sent_data_offsets(sent_packets):
    offsets = []
    for packet in sent_packets:
        parsed = parse_gfdi(packet)
        if parsed.message_type == GarminMessage.FILE_TRANSFER_DATA:
            offsets.append(struct.unpack_from("<I", parsed.raw, 3)[0])
    return offsets


def sent_data_crcs(sent_packets):
    crcs = []
    for packet in sent_packets:
        parsed = parse_gfdi(packet)
        if parsed.message_type == GarminMessage.FILE_TRANSFER_DATA:
            crcs.append(struct.unpack_from("<H", parsed.raw, 1)[0])
    return crcs


class UploaderTests(unittest.IsolatedAsyncioTestCase):
    async def test_upload_reports_progress_and_sends_sync_complete(self):
        data = b"\xd0\x00\xd0abc"
        progress = []
        transport = FakeTransport(
            [
                generic_status(GarminMessage.SYSTEM_EVENT),
                create_status(file_index=7),
                upload_status(len(data)),
                transfer_status(len(data)),
                generic_status(GarminMessage.SYSTEM_EVENT),
            ]
        )
        uploader = GarminPrgUploader(
            transport,
            max_packet_size=32,
            post_sync_delay=0,
            progress_callback=lambda item: progress.append((item.offset, item.total, item.percent)),
        )

        result = await uploader.upload(data)

        sent_types = [parse_gfdi(packet).message_type for packet in transport.sent]
        self.assertEqual(
            sent_types,
            [
                GarminMessage.SYSTEM_EVENT,
                GarminMessage.CREATE_FILE,
                GarminMessage.UPLOAD_REQUEST,
                GarminMessage.FILE_TRANSFER_DATA,
                GarminMessage.SYSTEM_EVENT,
            ],
        )
        self.assertEqual(result.file_index, 7)
        self.assertEqual(result.total, len(data))
        self.assertEqual(progress[0], (0, len(data), 0))
        self.assertEqual(progress[-1], (len(data), len(data), 100))

    async def test_upload_can_skip_final_sync_complete_and_return_created_file(self):
        data = b"\xd0\x00\xd0abc"
        transport = FakeTransport(
            [
                generic_status(GarminMessage.SYSTEM_EVENT),
                create_status(file_index=9),
                upload_status(len(data)),
                transfer_status(len(data)),
            ]
        )
        uploader = GarminPrgUploader(
            transport,
            max_packet_size=32,
            post_sync_delay=0,
            send_final_sync_complete=False,
        )

        result = await uploader.upload(data)

        sent_types = [parse_gfdi(packet).message_type for packet in transport.sent]
        self.assertEqual(
            sent_types,
            [
                GarminMessage.SYSTEM_EVENT,
                GarminMessage.CREATE_FILE,
                GarminMessage.UPLOAD_REQUEST,
                GarminMessage.FILE_TRANSFER_DATA,
            ],
        )
        self.assertEqual(result.file_index, 9)
        self.assertEqual(result.total, len(data))

    async def test_upload_can_resume_from_watch_offset(self):
        data = b"\xd0\x00\xd0" + bytes(range(40))
        resume_offset = 7
        transport = FakeTransport(
            [
                generic_status(GarminMessage.SYSTEM_EVENT),
                create_status(file_index=7),
                upload_status(len(data), offset=resume_offset, crc_seed=garmin_crc(data[:resume_offset])),
                transfer_status(len(data)),
                generic_status(GarminMessage.SYSTEM_EVENT),
            ]
        )
        uploader = GarminPrgUploader(transport, max_packet_size=128, post_sync_delay=0)

        await uploader.upload(data)

        self.assertEqual(sent_data_offsets(transport.sent), [resume_offset])

    async def test_upload_resume_zero_seed_computes_local_crc(self):
        data = b"\xd0\x00\xd0" + bytes(range(40))
        resume_offset = 7
        transport = FakeTransport(
            [
                generic_status(GarminMessage.SYSTEM_EVENT),
                create_status(file_index=7),
                upload_status(len(data), offset=resume_offset, crc_seed=0),
                transfer_status(len(data)),
                generic_status(GarminMessage.SYSTEM_EVENT),
            ]
        )
        uploader = GarminPrgUploader(transport, max_packet_size=128, post_sync_delay=0)

        await uploader.upload(data)

        first_chunk = data[resume_offset:]
        self.assertEqual(sent_data_crcs(transport.sent), [garmin_crc(first_chunk, garmin_crc(data[:resume_offset]))])

    async def test_upload_rejects_unexpected_created_file_type(self):
        data = b"\xd0\x00\xd0abc"
        transport = FakeTransport([generic_status(GarminMessage.SYSTEM_EVENT), create_status(file_index=7, data_type=1, subtype=2)])
        uploader = GarminPrgUploader(transport, max_packet_size=32, post_sync_delay=0)

        with self.assertRaises(ProtocolError):
            await uploader.upload(data)

    async def test_upload_retries_resend_status_from_watch_offset(self):
        data = b"\xd0\x00\xd0abc"
        transport = FakeTransport(
            [
                generic_status(GarminMessage.SYSTEM_EVENT),
                create_status(file_index=7),
                upload_status(len(data)),
                transfer_status(0, TransferStatus.RESEND),
                transfer_status(len(data)),
                generic_status(GarminMessage.SYSTEM_EVENT),
            ]
        )
        uploader = GarminPrgUploader(transport, max_packet_size=32, max_retries=1, post_sync_delay=0)

        await uploader.upload(data)

        self.assertEqual(sent_data_offsets(transport.sent), [0, 0])

    async def test_upload_rejects_final_sync_failure(self):
        data = b"\xd0\x00\xd0abc"
        transport = FakeTransport(
            [
                generic_status(GarminMessage.SYSTEM_EVENT),
                create_status(file_index=7),
                upload_status(len(data)),
                transfer_status(len(data)),
                generic_status(GarminMessage.SYSTEM_EVENT, Status.NAK),
            ]
        )
        uploader = GarminPrgUploader(transport, max_packet_size=32, post_sync_delay=0)

        with self.assertRaises(ProtocolError):
            await uploader.upload(data)


if __name__ == "__main__":
    unittest.main()
