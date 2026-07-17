from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from garmin_prg_sender.protocol import (  # noqa: E402
    CreateFileStatus,
    FileTransferDataStatus,
    FlagsStatus,
    GarminMessage,
    INSTALL_SYNC_BIT,
    ParsedMessage,
    SET_FILE_FLAG_ARCHIVE,
    SetFileFlagsStatus,
    Status,
    SupportedFileTypesStatus,
    TransferStatus,
    UploadChunker,
    UploadRequestStatus,
    UploadStatus,
    build_create_file,
    build_set_file_flag_archive,
    build_synchronization,
    cobs_encode,
    frame_gfdi,
    garmin_crc,
    parse_gfdi,
)


class ProtocolTests(unittest.TestCase):
    def test_cobs_roundtrip_with_zeros(self):
        from garmin_prg_sender.protocol import CobsDecoder

        payload = bytes([0, 1, 2, 0, 3, 4, 5, 0])
        decoder = CobsDecoder()
        self.assertEqual(decoder.feed(cobs_encode(payload)), [payload])

    def test_create_file_packet_is_gfdi_create_file(self):
        packet = build_create_file(1234, nonce=0)
        parsed = parse_gfdi(packet)
        self.assertEqual(parsed.message_type, GarminMessage.CREATE_FILE)

    def test_crc_is_incremental(self):
        data = b"abcdef"
        split = garmin_crc(data[3:], garmin_crc(data[:3]))
        self.assertEqual(split, garmin_crc(data))

    def test_upload_chunker_uses_gadgetbridge_payload_size(self):
        chunker = UploadChunker(bytes(range(255)) * 3, max_packet_size=375)
        first = chunker.next_chunk()
        second = chunker.next_chunk()
        self.assertIsNotNone(first)
        self.assertIsNotNone(second)
        self.assertEqual(len(first.data), 362)
        self.assertEqual(second.offset, 362)

    def test_upload_chunker_can_start_from_watch_offset(self):
        data = bytes(range(40))
        seed = garmin_crc(data[:7])
        chunker = UploadChunker(data, max_packet_size=20, initial_offset=7, initial_crc=seed)
        chunk = chunker.next_chunk()
        self.assertEqual(chunk.offset, 7)
        self.assertEqual(chunk.running_crc, garmin_crc(chunk.data, seed))

    def test_parse_create_file_status(self):
        import struct

        payload = struct.pack("<HBBHBBH", GarminMessage.CREATE_FILE, Status.ACK, 0, 0x1234, 255, 17, 0x5678)
        parsed = parse_gfdi(frame_gfdi(GarminMessage.RESPONSE, payload))
        self.assertIsInstance(parsed, CreateFileStatus)
        self.assertTrue(parsed.can_proceed)
        self.assertEqual(parsed.file_index, 0x1234)

    def test_parse_upload_status(self):
        import struct

        payload = struct.pack("<HBBIIH", GarminMessage.UPLOAD_REQUEST, Status.ACK, UploadStatus.OK, 362, 1000, 0)
        parsed = parse_gfdi(frame_gfdi(GarminMessage.RESPONSE, payload))
        self.assertIsInstance(parsed, UploadRequestStatus)
        self.assertTrue(parsed.can_proceed)
        self.assertEqual(parsed.data_offset, 362)

    def test_parse_transfer_status(self):
        import struct

        payload = struct.pack("<HBBI", GarminMessage.FILE_TRANSFER_DATA, Status.ACK, TransferStatus.OK, 724)
        parsed = parse_gfdi(frame_gfdi(GarminMessage.RESPONSE, payload))
        self.assertIsInstance(parsed, FileTransferDataStatus)
        self.assertTrue(parsed.can_proceed)
        self.assertEqual(parsed.data_offset, 724)

    def test_build_synchronization_install_bitmask_4_byte(self):
        import struct

        parsed = parse_gfdi(build_synchronization(0))
        self.assertIsInstance(parsed, ParsedMessage)
        self.assertEqual(parsed.message_type, GarminMessage.SYNCHRONIZATION)
        sync_type, size, bitmask = struct.unpack("<BBI", parsed.raw)
        self.assertEqual(sync_type, 0)
        self.assertEqual(size, 4)
        self.assertEqual(bitmask, INSTALL_SYNC_BIT)

    def test_build_synchronization_install_bitmask_8_byte(self):
        import struct

        parsed = parse_gfdi(build_synchronization(2, bitmask_size=8))
        self.assertEqual(parsed.message_type, GarminMessage.SYNCHRONIZATION)
        sync_type, size, bitmask = struct.unpack("<BBQ", parsed.raw)
        self.assertEqual(sync_type, 2)
        self.assertEqual(size, 8)
        self.assertEqual(bitmask, INSTALL_SYNC_BIT)

    def test_build_set_file_flag_archive(self):
        import struct

        parsed = parse_gfdi(build_set_file_flag_archive(0x1234))
        self.assertEqual(parsed.message_type, GarminMessage.SET_FILE_FLAG)
        file_index, flags = struct.unpack("<HB", parsed.raw)
        self.assertEqual(file_index, 0x1234)
        self.assertEqual(flags, SET_FILE_FLAG_ARCHIVE)

    def test_parse_set_file_flag_status(self):
        import struct

        payload = struct.pack("<HBBHB", GarminMessage.SET_FILE_FLAG, Status.ACK, FlagsStatus.APPLIED, 0x1234, SET_FILE_FLAG_ARCHIVE)
        parsed = parse_gfdi(frame_gfdi(GarminMessage.RESPONSE, payload))
        self.assertIsInstance(parsed, SetFileFlagsStatus)
        self.assertTrue(parsed.can_proceed)
        self.assertEqual(parsed.file_identifier, 0x1234)
        self.assertEqual(parsed.flags, SET_FILE_FLAG_ARCHIVE)

    def test_parse_supported_file_types_status(self):
        import struct

        name = b"PRG"
        payload = (
            struct.pack("<HB", GarminMessage.SUPPORTED_FILE_TYPES_REQUEST, Status.ACK)
            + bytes([1, 255, 17, len(name)])
            + name
        )
        parsed = parse_gfdi(frame_gfdi(GarminMessage.RESPONSE, payload))
        self.assertIsInstance(parsed, SupportedFileTypesStatus)
        self.assertTrue(parsed.can_proceed)
        self.assertEqual(len(parsed.file_types), 1)
        self.assertTrue(parsed.file_types[0].is_prg)
        self.assertEqual(parsed.file_types[0].name, "PRG")


if __name__ == "__main__":
    unittest.main()
