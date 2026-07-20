from __future__ import annotations

import argparse
import asyncio
import subprocess
import sys
import traceback
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path

from .logging_transport import PacketLoggingTransport
from .log_summary import print_packet_log_summary
from .protobuf import (
    GARMON_APP_ID,
    GARMON_APP_NAME,
    GarminProtobufClient,
    format_installed_app,
)
from .protocol import (
    GarminMessage,
    GenericStatus,
    ParsedMessage,
    ProtocolError,
    ProtobufPacket,
    ProtobufStatus,
    SetFileFlagsStatus,
    SupportedFileTypesStatus,
    SystemEvent,
    UploadChunker,
    build_create_file,
    build_file_transfer_data,
    build_generic_status,
    build_protobuf_packet,
    build_protobuf_status,
    build_set_file_flag_archive,
    build_sync_ready,
    build_sync_complete,
    build_supported_file_types_request,
    build_synchronization,
    build_upload_request,
    build_system_event,
    cobs_encode,
    load_prg,
    parse_gfdi,
)
from .smart_dump import (
    build_http_unknown_status_response,
    describe_smart_payload,
    find_http_raw_requests,
)
from .transport import GarminTransport, create_ble_transport, inspect_garmin_support
from .uploader import GarminPrgUploader, UploadProgress, UploadResult
from .windows_diagnostic import (
    list_windows_ble_devices,
    pair_windows_ble_device,
    run_winrt_diagnostic,
    unpair_windows_ble_device,
    wait_for_live_gatt,
)


DEFAULT_GARMON_PRG = Path(__file__).resolve().parents[2] / "test-prgs" / "GarmonInstallTest_fenix6pro_43KB.prg"

POST_UPLOAD_TRIGGER_CHOICES = (
    "none",
    "new-download",
    "device-disconnect",
    "sync-install-type0",
    "sync-install-type1",
    "sync-install-type2",
    "archive-created-file",
    "archive-created-file-number",
    "sync-install-type0-8byte",
    "sync-install-type1-8byte",
    "sync-install-type2-8byte",
)

GARMIN_CONNECT_STAGE_TRIGGER = "none"

INDEX_LADDER_TRIGGERS = (
    "none",
    "new-download",
    "device-disconnect",
    "sync-install-type0",
    "sync-install-type1",
    "sync-install-type2",
    "archive-created-file",
    "archive-created-file-number",
    "sync-install-type0-8byte",
    "sync-install-type1-8byte",
    "sync-install-type2-8byte",
)


@dataclass(frozen=True)
class TriggerResult:
    trigger: str
    registered: bool | None
    query_failed: bool = False
    trigger_failed: str | None = None


@dataclass(frozen=True)
class InstalledAppsCheck:
    registered: bool | None
    query_failed: bool = False


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Send a Garmin Connect IQ .prg file over Bluetooth using Gadgetbridge's GFDI upload flow.")
    parser.add_argument("--file", type=Path, help="Path to the .prg file")
    parser.add_argument("--address", help="BLE address/device id to connect to")
    parser.add_argument("--address-type", choices=("public", "random"), help="Windows BLE address type override")
    parser.add_argument("--winrt-services", choices=("auto", "cached", "uncached"), default="auto", help="Windows GATT service cache mode")
    parser.add_argument("--name", help="Case-insensitive substring of the watch BLE name")
    parser.add_argument("--transport", choices=("auto", "v2", "v1"), default="auto", help="Garmin GFDI transport to use")
    parser.add_argument("--max-packet-size", type=int, default=375, help="GFDI max packet size; Gadgetbridge defaults to 375")
    parser.add_argument("--max-write-size", type=int, help="Override BLE write fragment size")
    parser.add_argument("--timeout", type=float, default=20.0, help="Seconds to wait for each watch response")
    parser.add_argument("--sync-timeout", type=float, default=None, help="Seconds to wait for each watch system-event ACK; defaults to --timeout")
    parser.add_argument("--post-sync-delay", type=float, default=2.0, help="Seconds to stay connected after final SYNC_COMPLETE ACK")
    parser.add_argument("--no-post-upload-verify", action="store_true", help="Skip installed-apps protobuf verification after upload")
    parser.add_argument(
        "--stage-for-garmin-connect",
        action="store_true",
        help="Stage a PRG over BLE, then let Garmin Connect on a paired phone complete Connect IQ registration",
    )
    parser.add_argument("--query-installed-apps", action="store_true", help="Connect and query Garmin's installed-apps protobuf service without uploading")
    parser.add_argument("--query-supported-file-types", action="store_true", help="Connect and query Garmin's supported GFDI file types")
    parser.add_argument("--protobuf-listen", action="store_true", help="Listen for watch-originated Garmin Smart protobuf traffic and print decoded fields")
    parser.add_argument("--listen-seconds", type=float, default=60.0, help="Seconds to listen in --protobuf-listen mode")
    parser.add_argument("--listen-phone-events", action="store_true", help="In --protobuf-listen mode, send safe foreground/SYNC_READY events to prompt phone-service requests")
    parser.add_argument("--listen-setup-events", action="store_true", help="In --protobuf-listen mode, also send pair/setup-complete events to mimic an initialized phone")
    parser.add_argument("--listen-http-unknown", action="store_true", help="In --protobuf-listen mode, reply to HTTP RawRequest messages with UNKNOWN_STATUS")
    parser.add_argument("--usb-sideload", action="store_true", help="Copy a PRG to GARMIN\\Apps over USB/MTP using the proven sideload path")
    parser.add_argument("--usb-soft-install", action="store_true", help="Copy a PRG over USB/MTP, restart the Garmin WPD device, and verify registration over BLE when possible")
    parser.add_argument("--usb-device-pattern", default="fenix|Garmin", help="Regex used to find the Garmin MTP device in Windows shell")
    parser.add_argument("--usb-timeout", type=int, default=180, help="Seconds to wait for MTP copy/disconnect/reconnect steps")
    parser.add_argument("--usb-mtp-return-timeout", type=int, default=45, help="Seconds to wait for MTP to return after USB soft install")
    parser.add_argument("--usb-wait-for-disconnect", action="store_true", help="After USB sideload copy, wait for the watch to be unplugged")
    parser.add_argument("--usb-wait-for-reconnect", action="store_true", help="After USB sideload copy/disconnect, wait for the watch to reconnect")
    parser.add_argument(
        "--post-upload-trigger",
        choices=POST_UPLOAD_TRIGGER_CHOICES,
        default=None,
        help="Registration trigger to send after PRG bytes upload",
    )
    parser.add_argument("--run-index-ladder", action="store_true", help="Run the safe Garmon registration-trigger ladder")
    parser.add_argument("--verify-delay", type=float, default=10.0, help="Seconds to wait after disconnecting before installed-app verification")
    parser.add_argument("--verify-app-id", default=GARMON_APP_ID, help="Connect IQ app UUID to verify in installed-apps results")
    parser.add_argument("--verify-app-name", default=GARMON_APP_NAME, help="Connect IQ app name to verify in installed-apps results")
    parser.add_argument("--show-installed-apps", action="store_true", help="Print installed-app rows returned by the watch")
    parser.add_argument("--skip-sync-ack", action="store_true", help="Do not wait for ACKs to Garmin system events")
    parser.add_argument("--skip-sync-ready", action="store_true", help="Do not send Gadgetbridge-style SYNC_READY before uploading")
    parser.add_argument("--first-connect-events", action="store_true", help="Also send Gadgetbridge's first-pair setup completion events before uploading")
    parser.add_argument("--connect-timeout", type=float, default=45.0, help="Seconds to wait for BLE connection setup")
    parser.add_argument("--progress-step", type=int, default=5, help="Minimum percentage step between upload progress lines; 0 prints every acknowledged chunk")
    parser.add_argument("--upload-retries", type=int, default=3, help="Recoverable chunk retries before upload fails")
    parser.add_argument("--packet-log", type=Path, help="Write compact JSONL GFDI packet log for live uploads")
    parser.add_argument("--packet-log-bytes", type=int, default=64, help="Payload prefix bytes to include per packet log row")
    parser.add_argument("--summarize-log", type=Path, help="Summarize a JSONL packet log and exit")
    parser.add_argument("--dry-run", action="store_true", help="Validate and build packets without using Bluetooth")
    parser.add_argument("--scan", action="store_true", help="List nearby BLE devices and exit")
    parser.add_argument("--scan-seconds", type=float, default=8.0, help="BLE scan duration")
    parser.add_argument("--list-windows-ble", action="store_true", help="List cached Windows BLE devices and extracted addresses")
    parser.add_argument("--pair-windows-ble", action="store_true", help="Pair a visible BLE device with Windows; use --address or --name")
    parser.add_argument("--pair-scan-seconds", type=float, default=12.0, help="BLE scan duration when pairing by --name")
    parser.add_argument("--unpair-windows-ble", action="store_true", help="Remove a cached Windows BLE pairing entry; dry-run unless --confirm-unpair is provided")
    parser.add_argument("--confirm-unpair", action="store_true", help="Actually remove the Windows BLE pairing entry selected by --unpair-windows-ble")
    parser.add_argument("--probe", action="store_true", help="Connect and list GATT services without writing")
    parser.add_argument("--probe-gfdi", action="store_true", help="Connect and register Garmin GFDI, but do not upload")
    parser.add_argument("--winrt-diagnostic", action="store_true", help="Ask Windows directly for paired-device and GATT status")
    parser.add_argument("--wait-live", action="store_true", help="Wait until Windows can open live GATT services for a paired watch")
    parser.add_argument("--wait-seconds", type=float, default=300.0, help="Maximum seconds for --wait-live")
    parser.add_argument("--retry-seconds", type=float, default=5.0, help="Seconds between --wait-live checks")
    parser.add_argument("--debug", action="store_true", help="Print tracebacks for Bluetooth errors")
    args = parser.parse_args(argv)

    if args.summarize_log:
        try:
            print_packet_log_summary(args.summarize_log)
            return 0
        except Exception as exc:
            if args.debug:
                traceback.print_exc()
            print(f"Packet log summary failed: {exc}", file=sys.stderr)
            return 1

    if args.list_windows_ble:
        try:
            return asyncio.run(list_windows_ble_devices(args.name, timeout=args.connect_timeout))
        except Exception as exc:
            if args.debug:
                traceback.print_exc()
            print(f"Windows BLE listing failed: {exc}", file=sys.stderr)
            return 1

    if args.pair_windows_ble:
        try:
            return asyncio.run(
                pair_windows_ble_device(
                    args.address,
                    args.name,
                    args.address_type,
                    timeout=args.connect_timeout,
                    scan_seconds=args.pair_scan_seconds,
                )
            )
        except Exception as exc:
            if args.debug:
                traceback.print_exc()
            print(f"Windows BLE pairing failed: {exc}", file=sys.stderr)
            return 1

    if args.unpair_windows_ble:
        try:
            return asyncio.run(unpair_windows_ble_device(args.address, args.name, args.confirm_unpair, timeout=args.connect_timeout))
        except Exception as exc:
            if args.debug:
                traceback.print_exc()
            print(f"Windows BLE unpair failed: {exc}", file=sys.stderr)
            return 1

    if args.wait_live:
        if not args.address:
            print("Provide --address for --wait-live.", file=sys.stderr)
            return 2
        try:
            return asyncio.run(wait_for_live_gatt(args.address, args.address_type, args.wait_seconds, args.retry_seconds, args.connect_timeout))
        except Exception as exc:
            if args.debug:
                traceback.print_exc()
            print(f"Live GATT wait failed: {exc}", file=sys.stderr)
            return 1

    if args.winrt_diagnostic:
        if not args.address:
            print("Provide --address for WinRT diagnostics.", file=sys.stderr)
            return 2
        try:
            return asyncio.run(run_winrt_diagnostic(args.address, args.address_type, args.connect_timeout))
        except Exception as exc:
            if args.debug:
                traceback.print_exc()
            print(f"WinRT diagnostic failed: {exc}", file=sys.stderr)
            return 1

    if args.scan:
        try:
            return asyncio.run(_scan(args.scan_seconds))
        except Exception as exc:
            if args.debug:
                traceback.print_exc()
            print(f"Scan failed: {exc}", file=sys.stderr)
            return 1

    if args.probe or args.probe_gfdi:
        if not args.address and not args.name:
            print("Provide --address or --name for probing.", file=sys.stderr)
            return 2
        try:
            return asyncio.run(_probe(args))
        except Exception as exc:
            if args.debug:
                traceback.print_exc()
            print(f"Probe failed: {exc}", file=sys.stderr)
            return 1

    if args.query_installed_apps:
        if not args.address and not args.name:
            print("Provide --address or --name for installed-apps query.", file=sys.stderr)
            return 2
        try:
            return asyncio.run(_query_installed_apps(args))
        except Exception as exc:
            if args.debug:
                traceback.print_exc()
            print(f"Installed-apps query failed: {exc}", file=sys.stderr)
            return 1

    if args.query_supported_file_types:
        if not args.address and not args.name:
            print("Provide --address or --name for supported-file-types query.", file=sys.stderr)
            return 2
        try:
            return asyncio.run(_query_supported_file_types(args))
        except Exception as exc:
            if args.debug:
                traceback.print_exc()
            print(f"Supported-file-types query failed: {exc}", file=sys.stderr)
            return 1

    if args.protobuf_listen:
        if not args.address and not args.name:
            print("Provide --address or --name for protobuf listen mode.", file=sys.stderr)
            return 2
        try:
            return asyncio.run(_protobuf_listen(args))
        except KeyboardInterrupt:
            return 130
        except Exception as exc:
            if args.debug:
                traceback.print_exc()
            print(f"Protobuf listen failed: {exc}", file=sys.stderr)
            return 1

    if args.run_index_ladder:
        try:
            args.file = _safe_garmon_ladder_file(args.file)
        except ProtocolError as exc:
            print(f"Index ladder setup failed: {exc}", file=sys.stderr)
            return 2

    if args.stage_for_garmin_connect and (args.usb_sideload or args.usb_soft_install):
        print("--stage-for-garmin-connect is a Bluetooth-only upload mode.", file=sys.stderr)
        return 2

    if (args.usb_sideload or args.usb_soft_install) and args.file is None:
        args.file = DEFAULT_GARMON_PRG

    if args.file is None:
        print("Provide --file, or use --scan to list BLE devices.", file=sys.stderr)
        return 2

    try:
        data = load_prg(args.file)
    except (OSError, ProtocolError) as exc:
        print(f"PRG validation failed: {exc}", file=sys.stderr)
        return 2

    if args.dry_run:
        _dry_run(data, args.max_packet_size)
        return 0

    if args.usb_sideload:
        return _usb_sideload(args)
    if args.usb_soft_install:
        return _usb_soft_install(args)

    if not args.address and not args.name:
        print("Provide --address or --name for live Bluetooth sending.", file=sys.stderr)
        return 2

    if args.stage_for_garmin_connect:
        _prepare_garmin_connect_stage(args)

    try:
        if args.run_index_ladder:
            return asyncio.run(_run_index_ladder(args, data))
        return asyncio.run(_send(args, data))
    except KeyboardInterrupt:
        return 130
    except Exception as exc:
        if args.debug:
            traceback.print_exc()
        print(f"Upload failed: {exc}", file=sys.stderr)
        return 1


def _dry_run(data: bytes, max_packet_size: int) -> None:
    create = build_create_file(len(data), nonce=0)
    upload = build_upload_request(1, len(data))
    chunker = UploadChunker(data, max_packet_size)
    first_chunk = chunker.next_chunk()
    print(f"PRG size: {len(data)} bytes")
    print(f"SyncReady packet: {len(build_sync_ready())} bytes")
    print(f"CreateFile packet: {len(create)} bytes, COBS {len(cobs_encode(create))} bytes")
    print(f"UploadRequest packet: {len(upload)} bytes, COBS {len(cobs_encode(upload))} bytes")
    if first_chunk is not None:
        data_packet = build_file_transfer_data(first_chunk.data, first_chunk.offset, first_chunk.running_crc)
        print(f"First data packet: {len(data_packet)} bytes, COBS {len(cobs_encode(data_packet))} bytes, payload {len(first_chunk.data)} bytes")
    print(f"SyncComplete packet: {len(build_sync_complete())} bytes")
    print(f"Chunk payload size: {max_packet_size - 13} bytes")
    print(f"Total chunks: {(len(data) + (max_packet_size - 14)) // (max_packet_size - 13)}")


def _usb_sideload(args) -> int:
    root = Path(__file__).resolve().parents[2]
    script = root / "scripts" / "Install-GarminPrgMtp.ps1"
    if not script.exists():
        print(f"USB sideload script not found: {script}", file=sys.stderr)
        return 1

    command = [
        "powershell",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(script),
        "-Prg",
        str(args.file),
        "-DevicePattern",
        args.usb_device_pattern,
        "-TimeoutSeconds",
        str(args.usb_timeout),
        "-Copy",
    ]
    if args.usb_wait_for_disconnect:
        command.append("-WaitForDisconnect")
    if args.usb_wait_for_reconnect:
        command.append("-WaitForReconnect")

    print("Running USB/MTP sideload copy.")
    print("After the PRG copy appears, unplug the watch and let its loading/indexing screen finish.")
    completed = subprocess.run(command, cwd=str(root))
    return completed.returncode


def _usb_soft_install(args) -> int:
    root = Path(__file__).resolve().parents[2]
    script = root / "scripts" / "Run-GarminSoftDisconnectIndexExperiment.ps1"
    if not script.exists():
        print(f"USB soft-install script not found: {script}", file=sys.stderr)
        return 1

    command = [
        "powershell",
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(script),
        "-Prg",
        str(args.file),
        "-DevicePattern",
        args.usb_device_pattern,
        "-TimeoutSeconds",
        str(args.usb_timeout),
        "-MtpReturnTimeoutSeconds",
        str(args.usb_mtp_return_timeout),
        "-TryPnpRestart",
    ]
    if args.address:
        command.extend(["-BleAddress", args.address])
    else:
        print("No --address supplied; soft install can stage/restart but cannot verify over BLE.")

    print("Running USB soft install.")
    print("This stages the PRG over MTP, restarts the Garmin WPD device, then verifies over BLE if --address is supplied.")
    print("Note: Windows may leave the watch in Garmin USB GPS mode afterward; physically unplug/replug to restore MTP if needed.")
    completed = subprocess.run(command, cwd=str(root))
    return completed.returncode


async def _send(args, data: bytes) -> int:
    trigger = _selected_post_upload_trigger(args)
    result = await _upload_with_trigger_once(
        args,
        data,
        trigger,
        packet_log=args.packet_log,
        verify=not args.no_post_upload_verify,
        allow_trigger_failure=args.stage_for_garmin_connect,
    )
    if args.stage_for_garmin_connect:
        _print_garmin_connect_stage_result(args, result)
        _write_garmin_connect_stage_notes(args, result)
        return 0
    if result.trigger_failed:
        return 1
    return 0


async def _upload_with_trigger_once(
    args,
    data: bytes,
    trigger: str,
    *,
    packet_log: Path | None,
    verify: bool,
    allow_trigger_failure: bool = False,
) -> TriggerResult:
    try:
        from bleak import BleakClient, BleakScanner
    except ImportError as exc:
        raise RuntimeError("Install dependencies first: python -m pip install -r requirements.txt") from exc

    device = None
    if args.address:
        device = _device_from_address(args.address)
    else:
        print("Scanning for BLE devices...")
        device = await _resolve_by_name(BleakScanner, args.name, args.scan_seconds)

    client_kwargs = _client_kwargs(args)
    async with BleakClient(device, **client_kwargs) as client:
        if not client.is_connected:
            raise RuntimeError("BLE connection failed")
        transport = await create_ble_transport(client, force=args.transport, max_write_size=args.max_write_size)
        packet_logger = None
        if packet_log:
            transport = PacketLoggingTransport(transport, packet_log, max_payload_bytes=args.packet_log_bytes)
            packet_logger = transport
            print(f"Writing packet log to {packet_log}")
        trigger_failed: str | None = None
        try:
            uploader = GarminPrgUploader(
                transport,
                max_packet_size=args.max_packet_size,
                timeout=args.timeout,
                max_retries=args.upload_retries,
                sync_timeout=args.sync_timeout,
                post_sync_delay=0,
                wait_for_sync_ack=not args.skip_sync_ack,
                send_sync_ready=not args.skip_sync_ready,
                send_first_connect_events=args.first_connect_events,
                send_final_sync_complete=False,
                progress_callback=_progress_printer(args.progress_step),
            )
            upload_result = await uploader.upload(data)
            print(
                "Upload completed; PRG bytes acknowledged "
                f"(file_index={upload_result.file_index}, file_number={upload_result.file_number})."
            )
            try:
                await _apply_post_upload_trigger(transport, args, trigger, upload_result)
            except ProtocolError as exc:
                if not allow_trigger_failure:
                    raise
                trigger_failed = str(exc)
                print(f"Post-upload trigger was not acknowledged cleanly: {trigger_failed}")
        finally:
            if packet_logger is not None:
                packet_logger.close()

    if not verify:
        return TriggerResult(trigger=trigger, registered=None, trigger_failed=trigger_failed)

    if args.verify_delay > 0:
        print(f"Disconnected. Waiting {args.verify_delay:g}s before installed-app verification.")
        await asyncio.sleep(args.verify_delay)
    check = await _query_installed_apps_after_reconnect(
        args,
        upload_completed=True,
        show_apps=args.show_installed_apps,
        packet_log=packet_log,
    )
    return TriggerResult(trigger=trigger, registered=check.registered, query_failed=check.query_failed)


def _selected_post_upload_trigger(args) -> str:
    if args.post_upload_trigger is not None:
        return args.post_upload_trigger
    if args.stage_for_garmin_connect:
        return GARMIN_CONNECT_STAGE_TRIGGER
    return "none"


def _prepare_garmin_connect_stage(args) -> None:
    if args.post_upload_trigger is None:
        args.post_upload_trigger = GARMIN_CONNECT_STAGE_TRIGGER
    args.no_post_upload_verify = True
    if args.packet_log is None:
        args.packet_log = _garmin_connect_stage_log_path()
    print("Staging PRG for Garmin Connect phone sync.")
    print(f"Stage trigger: {_selected_post_upload_trigger(args)}")


def _garmin_connect_stage_log_path() -> Path:
    logs = Path(__file__).resolve().parents[2] / "logs"
    logs.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    return logs / f"stage-for-garmin-connect-{stamp}.jsonl"


def _print_garmin_connect_stage_result(args, result: TriggerResult) -> None:
    print("")
    print("PRG staged for Garmin Connect phone sync")
    print(f"Bytes acknowledged over BLE. Trigger used: {result.trigger}.")
    if result.trigger_failed:
        print("Post-upload trigger detail: " + result.trigger_failed)
        print("Continuing because staged mode treats the full byte ACK as success; Garmin Connect supplies the registration pass.")
    if args.packet_log:
        print(f"Packet log: {args.packet_log}")
        print(f"Next steps file: {Path(args.packet_log).with_suffix('.next-steps.txt')}")
    print("Next step: turn phone Bluetooth back on so Garmin Connect can reconnect in the background.")
    print("Opening Garmin Connect or forcing a sync is a fallback if the install message does not appear.")
    print("Expected proof: the watch shows a Garmin Connect IQ installed message, then the app appears in Connect IQ/apps.")


def _write_garmin_connect_stage_notes(args, result: TriggerResult) -> None:
    if not args.packet_log:
        return
    notes_path = Path(args.packet_log).with_suffix(".next-steps.txt")
    trigger_detail = result.trigger_failed or "acknowledged cleanly"
    lines = [
        "Garmin Connect phone-sync stage",
        "",
        f"PRG: {args.file}",
        f"Watch address: {args.address or args.name or '(resolved by scan)'}",
        f"Trigger: {result.trigger}",
        f"Post-upload trigger detail: {trigger_detail}",
        f"Packet log: {args.packet_log}",
        "",
        "Result:",
        "PRG staged for Garmin Connect phone sync",
        "The watch acknowledged all PRG bytes over BLE. This mode intentionally skips immediate installed-app verification.",
        "",
        "Next steps:",
        "1. Turn phone Bluetooth back on.",
        "2. Let Garmin Connect reconnect in the background.",
        "3. Watch for the Garmin Connect IQ installed message on the watch.",
        "4. If the install message does not appear, open Garmin Connect and force a sync.",
        "5. If needed, use Check Install in this sender after phone sync finishes.",
        "",
    ]
    notes_path.write_text("\n".join(lines), encoding="utf-8")


async def _apply_post_upload_trigger(
    transport: GarminTransport,
    args,
    trigger: str,
    upload_result: UploadResult,
) -> None:
    if trigger == "none":
        await _send_system_event_and_wait(transport, args, SystemEvent.SYNC_COMPLETE, "SYNC_COMPLETE")
        print("Post-upload trigger: none (SYNC_COMPLETE baseline).")
        return

    if trigger == "new-download":
        await _send_system_event_and_wait(transport, args, SystemEvent.NEW_DOWNLOAD_AVAILABLE, "NEW_DOWNLOAD_AVAILABLE")
        await _send_system_event_and_wait(transport, args, SystemEvent.SYNC_COMPLETE, "SYNC_COMPLETE")
        print("Post-upload trigger: NEW_DOWNLOAD_AVAILABLE then SYNC_COMPLETE.")
        return

    if trigger == "device-disconnect":
        await _send_system_event_and_wait(transport, args, SystemEvent.SYNC_COMPLETE, "SYNC_COMPLETE")
        await _send_system_event_allowing_disconnect(
            transport,
            args,
            SystemEvent.DEVICE_DISCONNECT,
            "DEVICE_DISCONNECT",
        )
        print("Post-upload trigger: SYNC_COMPLETE then DEVICE_DISCONNECT.")
        return

    if trigger in {"archive-created-file", "archive-created-file-number"}:
        file_identifier = upload_result.file_number if trigger == "archive-created-file-number" else upload_result.file_index
        identifier_label = "file_number" if trigger == "archive-created-file-number" else "file_index"
        response = await _send_and_wait_status(
            transport,
            build_set_file_flag_archive(file_identifier),
            SetFileFlagsStatus,
            GarminMessage.SET_FILE_FLAG,
            "SET_FILE_FLAG ARCHIVE",
            timeout=args.timeout,
        )
        if isinstance(response, SetFileFlagsStatus):
            print(
                "Post-upload trigger: SET_FILE_FLAG ARCHIVE "
                f"sent {identifier_label}={file_identifier} "
                f"response_file_identifier={response.file_identifier} flags=0x{response.flags:02x}."
            )
        await _send_system_event_and_wait(transport, args, SystemEvent.SYNC_COMPLETE, "SYNC_COMPLETE")
        return

    if trigger.startswith("sync-install-type"):
        suffix = trigger.removeprefix("sync-install-type")
        sync_type_text = suffix.split("-", 1)[0]
        sync_type = int(sync_type_text)
        bitmask_size = 8 if trigger.endswith("-8byte") else 4
        await _send_and_wait_status(
            transport,
            build_synchronization(sync_type, bitmask_size=bitmask_size),
            GenericStatus,
            GarminMessage.SYNCHRONIZATION,
            f"SYNCHRONIZATION type {sync_type} INSTALL bitmask",
            timeout=args.timeout,
        )
        print(f"Post-upload trigger: SYNCHRONIZATION type={sync_type} INSTALL bitmask_size={bitmask_size}.")
        return

    raise ProtocolError(f"Unknown post-upload trigger: {trigger}")


async def _send_system_event_and_wait(
    transport: GarminTransport,
    args,
    event: SystemEvent,
    description: str,
) -> None:
    await transport.send_gfdi(build_system_event(event, 0))
    if args.skip_sync_ack:
        print(f"{description} sent without waiting for ACK.")
        return
    await _receive_expected_status(
        transport,
        GenericStatus,
        GarminMessage.SYSTEM_EVENT,
        description,
        timeout=args.sync_timeout if args.sync_timeout is not None else args.timeout,
    )


async def _send_system_event_allowing_disconnect(
    transport: GarminTransport,
    args,
    event: SystemEvent,
    description: str,
) -> None:
    await transport.send_gfdi(build_system_event(event, 0))
    if args.skip_sync_ack:
        print(f"{description} sent without waiting for ACK.")
        return

    timeout = args.sync_timeout if args.sync_timeout is not None else args.timeout
    timeout = min(timeout, 5.0)
    try:
        await _receive_expected_status(
            transport,
            GenericStatus,
            GarminMessage.SYSTEM_EVENT,
            description,
            timeout=timeout,
        )
    except ProtocolError:
        raise
    except Exception as exc:
        print(
            f"{description} ACK was not confirmed ({type(exc).__name__}: {exc}); "
            "continuing because a disconnect is plausible for this trigger."
        )


async def _send_and_wait_status(
    transport: GarminTransport,
    packet: bytes,
    expected_type,
    original_message_type: GarminMessage,
    description: str,
    *,
    timeout: float,
):
    await transport.send_gfdi(packet)
    return await _receive_expected_status(
        transport,
        expected_type,
        original_message_type,
        description,
        timeout=timeout,
    )


async def _receive_expected_status(
    transport: GarminTransport,
    expected_type,
    original_message_type: GarminMessage,
    description: str,
    *,
    timeout: float,
):
    while True:
        packet = await transport.receive_gfdi(timeout=timeout)
        message = parse_gfdi(packet)
        if isinstance(message, expected_type):
            if getattr(message, "original_message_type", original_message_type) != original_message_type:
                continue
            if hasattr(message, "can_proceed") and not message.can_proceed:
                raise ProtocolError(f"{description} failed: {message}")
            return message
        if isinstance(message, GenericStatus) and message.original_message_type == original_message_type:
            if not message.can_proceed:
                raise ProtocolError(f"{description} failed: {message.status.name}")
            if expected_type is not GenericStatus:
                raise ProtocolError(f"{description} returned a generic ACK, not {expected_type.__name__}")
            return message


async def _query_installed_apps(args) -> int:
    try:
        from bleak import BleakClient, BleakScanner
    except ImportError as exc:
        raise RuntimeError("Install dependencies first: python -m pip install -r requirements.txt") from exc

    device = _device_from_address(args.address) if args.address else await _resolve_by_name(BleakScanner, args.name, args.scan_seconds)
    client_kwargs = _client_kwargs(args)
    async with BleakClient(device, **client_kwargs) as client:
        if not client.is_connected:
            raise RuntimeError("BLE connection failed")
        transport = await create_ble_transport(client, force=args.transport, max_write_size=args.max_write_size)
        packet_logger = None
        if args.packet_log:
            transport = PacketLoggingTransport(transport, args.packet_log, max_payload_bytes=args.packet_log_bytes)
            packet_logger = transport
            print(f"Writing packet log to {args.packet_log}")
        try:
            return await _query_and_report_installed_apps(transport, args, upload_completed=False, show_apps=True)
        finally:
            if packet_logger is not None:
                packet_logger.close()


async def _query_and_report_installed_apps(transport, args, *, upload_completed: bool, show_apps: bool) -> int:
    check = await _query_installed_apps_on_transport(transport, args, upload_completed=upload_completed, show_apps=show_apps)
    return 1 if check.query_failed else 0


async def _query_installed_apps_on_transport(
    transport: GarminTransport,
    args,
    *,
    upload_completed: bool,
    show_apps: bool,
) -> InstalledAppsCheck:
    try:
        result = await GarminProtobufClient(transport, timeout=args.timeout).query_installed_apps()
    except Exception as exc:
        print("Unable to query installed apps")
        print(f"Installed-apps query error: {exc}")
        return InstalledAppsCheck(registered=None, query_failed=True)

    space = result.available_space if result.available_space is not None else "unknown"
    slots = result.available_slots if result.available_slots is not None else "unknown"
    print(f"Installed apps query succeeded: {len(result.apps)} apps, available_space={space}, available_slots={slots}")
    if show_apps:
        for app in sorted(result.apps, key=lambda item: (item.name.casefold(), item.app_type or -1)):
            print(format_installed_app(app))

    match = result.find(app_id=args.verify_app_id, app_name=args.verify_app_name)
    if upload_completed:
        if match is not None:
            print("Transfer succeeded and app is registered")
        else:
            print("Transfer succeeded but app is not registered")
    else:
        label = args.verify_app_name or args.verify_app_id or "Requested app"
        if match is not None:
            print(f"{label} is registered")
        else:
            print(f"{label} is not registered")
    return InstalledAppsCheck(registered=match is not None)


async def _query_installed_apps_after_reconnect(
    args,
    *,
    upload_completed: bool,
    show_apps: bool,
    packet_log: Path | None,
) -> InstalledAppsCheck:
    try:
        from bleak import BleakClient, BleakScanner
    except ImportError as exc:
        raise RuntimeError("Install dependencies first: python -m pip install -r requirements.txt") from exc

    device = _device_from_address(args.address) if args.address else await _resolve_by_name(BleakScanner, args.name, args.scan_seconds)
    client_kwargs = _client_kwargs(args)
    async with BleakClient(device, **client_kwargs) as client:
        if not client.is_connected:
            raise RuntimeError("BLE connection failed")
        transport = await create_ble_transport(client, force=args.transport, max_write_size=args.max_write_size)
        packet_logger = None
        if packet_log:
            transport = PacketLoggingTransport(transport, packet_log, max_payload_bytes=args.packet_log_bytes, append=True)
            packet_logger = transport
            print(f"Appending verification packets to {packet_log}")
        try:
            return await _query_installed_apps_on_transport(
                transport,
                args,
                upload_completed=upload_completed,
                show_apps=show_apps,
            )
        finally:
            if packet_logger is not None:
                packet_logger.close()


async def _query_supported_file_types(args) -> int:
    try:
        from bleak import BleakClient, BleakScanner
    except ImportError as exc:
        raise RuntimeError("Install dependencies first: python -m pip install -r requirements.txt") from exc

    device = _device_from_address(args.address) if args.address else await _resolve_by_name(BleakScanner, args.name, args.scan_seconds)
    client_kwargs = _client_kwargs(args)
    async with BleakClient(device, **client_kwargs) as client:
        if not client.is_connected:
            raise RuntimeError("BLE connection failed")
        transport = await create_ble_transport(client, force=args.transport, max_write_size=args.max_write_size)
        packet_logger = None
        if args.packet_log:
            transport = PacketLoggingTransport(transport, args.packet_log, max_payload_bytes=args.packet_log_bytes)
            packet_logger = transport
            print(f"Writing packet log to {args.packet_log}")
        try:
            await _query_supported_file_types_on_transport(transport, args)
            return 0
        finally:
            if packet_logger is not None:
                packet_logger.close()


async def _query_supported_file_types_on_transport(
    transport: GarminTransport,
    args,
) -> SupportedFileTypesStatus:
    response = await _send_and_wait_status(
        transport,
        build_supported_file_types_request(),
        SupportedFileTypesStatus,
        GarminMessage.SUPPORTED_FILE_TYPES_REQUEST,
        "SUPPORTED_FILE_TYPES_REQUEST",
        timeout=args.timeout,
    )
    if not isinstance(response, SupportedFileTypesStatus):
        raise ProtocolError(f"Unexpected supported-file-types response: {response}")

    print(f"Supported file types query succeeded: {len(response.file_types)} file types")
    for file_type in sorted(response.file_types, key=lambda item: (item.data_type, item.subtype, item.name.casefold())):
        marker = " [PRG 255/17]" if file_type.is_prg else ""
        name = file_type.name or "(unnamed)"
        print(f"  {file_type.data_type}/{file_type.subtype} {name}{marker}")
    print(f"PRG 255/17 advertised: {'yes' if any(item.is_prg for item in response.file_types) else 'no'}")
    return response


async def _protobuf_listen(args) -> int:
    try:
        from bleak import BleakClient, BleakScanner
    except ImportError as exc:
        raise RuntimeError("Install dependencies first: python -m pip install -r requirements.txt") from exc

    device = _device_from_address(args.address) if args.address else await _resolve_by_name(BleakScanner, args.name, args.scan_seconds)
    client_kwargs = _client_kwargs(args)
    fragments: dict[tuple[int, int], bytearray] = {}
    totals: dict[tuple[int, int], int] = {}
    packet_count = 0
    protobuf_count = 0
    complete_count = 0

    async with BleakClient(device, **client_kwargs) as client:
        if not client.is_connected:
            raise RuntimeError("BLE connection failed")
        transport = await create_ble_transport(client, force=args.transport, max_write_size=args.max_write_size)
        packet_logger = None
        if args.packet_log:
            transport = PacketLoggingTransport(transport, args.packet_log, max_payload_bytes=args.packet_log_bytes)
            packet_logger = transport
            print(f"Writing packet log to {args.packet_log}")

        try:
            print(f"Connected. Listening for Garmin Smart protobuf traffic for {args.listen_seconds:g}s.")
            if args.listen_phone_events:
                await transport.send_gfdi(build_system_event(SystemEvent.HOST_DID_ENTER_FOREGROUND, 0))
                await transport.send_gfdi(build_sync_ready())
                print("Sent safe phone-presence events: HOST_DID_ENTER_FOREGROUND, SYNC_READY.")
            if args.listen_setup_events:
                await transport.send_gfdi(build_system_event(SystemEvent.PAIR_COMPLETE, 0))
                await transport.send_gfdi(build_system_event(SystemEvent.SETUP_WIZARD_COMPLETE, 0))
                print("Sent setup-complete events: PAIR_COMPLETE, SETUP_WIZARD_COMPLETE.")

            loop = asyncio.get_running_loop()
            deadline = loop.time() + max(0.0, args.listen_seconds)
            while loop.time() < deadline:
                timeout = max(0.1, min(args.timeout, deadline - loop.time()))
                try:
                    packet = await transport.receive_gfdi(timeout=timeout)
                except asyncio.TimeoutError:
                    continue
                if not packet:
                    continue

                packet_count += 1
                try:
                    message = parse_gfdi(packet)
                except ProtocolError as exc:
                    print(f"RX undecodable GFDI packet ({len(packet)} bytes): {exc}")
                    continue

                if isinstance(message, ProtobufStatus):
                    print(
                        "RX ProtobufStatus "
                        f"for={_garmin_message_name(message.original_message_type)} "
                        f"request_id={message.request_id} offset={message.data_offset} "
                        f"status={_enum_name(message.status)} "
                        f"chunk={_enum_name(message.chunk_status)} code={_enum_name(message.status_code)}"
                    )
                    continue

                if isinstance(message, GenericStatus):
                    print(
                        "RX GenericStatus "
                        f"for={_garmin_message_name(message.original_message_type)} "
                        f"status={_enum_name(message.status)}"
                    )
                    continue

                if not hasattr(message, "message_type"):
                    print(f"RX {type(message).__name__}")
                    continue

                if not isinstance(message, ProtobufPacket):
                    raw = getattr(message, "raw", b"")
                    raw_text = f" raw={raw[:32].hex(' ')}" if raw else ""
                    print(f"RX {_garmin_message_name(message.message_type)} ({len(packet)} bytes){raw_text}")
                    if isinstance(message, ParsedMessage):
                        await transport.send_gfdi(build_generic_status(message.message_type))
                    continue

                protobuf_count += 1
                print(
                    "RX "
                    f"{_garmin_message_name(message.message_type)} "
                    f"request_id={message.request_id} "
                    f"chunk={message.data_offset}-{message.end_offset}/{message.total_length}"
                )
                await transport.send_gfdi(_ack_for_incoming_protobuf(message))

                smart_payload = _add_listen_fragment(message, fragments, totals)
                if smart_payload is None:
                    continue

                complete_count += 1
                print(f"Smart protobuf complete ({len(smart_payload)} bytes):")
                for line in describe_smart_payload(smart_payload):
                    print(f"  {line}")

                http_requests = find_http_raw_requests(smart_payload)
                if http_requests and args.listen_http_unknown and message.message_type == GarminMessage.PROTOBUF_REQUEST:
                    await transport.send_gfdi(
                        build_protobuf_packet(
                            GarminMessage.PROTOBUF_RESPONSE,
                            message.request_id,
                            build_http_unknown_status_response(),
                        )
                    )
                    print(f"Sent HTTP UNKNOWN_STATUS protobuf response for request_id={message.request_id}.")
        finally:
            if packet_logger is not None:
                packet_logger.close()

    print(
        "Protobuf listen complete: "
        f"{packet_count} GFDI packets, {protobuf_count} protobuf packets, {complete_count} complete Smart messages."
    )
    return 0


def _ack_for_incoming_protobuf(packet) -> bytes:
    if packet.is_single_packet:
        return build_generic_status(packet.message_type)
    return build_protobuf_status(packet.message_type, packet.request_id, packet.data_offset)


def _add_listen_fragment(
    packet,
    fragments: dict[tuple[int, int], bytearray],
    totals: dict[tuple[int, int], int],
) -> bytes | None:
    if packet.is_single_packet:
        return packet.data

    key = (int(packet.message_type), int(packet.request_id))
    if packet.data_offset == 0:
        fragments[key] = bytearray()
        totals[key] = packet.total_length

    buffer = fragments.setdefault(key, bytearray())
    expected_offset = len(buffer)
    if packet.data_offset != expected_offset:
        print(
            "  Fragment offset mismatch; "
            f"got {packet.data_offset}, expected {expected_offset}. Dropping partial protobuf request."
        )
        fragments.pop(key, None)
        totals.pop(key, None)
        return None

    buffer.extend(packet.data)
    total = totals.get(key, packet.total_length)
    if len(buffer) < total:
        return None

    payload = bytes(buffer[:total])
    fragments.pop(key, None)
    totals.pop(key, None)
    return payload


def _garmin_message_name(value: int) -> str:
    try:
        return GarminMessage(value).name
    except ValueError:
        return str(value)


def _enum_name(value) -> str:
    return getattr(value, "name", str(value))


async def _run_index_ladder(args, data: bytes) -> int:
    print(f"Index ladder PRG: {args.file}")
    print("Preflight: query installed apps.")
    try:
        preflight = await _query_installed_apps_after_reconnect(
            args,
            upload_completed=False,
            show_apps=args.show_installed_apps,
            packet_log=None,
        )
        if preflight.registered is True:
            print("Index ladder stopped: Garmon is already registered.")
            return 0
    except Exception as exc:
        print(f"Preflight installed-apps query failed: {exc}")

    print("Preflight: query supported file types.")
    try:
        await _query_supported_file_types(args)
    except Exception as exc:
        print(f"Preflight supported-file-types query failed: {exc}")

    results: list[TriggerResult] = []
    for trigger in INDEX_LADDER_TRIGGERS:
        log_path = _ladder_log_path(trigger)
        print("")
        print(f"=== Index ladder trigger: {trigger} ===")
        try:
            result = await _upload_with_trigger_once(
                args,
                data,
                trigger,
                packet_log=log_path,
                verify=True,
            )
        except Exception as exc:
            detail = str(exc)
            message = f"{type(exc).__name__}: {detail}" if detail else type(exc).__name__
            print(f"Index ladder trigger failed: {trigger}: {message}")
            results.append(TriggerResult(trigger=trigger, registered=None, trigger_failed=message))
            continue

        results.append(result)
        if result.registered is True:
            print(f"Index ladder stopped: {trigger} registered Garmon.")
            return 0
        if result.query_failed:
            print(f"Index ladder trigger {trigger}: unable to query installed apps after upload.")
        else:
            print(f"Index ladder trigger {trigger}: Garmon is not registered.")

    print("")
    print("Index ladder completed: Garmon was not registered by any safe trigger.")
    failed = [item for item in results if item.trigger_failed is not None]
    if failed:
        print("Trigger failures:")
        for item in failed:
            print(f"  {item.trigger}: {item.trigger_failed}")
    print("Conclusion: the missing mechanism is not a simple GFDI index trigger in this ladder.")
    return 0


def _safe_garmon_ladder_file(path: Path | None) -> Path:
    target = DEFAULT_GARMON_PRG if path is None else path
    if not target.exists():
        raise ProtocolError(f"Garmon install-test PRG was not found: {target}")
    try:
        target_resolved = target.resolve(strict=True)
        garmon_resolved = DEFAULT_GARMON_PRG.resolve(strict=True)
    except OSError as exc:
        raise ProtocolError(f"Could not resolve Garmon install-test PRG: {exc}") from exc
    if target_resolved != garmon_resolved:
        raise ProtocolError(
            "The index ladder is restricted to GarmonInstallTest_fenix6pro_43KB.prg. "
            f"Requested file was: {target}"
        )
    return target


def _ladder_log_path(trigger: str) -> Path:
    logs = DEFAULT_GARMON_PRG.parents[1] / "logs"
    logs.mkdir(parents=True, exist_ok=True)
    return logs / f"index-ladder-{trigger}.jsonl"


async def _scan(scan_seconds: float) -> int:
    try:
        from bleak import BleakScanner
    except ImportError as exc:
        raise RuntimeError("Install dependencies first: python -m pip install -r requirements.txt") from exc

    print("Scanning for BLE devices...")
    discovered = await BleakScanner.discover(timeout=scan_seconds, return_adv=True)
    if not discovered:
        print("No BLE devices found.")
        return 0
    rows = []
    for _key, value in discovered.items():
        device, adv = value
        rows.append((device, adv))
    for device, adv in sorted(rows, key=lambda item: (((item[0].name or "").lower()), item[0].address)):
        name = device.name or "(no name)"
        rssi = getattr(adv, "rssi", None)
        service_uuids = ", ".join(getattr(adv, "service_uuids", []) or [])
        rssi_text = f" rssi={rssi}" if rssi is not None else ""
        service_text = f" services=[{service_uuids}]" if service_uuids else ""
        print(f"{name}  {device.address}{rssi_text}{service_text}")
    return 0


async def _probe(args) -> int:
    try:
        from bleak import BleakClient, BleakScanner
    except ImportError as exc:
        raise RuntimeError("Install dependencies first: python -m pip install -r requirements.txt") from exc

    device = _device_from_address(args.address) if args.address else await _resolve_by_name(BleakScanner, args.name, args.scan_seconds)
    client_kwargs = _client_kwargs(args)
    async with BleakClient(device, **client_kwargs) as client:
        if not client.is_connected:
            raise RuntimeError("BLE connection failed")
        print("Connected.")
        print("Services:")
        for service in client.services:
            print(f"  {service.uuid}  {service.description}")
            for char in service.characteristics:
                props = ",".join(char.properties)
                print(f"    {char.uuid}  [{props}]")

        info = inspect_garmin_support(client.services)
        if info.v2_pair is not None:
            print(f"Garmin v2 GFDI pair: receive={info.v2_pair.receive_uuid} send={info.v2_pair.send_uuid}")
        if info.v1_pair is not None:
            print(f"Garmin v1/v0 GFDI pair: receive={info.v1_pair.receive_uuid} send={info.v1_pair.send_uuid}")
        if not info.has_gfdi:
            print("No Gadgetbridge-known Garmin GFDI characteristic pair found.")
            return 3

        if args.probe_gfdi:
            transport = await create_ble_transport(client, force=args.transport, max_write_size=args.max_write_size)
            handle = getattr(transport, "gfdi_handle", None)
            if handle is not None:
                print(f"GFDI registration succeeded; handle={handle}.")
            else:
                print("GFDI transport initialized.")

    return 0


def _device_from_address(address: str):
    from bleak import BLEDevice

    cleaned = address.replace("-", "").replace(":", "").upper()
    if len(cleaned) == 12 and all(c in "0123456789ABCDEF" for c in cleaned):
        display = ":".join(cleaned[i : i + 2] for i in range(0, 12, 2))
        return BLEDevice(display, "Windows paired BLE device", None)
    return address


def _client_kwargs(args) -> dict:
    kwargs = {"timeout": args.connect_timeout}
    winrt = {}
    if args.address_type:
        winrt["address_type"] = args.address_type
    if args.winrt_services != "auto":
        winrt["use_cached_services"] = args.winrt_services == "cached"
    if winrt:
        kwargs["winrt"] = winrt
    return kwargs


def _progress_printer(step_percent: int):
    last_percent = -1

    def report(progress: UploadProgress) -> None:
        nonlocal last_percent
        percent = progress.percent
        should_print = (
            step_percent <= 0
            or last_percent < 0
            or percent >= last_percent + step_percent
            or progress.offset >= progress.total
        )
        if should_print:
            print(f"Uploaded {progress.offset}/{progress.total} bytes ({percent}%)", flush=True)
            last_percent = percent

    return report


async def _resolve_by_name(BleakScanner, name: str, scan_seconds: float):
    print("Scanning for BLE devices...")
    devices = await BleakScanner.discover(timeout=scan_seconds)
    wanted = name.lower()
    matches = [d for d in devices if d.name and wanted in d.name.lower()]
    if not matches:
        found = ", ".join(sorted(d.name for d in devices if d.name)) or "no named devices"
        raise RuntimeError(f"No BLE device name containing {name!r}. Found: {found}")
    if len(matches) > 1:
        names = ", ".join(f"{d.name} ({d.address})" for d in matches)
        raise RuntimeError(f"Multiple matching devices; use --address. Matches: {names}")
    return matches[0]
