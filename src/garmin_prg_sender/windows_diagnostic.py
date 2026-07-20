from __future__ import annotations

import asyncio
import sys
import time
from dataclasses import dataclass
from typing import Any


def format_ble_address(value: int) -> str:
    raw = f"{value:012X}"
    return ":".join(raw[i : i + 2] for i in range(0, 12, 2))


def parse_ble_address(value: str) -> int:
    cleaned = value.replace("-", "").replace(":", "").upper()
    if len(cleaned) != 12 or any(c not in "0123456789ABCDEF" for c in cleaned):
        raise ValueError(f"Not a 48-bit BLE address: {value!r}")
    return int(cleaned, 16)


@dataclass(frozen=True)
class LiveGattCheck:
    reachable: bool
    name: str | None
    paired: bool | None
    connection_status: str | None
    session_active: bool
    service_status: str
    service_count: int
    error: str | None = None


async def run_winrt_diagnostic(address: str, address_type: str | None, timeout: float) -> int:
    if sys.platform != "win32":
        print("WinRT diagnostics are only available on Windows.")
        return 2

    try:
        from bleak.backends.winrt.client import FutureLike
        from winrt.windows.devices.bluetooth import (
            BluetoothAddressType,
            BluetoothCacheMode,
            BluetoothLEDevice,
        )
        from winrt.windows.devices.bluetooth.genericattributeprofile import (
            GattCommunicationStatus,
            GattSession,
            GattSessionStatus,
        )
    except ImportError as exc:
        raise RuntimeError("Install dependencies first: python -m pip install -r requirements.txt") from exc

    bluetooth_address = parse_ble_address(address)
    print(f"WinRT diagnostic for {format_ble_address(bluetooth_address)}")

    device = await _open_device(BluetoothLEDevice, BluetoothAddressType, bluetooth_address, address_type, timeout)

    if device is None:
        print("Windows did not return a BluetoothLEDevice for this address.")
        return 3

    try:
        _print_device(device)
        await _print_services(device, BluetoothCacheMode.CACHED, "Cached GATT services", timeout)
        await _maintain_session(device, GattSession, GattSessionStatus, timeout)
        live_ok = await _print_services(device, BluetoothCacheMode.UNCACHED, "Live GATT services", timeout)
        return 0 if live_ok else 4
    finally:
        close = getattr(device, "close", None)
        if callable(close):
            close()


async def wait_for_live_gatt(
    address: str,
    address_type: str | None,
    wait_seconds: float,
    retry_seconds: float,
    connect_timeout: float,
) -> int:
    deadline = time.monotonic() + wait_seconds
    attempt = 1
    while True:
        check = await check_live_gatt(address, address_type, connect_timeout)
        details = [
            f"name={check.name or 'unknown'}",
            f"paired={_format_optional_bool(check.paired)}",
            f"windows={check.connection_status or 'unknown'}",
            f"session={'active' if check.session_active else 'closed'}",
            f"live_gatt={check.service_status}",
            f"services={check.service_count}",
        ]
        if check.error:
            details.append(f"error={check.error}")
        print(f"Attempt {attempt}: " + " ".join(details))
        if check.reachable:
            print("Live Garmin GATT services are reachable.")
            return 0
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            print("Timed out waiting for live Garmin GATT services.")
            return 4
        await asyncio.sleep(min(retry_seconds, remaining))
        attempt += 1


async def list_windows_ble_devices(name_filter: str | None = None, timeout: float = 5.0) -> int:
    if sys.platform != "win32":
        print("Windows BLE listing is only available on Windows.")
        return 2

    try:
        from bleak.backends.winrt.client import FutureLike
        from winrt.windows.devices.bluetooth import BluetoothLEDevice
        from winrt.windows.devices.enumeration import DeviceInformation
    except ImportError as exc:
        raise RuntimeError("Install dependencies first: python -m pip install -r requirements.txt") from exc

    selector = BluetoothLEDevice.get_device_selector()
    devices = await FutureLike(DeviceInformation.find_all_async_aqs_filter(selector))
    wanted = name_filter.lower() if name_filter else None
    rows = []
    for info in devices:
        name = str(_safe_attr(info, "name") or "")
        if wanted and wanted not in name.lower():
            continue
        rows.append((name, str(_safe_attr(info, "id") or ""), info))

    if not rows:
        print("No cached Windows BLE devices matched.")
        return 0

    print("Cached Windows BLE devices:")
    for name, device_id, info in sorted(rows, key=lambda item: ((item[0] or "").lower(), item[1].lower())):
        address = address_from_device_id(device_id) or "(unknown address)"
        listed_paired = _format_optional_bool(_safe_bool(_safe_attr(_safe_attr(info, "pairing"), "is_paired")))
        line = f"  {name or '(no name)'}  address={address}  listed_paired={listed_paired}"
        try:
            device = await asyncio.wait_for(BluetoothLEDevice.from_id_async(device_id), timeout=timeout)
        except Exception as exc:
            print(line + f"  open={_describe_exception(exc)}")
            continue
        if device is None:
            print(line + "  open=device-not-found")
            continue
        try:
            connection_status = _enum_name(_safe_attr(device, "connection_status"))
            address_type = _enum_name(_safe_attr(device, "bluetooth_address_type"))
            device_pairing = _safe_attr(_safe_attr(device, "device_information"), "pairing")
            device_paired = _format_optional_bool(_safe_bool(_safe_attr(device_pairing, "is_paired")))
            print(line + f"  device_paired={device_paired}  status={connection_status}  type={address_type}")
        finally:
            close = getattr(device, "close", None)
            if callable(close):
                close()
    return 0


async def pair_windows_ble_device(
    address: str | None,
    name_filter: str | None,
    address_type: str | None = None,
    *,
    timeout: float = 45.0,
    scan_seconds: float = 12.0,
) -> int:
    if sys.platform != "win32":
        print("Windows BLE pairing is only available on Windows.")
        return 2
    if not address and not name_filter:
        print("Provide --address or --name to choose a BLE device for pairing.")
        return 2

    try:
        from bleak import BleakScanner
        from bleak.backends.winrt.client import FutureLike
        from winrt.windows.devices.bluetooth import BluetoothAddressType, BluetoothLEDevice
    except ImportError as exc:
        raise RuntimeError("Install dependencies first: python -m pip install -r requirements.txt") from exc

    target_address = format_ble_address(parse_ble_address(address)) if address else None
    target_name = None
    if target_address is None:
        resolved = await _resolve_visible_ble_device_by_name(BleakScanner, name_filter or "", scan_seconds)
        if resolved is None:
            return 3
        target_address, target_name = resolved

    print(f"Opening BLE device {target_address} for Windows pairing...")
    device = await _open_device(BluetoothLEDevice, BluetoothAddressType, parse_ble_address(target_address), address_type, timeout)
    if device is None:
        print("Windows did not open this BLE device. Put the watch in pairing mode and scan again.")
        return 4

    try:
        device_name = str(_safe_attr(device, "name") or target_name or "")
        info = _safe_attr(device, "device_information")
        pairing = _safe_attr(info, "pairing") if info is not None else None
        if pairing is None:
            print(f"Windows did not expose pairing information for {device_name or '(no name)'}  address={target_address}.")
            return 5

        is_paired = bool(_safe_attr(pairing, "is_paired"))
        can_pair = bool(_safe_attr(pairing, "can_pair"))
        print(
            "Matched BLE device: "
            f"{device_name or '(no name)'}  address={target_address}  "
            f"paired={_format_optional_bool(is_paired)}  can_pair={_format_optional_bool(can_pair)}"
        )
        if is_paired:
            print("Pair result: already paired.")
            return 0
        if not can_pair:
            print("Windows says this device cannot be paired right now. Put the watch in Pair Phone mode and retry.")
            return 6

        print("Starting Windows BLE pairing. Confirm any Windows or watch prompt if it appears.")
        result = await asyncio.wait_for(FutureLike(pairing.pair_async()), timeout=timeout)
        status = _enum_name(_safe_attr(result, "status"))
        protection = _enum_name(_safe_attr(result, "protection_level_used"))
        print(f"Pair result: status={status} protection={protection}")
        return 0 if status in {"paired", "already_paired"} else 7
    finally:
        close = getattr(device, "close", None)
        if callable(close):
            close()


async def unpair_windows_ble_device(address: str | None, name_filter: str | None, confirm: bool, timeout: float = 10.0) -> int:
    if sys.platform != "win32":
        print("Windows BLE unpair is only available on Windows.")
        return 2
    if not address and not name_filter:
        print("Provide --address or --name to choose a cached Windows BLE device.")
        return 2

    try:
        from bleak.backends.winrt.client import FutureLike
        from winrt.windows.devices.bluetooth import BluetoothLEDevice
        from winrt.windows.devices.enumeration import DeviceInformation
    except ImportError as exc:
        raise RuntimeError("Install dependencies first: python -m pip install -r requirements.txt") from exc

    matches = await _find_cached_ble_infos(FutureLike, BluetoothLEDevice, DeviceInformation, address=address, name_filter=name_filter)
    if not matches:
        print("No cached Windows BLE device matched.")
        return 3
    if len(matches) > 1:
        print("Multiple cached Windows BLE devices matched; use --address.")
        for info in matches:
            print(f"  {info.name or '(no name)'}  address={address_from_device_id(info.id) or '(unknown address)'}")
        return 4

    info = matches[0]
    found_address = address_from_device_id(info.id) or "(unknown address)"
    print(f"Matched Windows BLE device: {info.name or '(no name)'}  address={found_address}")
    if not confirm:
        print("Dry run only. Re-run with --confirm-unpair to remove this Windows pairing/cache entry.")
        return 0

    device = await asyncio.wait_for(BluetoothLEDevice.from_id_async(info.id), timeout=timeout)
    if device is None:
        print("Windows did not open the cached device for unpairing.")
        return 5
    try:
        result = await device.device_information.pairing.unpair_async()
        status = _enum_name(result.status)
        print(f"Unpair result: {status}")
        return 0 if status in {"unpaired", "already_unpaired"} else 6
    finally:
        close = getattr(device, "close", None)
        if callable(close):
            close()


def address_from_device_id(device_id: str) -> str | None:
    tail = device_id.rsplit("-", 1)[-1]
    cleaned = tail.replace(":", "").upper()
    if len(cleaned) != 12 or any(c not in "0123456789ABCDEF" for c in cleaned):
        return None
    return format_ble_address(int(cleaned, 16))


async def _find_cached_ble_infos(FutureLike: Any, BluetoothLEDevice: Any, DeviceInformation: Any, *, address: str | None, name_filter: str | None) -> list[Any]:
    selector = BluetoothLEDevice.get_device_selector()
    devices = await FutureLike(DeviceInformation.find_all_async_aqs_filter(selector))
    wanted_address = None
    if address:
        wanted_address = format_ble_address(parse_ble_address(address))
    wanted_name = name_filter.lower() if name_filter else None
    matches = []
    for info in devices:
        info_address = address_from_device_id(str(_safe_attr(info, "id") or ""))
        info_name = str(_safe_attr(info, "name") or "")
        if wanted_address and info_address != wanted_address:
            continue
        if wanted_name and wanted_name not in info_name.lower():
            continue
        matches.append(info)
    return matches


async def _resolve_visible_ble_device_by_name(BleakScanner: Any, name_filter: str, scan_seconds: float) -> tuple[str, str] | None:
    wanted = name_filter.lower()
    print(f"Scanning for BLE devices matching name {name_filter!r}...")
    discovered = await BleakScanner.discover(timeout=scan_seconds, return_adv=True)
    matches: list[tuple[str, str, int | None]] = []
    for _key, value in discovered.items():
        device, adv = value
        name = device.name or "(no name)"
        if wanted and wanted not in name.lower():
            continue
        matches.append((device.address, name, getattr(adv, "rssi", None)))

    if not matches:
        print("No visible BLE device matched. Put the watch in Pair Phone mode and retry.")
        return None
    if len(matches) > 1:
        print("Multiple visible BLE devices matched; use --address.")
        for match_address, match_name, rssi in sorted(matches, key=lambda item: (item[1].lower(), item[0])):
            rssi_text = f" rssi={rssi}" if rssi is not None else ""
            print(f"  {match_name}  address={match_address}{rssi_text}")
        return None

    match_address, match_name, rssi = matches[0]
    rssi_text = f" rssi={rssi}" if rssi is not None else ""
    print(f"Found visible BLE device: {match_name}  address={match_address}{rssi_text}")
    return format_ble_address(parse_ble_address(match_address)), match_name


async def check_live_gatt(address: str, address_type: str | None, timeout: float) -> LiveGattCheck:
    if sys.platform != "win32":
        return LiveGattCheck(False, None, None, None, False, "unsupported-platform", 0)

    try:
        from bleak.backends.winrt.client import FutureLike
        from winrt.windows.devices.bluetooth import (
            BluetoothAddressType,
            BluetoothCacheMode,
            BluetoothLEDevice,
        )
        from winrt.windows.devices.bluetooth.genericattributeprofile import (
            GattCommunicationStatus,
            GattSession,
            GattSessionStatus,
        )
    except ImportError as exc:
        return LiveGattCheck(False, None, None, None, False, "missing-dependencies", 0, str(exc))

    try:
        bluetooth_address = parse_ble_address(address)
        device = await _open_device(BluetoothLEDevice, BluetoothAddressType, bluetooth_address, address_type, timeout)
    except Exception as exc:
        return LiveGattCheck(False, None, None, None, False, "open-device-failed", 0, str(exc))

    if device is None:
        return LiveGattCheck(False, None, None, None, False, "device-not-found", 0)

    session = None
    token = None
    name = None
    paired = None
    connection_status = None
    try:
        name = _safe_attr(device, "name")
        connection_status = _enum_name(_safe_attr(device, "connection_status"))
        info = _safe_attr(device, "device_information")
        pairing = _safe_attr(info, "pairing") if info is not None else None
        if pairing is not None:
            paired_value = _safe_attr(pairing, "is_paired")
            paired = bool(paired_value) if paired_value is not None else None

        session = await asyncio.wait_for(GattSession.from_device_id_async(device.bluetooth_device_id), timeout=timeout)
        active = asyncio.Event()
        loop = asyncio.get_running_loop()

        def on_status_changed(sender: Any, args: Any) -> None:
            if args.status == GattSessionStatus.ACTIVE:
                loop.call_soon_threadsafe(active.set)

        token = session.add_session_status_changed(on_status_changed)
        if session.session_status == GattSessionStatus.ACTIVE:
            active.set()
        session.maintain_connection = True
        try:
            await asyncio.wait_for(active.wait(), timeout=timeout)
        except asyncio.TimeoutError:
            pass
        session_active = session.session_status == GattSessionStatus.ACTIVE

        result = await asyncio.wait_for(
            FutureLike(device.get_gatt_services_with_cache_mode_async(BluetoothCacheMode.UNCACHED)),
            timeout=timeout,
        )
        service_status = _enum_name(result.status)
        services = list(getattr(result, "services", []) or []) if result.status == GattCommunicationStatus.SUCCESS else []
        return LiveGattCheck(
            reachable=result.status == GattCommunicationStatus.SUCCESS,
            name=str(name) if name else None,
            paired=paired,
            connection_status=connection_status,
            session_active=session_active,
            service_status=service_status,
            service_count=len(services),
        )
    except Exception as exc:
        return LiveGattCheck(
            reachable=False,
            name=str(_safe_attr(device, "name") or "") or None,
            paired=paired,
            connection_status=connection_status or _enum_name(_safe_attr(device, "connection_status")),
            session_active=False,
            service_status="check-failed",
            service_count=0,
            error=_describe_exception(exc),
        )
    finally:
        if session is not None:
            try:
                session.maintain_connection = False
            except Exception:
                pass
            if token is not None:
                try:
                    session.remove_session_status_changed(token)
                except Exception:
                    pass
            close = getattr(session, "close", None)
            if callable(close):
                close()
        close = getattr(device, "close", None)
        if callable(close):
            close()


async def _open_device(BluetoothLEDevice: Any, BluetoothAddressType: Any, bluetooth_address: int, address_type: str | None, timeout: float) -> Any:
    if address_type is None:
        return await asyncio.wait_for(
            BluetoothLEDevice.from_bluetooth_address_async(bluetooth_address),
            timeout=timeout,
        )
    winrt_address_type = BluetoothAddressType.PUBLIC if address_type == "public" else BluetoothAddressType.RANDOM
    return await asyncio.wait_for(
        BluetoothLEDevice.from_bluetooth_address_with_bluetooth_address_type_async(bluetooth_address, winrt_address_type),
        timeout=timeout,
    )


def _print_device(device: Any) -> None:
    print("Device:")
    _print_attr(device, "name", "  Name")
    _print_attr(device, "bluetooth_address", "  Address", formatter=lambda value: format_ble_address(int(value)))
    _print_attr(device, "bluetooth_address_type", "  Address type", formatter=_enum_name)
    _print_attr(device, "connection_status", "  Connection status", formatter=_enum_name)
    _print_attr(device, "device_id", "  Device id")

    info = getattr(device, "device_information", None)
    if info is not None:
        print("Device information:")
        _print_attr(info, "name", "  Name")
        _print_attr(info, "id", "  Id")
        pairing = getattr(info, "pairing", None)
        if pairing is not None:
            _print_attr(pairing, "is_paired", "  Is paired")
            _print_attr(pairing, "can_pair", "  Can pair")


async def _maintain_session(device: Any, GattSession: Any, GattSessionStatus: Any, timeout: float) -> None:
    print("GATT session:")
    loop = asyncio.get_running_loop()
    session = await asyncio.wait_for(
        GattSession.from_device_id_async(device.bluetooth_device_id),
        timeout=timeout,
    )
    active = asyncio.Event()

    def on_status_changed(sender: Any, args: Any) -> None:
        print(f"  Status event: status={_enum_name(args.status)} error={_enum_name(args.error)}")
        if args.status == GattSessionStatus.ACTIVE:
            loop.call_soon_threadsafe(active.set)

    token = None
    try:
        _print_attr(session, "can_maintain_connection", "  Can maintain connection")
        _print_attr(session, "session_status", "  Initial status", formatter=_enum_name)
        _print_attr(session, "max_pdu_size", "  Initial max PDU")
        token = session.add_session_status_changed(on_status_changed)
        if session.session_status == GattSessionStatus.ACTIVE:
            active.set()
        session.maintain_connection = True
        try:
            await asyncio.wait_for(active.wait(), timeout=timeout)
            print("  Maintain connection: active")
        except asyncio.TimeoutError:
            print("  Maintain connection: timed out waiting for active session")
        _print_attr(session, "session_status", "  Final status", formatter=_enum_name)
        _print_attr(session, "max_pdu_size", "  Final max PDU")
    finally:
        try:
            session.maintain_connection = False
        except Exception:
            pass
        if token is not None:
            try:
                session.remove_session_status_changed(token)
            except Exception:
                pass
        close = getattr(session, "close", None)
        if callable(close):
            close()


async def _print_services(device: Any, cache_mode: Any, label: str, timeout: float) -> bool:
    from bleak.backends.winrt.client import FutureLike
    from winrt.windows.devices.bluetooth.genericattributeprofile import GattCommunicationStatus

    print(f"{label}:")
    result = await asyncio.wait_for(
        FutureLike(device.get_gatt_services_with_cache_mode_async(cache_mode)),
        timeout=timeout,
    )
    print(f"  Status: {_enum_name(result.status)}")
    protocol_error = getattr(result, "protocol_error", None)
    if protocol_error is not None:
        print(f"  Protocol error: {protocol_error}")
    if result.status != GattCommunicationStatus.SUCCESS:
        return False

    services = list(getattr(result, "services", []) or [])
    if not services:
        print("  No services returned.")
        return True

    for service in services:
        print(f"  Service {service.uuid}")
        await _print_characteristics(service, cache_mode, timeout)
    return True


async def _print_characteristics(service: Any, cache_mode: Any, timeout: float) -> None:
    from bleak.backends.winrt.client import FutureLike
    from winrt.windows.devices.bluetooth.genericattributeprofile import GattCommunicationStatus

    result = await asyncio.wait_for(
        FutureLike(service.get_characteristics_with_cache_mode_async(cache_mode)),
        timeout=timeout,
    )
    if result.status != GattCommunicationStatus.SUCCESS:
        print(f"    Characteristics status: {_enum_name(result.status)}")
        return
    for char in list(getattr(result, "characteristics", []) or []):
        props = _format_properties(getattr(char, "characteristic_properties", None))
        print(f"    Characteristic {char.uuid} [{props}]")


def _format_properties(value: Any) -> str:
    if value is None:
        return ""
    names = []
    for name in (
        "BROADCAST",
        "READ",
        "WRITE_WITHOUT_RESPONSE",
        "WRITE",
        "NOTIFY",
        "INDICATE",
        "AUTHENTICATED_SIGNED_WRITES",
        "EXTENDED_PROPERTIES",
        "RELIABLE_WRITES",
        "WRITABLE_AUXILIARIES",
    ):
        flag = getattr(type(value), name, None)
        if flag is not None and value & flag:
            names.append(name.lower())
    return ",".join(names) or str(value)


def _print_attr(source: Any, attr: str, label: str, formatter: Any | None = None) -> None:
    try:
        value = getattr(source, attr)
    except Exception as exc:
        print(f"{label}: <error: {exc}>")
        return
    if formatter is not None:
        try:
            value = formatter(value)
        except Exception as exc:
            value = f"<format error: {exc}>"
    print(f"{label}: {value}")


def _safe_attr(source: Any, attr: str) -> Any:
    try:
        return getattr(source, attr)
    except Exception:
        return None


def _format_optional_bool(value: bool | None) -> str:
    if value is None:
        return "unknown"
    return "yes" if value else "no"


def _safe_bool(value: Any) -> bool | None:
    if value is None:
        return None
    return bool(value)


def _describe_exception(exc: Exception) -> str:
    message = str(exc)
    if message:
        return f"{type(exc).__name__}: {message}"
    return type(exc).__name__


def _enum_name(value: Any) -> str:
    if value is None:
        return "unknown"
    name = getattr(value, "name", None)
    if name:
        return str(name).lower()
    return str(value)
