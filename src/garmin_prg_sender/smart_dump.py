from __future__ import annotations

from dataclasses import dataclass
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

from .protobuf import _field_message, _field_varint, _iter_fields, parse_installed_apps_response
from .protocol import ProtocolError


SMART_FIELD_NAMES = {
    1: "CALENDAR_EVENTS_SERVICE",
    2: "CONNECT_IQ_HTTP_SERVICE",
    3: "CONNECT_IQ_INSTALLED_APPS_SERVICE",
    4: "CONNECT_IQ_APP_SETTINGS_SERVICE",
    5: "INTERNATIONAL_GOLF_SERVICE",
    6: "SWING_SENSOR_SERVICE",
    7: "DATA_TRANSFER_SERVICE",
    8: "DEVICE_STATUS_SERVICE",
    9: "INCIDENT_DETECTION_SERVICE",
    10: "AUDIO_PROMPTS_SERVICE",
    11: "WIFI_SETUP_SERVICE",
    12: "FIND_MY_WATCH_SERVICE",
    13: "CORE_SERVICE",
    14: "GROUP_LIVE_TRACK_SERVICE",
    15: "EXPRESSPAY_COMMAND_SERVICE",
    16: "SMS_NOTIFICATION_SERVICE",
    17: "LIVE_TRACK_MESSAGING_SERVICE",
    18: "INSTANT_INPUT_SERVICE",
    19: "SPORT_PROFILE_SETUP_SERVICE",
    20: "HSA_DATA_SERVICE",
    21: "LIVE_TRACK_SERVICE",
    22: "EXPLORE_SYNC_SERVICE",
    23: "WAY_POINT_TRANSFER_SERVICE",
    24: "DEVICE_MESSAGE_SERVICE",
    25: "LTE_SERVICE",
    26: "ANTI_THEFT_ALARM_SERVICE",
    27: "CREDENTIALS_SERVICE",
    28: "INREACH_TRACKING_SERVICE",
    29: "INREACH_MESSAGING_SERVICE",
    30: "EVENT_SHARING_SERVICE",
    31: "GENERIC_ITEM_TRANSFER_SERVICE",
    32: "INREACH_CONTACT_SYNC_SERVICE",
    33: "HAND_CALIBRATION_SERVICE",
    42: "SETTINGS_SERVICE",
    49: "NOTIFICATIONS_SERVICE",
}

HTTP_METHODS = {
    0: "UNKNOWN_METHOD",
    1: "GET",
    2: "PUT",
    3: "POST",
    4: "DELETE",
    5: "PATCH",
    6: "HEAD",
}

HTTP_SERVICE_STATUS = {
    0: "UNKNOWN_STATUS",
    100: "OK",
    200: "NETWORK_REQUEST_TIMED_OUT",
    300: "FILE_TOO_LARGE",
    400: "DATA_TRANSFER_ITEM_FAILURE",
}

DATA_TRANSFER_STATUS = {
    0: "UNKNOWN",
    1: "SUCCESS",
    2: "INVALID_ID",
    3: "INVALID_OFFSET",
}

SENSITIVE_QUERY_PARTS = ("auth", "code", "key", "secret", "session", "sig", "signature", "ticket", "token")
SENSITIVE_HEADER_PARTS = ("authorization", "cookie", "key", "secret", "session", "ticket", "token")
REDACTED = "REDACTED"


@dataclass(frozen=True)
class HttpRawRequest:
    url: str
    method: int | None
    headers: tuple[tuple[str, str], ...]
    use_data_xfer: bool | None

    @property
    def method_name(self) -> str:
        if self.method is None:
            return "UNKNOWN"
        return HTTP_METHODS.get(self.method, str(self.method))


def describe_smart_payload(payload: bytes) -> list[str]:
    """Return a compact, token-redacted description of a Garmin Smart protobuf."""
    lines: list[str] = []
    fields = _safe_fields(payload)
    if fields is None:
        return [f"Smart protobuf parse failed ({len(payload)} bytes): {payload[:32].hex(' ')}"]

    if not fields:
        return ["Smart protobuf is empty"]

    for field in fields:
        name = SMART_FIELD_NAMES.get(field.number, "UNKNOWN_SERVICE")
        value_len = len(field.value) if isinstance(field.value, bytes) else None
        suffix = f" {value_len} bytes" if value_len is not None else f" value={field.value}"
        lines.append(f"Smart field {field.number} {name}:{suffix}")

        if not isinstance(field.value, bytes):
            continue
        if field.number == 2:
            lines.extend("  " + item for item in describe_http_service(field.value))
        elif field.number == 3:
            lines.extend("  " + item for item in describe_installed_apps_service(field.value))
        elif field.number == 7:
            lines.extend("  " + item for item in describe_data_transfer_service(field.value))
        elif field.number in (4, 22, 31):
            lines.extend("  " + item for item in describe_generic_message(field.value, max_depth=2))
        else:
            lines.extend("  " + item for item in describe_generic_message(field.value, max_depth=1))

    return lines


def find_http_raw_requests(payload: bytes) -> tuple[HttpRawRequest, ...]:
    requests: list[HttpRawRequest] = []
    fields = _safe_fields(payload)
    if fields is None:
        return ()
    for field in fields:
        if field.number != 2 or field.wire_type != 2 or not isinstance(field.value, bytes):
            continue
        for http_field in _safe_fields(field.value) or ():
            if http_field.number == 5 and http_field.wire_type == 2 and isinstance(http_field.value, bytes):
                requests.append(parse_http_raw_request(http_field.value))
    return tuple(requests)


def build_http_unknown_status_response() -> bytes:
    raw_response = _field_varint(1, 0)
    http_service = _field_message(6, raw_response)
    return _field_message(2, http_service)


def describe_http_service(data: bytes) -> list[str]:
    lines: list[str] = []
    for field in _safe_fields(data) or ():
        if field.number == 5 and field.wire_type == 2 and isinstance(field.value, bytes):
            request = parse_http_raw_request(field.value)
            lines.append(
                "Http.RawRequest "
                f"method={request.method_name} "
                f"useDataXfer={_format_bool(request.use_data_xfer)} "
                f"url={_redact_url(request.url)}"
            )
            for key, value in request.headers[:12]:
                lines.append(f"  header {key}: {_redact_header_value(key, value)}")
            if len(request.headers) > 12:
                lines.append(f"  ... {len(request.headers) - 12} more headers")
        elif field.number == 6 and field.wire_type == 2 and isinstance(field.value, bytes):
            lines.extend(describe_http_raw_response(field.value))
        else:
            lines.append(_format_field("HttpService", field))
    return lines or ["HttpService has no decodable fields"]


def parse_http_raw_request(data: bytes) -> HttpRawRequest:
    url = ""
    method = None
    headers: list[tuple[str, str]] = []
    use_data_xfer = None
    for field in _safe_fields(data) or ():
        if field.number == 1 and field.wire_type == 2 and isinstance(field.value, bytes):
            url = _decode_text(field.value)
        elif field.number == 3 and field.wire_type == 0:
            method = int(field.value)
        elif field.number == 5 and field.wire_type == 2 and isinstance(field.value, bytes):
            header = _parse_header(field.value)
            if header is not None:
                headers.append(header)
        elif field.number == 6 and field.wire_type == 0:
            use_data_xfer = bool(field.value)
    return HttpRawRequest(url=url, method=method, headers=tuple(headers), use_data_xfer=use_data_xfer)


def describe_http_raw_response(data: bytes) -> list[str]:
    status = None
    http_status = None
    body_length = None
    xfer_id = None
    xfer_size = None
    headers: list[tuple[str, str]] = []
    extras: list[str] = []

    for field in _safe_fields(data) or ():
        if field.number == 1 and field.wire_type == 0:
            status = int(field.value)
        elif field.number == 2 and field.wire_type == 0:
            http_status = int(field.value)
        elif field.number == 3 and field.wire_type == 2 and isinstance(field.value, bytes):
            body_length = len(field.value)
        elif field.number == 4 and field.wire_type == 2 and isinstance(field.value, bytes):
            xfer_id, xfer_size = _parse_data_transfer_item(field.value)
        elif field.number == 5 and field.wire_type == 2 and isinstance(field.value, bytes):
            header = _parse_header(field.value)
            if header is not None:
                headers.append(header)
        else:
            extras.append(_format_field("Http.RawResponse", field))

    status_text = "unknown" if status is None else HTTP_SERVICE_STATUS.get(status, str(status))
    parts = [f"Http.RawResponse status={status_text}"]
    if http_status is not None:
        parts.append(f"httpStatus={http_status}")
    if body_length is not None:
        parts.append(f"body={body_length} bytes")
    if xfer_id is not None:
        parts.append(f"xferData id={xfer_id} size={xfer_size}")
    lines = [" ".join(parts)]
    for key, value in headers[:12]:
        lines.append(f"  header {key}: {_redact_header_value(key, value)}")
    if len(headers) > 12:
        lines.append(f"  ... {len(headers) - 12} more headers")
    lines.extend(extras)
    return lines


def describe_data_transfer_service(data: bytes) -> list[str]:
    lines: list[str] = []
    for field in _safe_fields(data) or ():
        if field.number == 1 and field.wire_type == 2 and isinstance(field.value, bytes):
            lines.append(_describe_data_download_request(field.value))
        elif field.number == 2 and field.wire_type == 2 and isinstance(field.value, bytes):
            lines.append(_describe_data_download_response(field.value))
        else:
            lines.append(_format_field("DataTransferService", field))
    return lines or ["DataTransferService has no decodable fields"]


def describe_installed_apps_service(data: bytes) -> list[str]:
    lines: list[str] = []
    for field in _safe_fields(data) or ():
        if field.number == 1 and field.wire_type == 2 and isinstance(field.value, bytes):
            app_type = _first_varint(field.value, 1)
            lines.append(f"InstalledApps.GetInstalledAppsRequest app_type={app_type if app_type is not None else 'unknown'}")
        elif field.number == 2 and field.wire_type == 2 and isinstance(field.value, bytes):
            try:
                result = parse_installed_apps_response(_field_message(3, data))
            except ProtocolError as exc:
                lines.append(f"InstalledApps.GetInstalledAppsResponse parse failed: {exc}")
            else:
                lines.append(
                    "InstalledApps.GetInstalledAppsResponse "
                    f"apps={len(result.apps)} "
                    f"available_space={result.available_space} "
                    f"available_slots={result.available_slots}"
                )
        else:
            lines.append(_format_field("InstalledAppsService", field))
    return lines or ["InstalledAppsService has no decodable fields"]


def describe_generic_message(data: bytes, *, max_depth: int, prefix: str = "field") -> list[str]:
    fields = _safe_fields(data)
    if fields is None:
        return [f"{prefix}: opaque {len(data)} bytes {_format_bytes(data)}"]
    if not fields:
        return [f"{prefix}: empty message"]

    lines: list[str] = []
    for field in fields[:24]:
        lines.append(_format_field(prefix, field))
        if max_depth > 0 and field.wire_type == 2 and isinstance(field.value, bytes):
            nested = _safe_fields(field.value)
            if nested:
                for nested_line in describe_generic_message(field.value, max_depth=max_depth - 1, prefix=f"{prefix}.{field.number}")[:8]:
                    lines.append("  " + nested_line)
    if len(fields) > 24:
        lines.append(f"... {len(fields) - 24} more fields")
    return lines


def _describe_data_download_request(data: bytes) -> str:
    data_id = None
    offset = None
    max_chunk_size = None
    for field in _safe_fields(data) or ():
        if field.number == 1 and field.wire_type == 0:
            data_id = int(field.value)
        elif field.number == 2 and field.wire_type == 0:
            offset = int(field.value)
        elif field.number == 3 and field.wire_type == 0:
            max_chunk_size = int(field.value)
    return f"DataDownloadRequest id={data_id} offset={offset} maxChunkSize={max_chunk_size}"


def _describe_data_download_response(data: bytes) -> str:
    status = None
    data_id = None
    offset = None
    payload_length = None
    for field in _safe_fields(data) or ():
        if field.number == 1 and field.wire_type == 0:
            status = int(field.value)
        elif field.number == 2 and field.wire_type == 0:
            data_id = int(field.value)
        elif field.number == 3 and field.wire_type == 0:
            offset = int(field.value)
        elif field.number == 4 and field.wire_type == 2 and isinstance(field.value, bytes):
            payload_length = len(field.value)
    status_text = "unknown" if status is None else DATA_TRANSFER_STATUS.get(status, str(status))
    return f"DataDownloadResponse status={status_text} id={data_id} offset={offset} payload={payload_length} bytes"


def _parse_data_transfer_item(data: bytes) -> tuple[int | None, int | None]:
    data_id = None
    size = None
    for field in _safe_fields(data) or ():
        if field.number == 1 and field.wire_type == 0:
            data_id = int(field.value)
        elif field.number == 2 and field.wire_type == 0:
            size = int(field.value)
    return data_id, size


def _parse_header(data: bytes) -> tuple[str, str] | None:
    key = None
    value = None
    for field in _safe_fields(data) or ():
        if field.number == 1 and field.wire_type == 2 and isinstance(field.value, bytes):
            key = _decode_text(field.value)
        elif field.number == 2 and field.wire_type == 2 and isinstance(field.value, bytes):
            value = _decode_text(field.value)
    if key is None or value is None:
        return None
    return key, value


def _first_varint(data: bytes, field_number: int) -> int | None:
    for field in _safe_fields(data) or ():
        if field.number == field_number and field.wire_type == 0:
            return int(field.value)
    return None


def _safe_fields(data: bytes):
    try:
        return tuple(_iter_fields(data))
    except ProtocolError:
        return None


def _format_field(prefix: str, field) -> str:
    if isinstance(field.value, bytes):
        return f"{prefix}.{field.number} wire={field.wire_type} len={len(field.value)} {_format_bytes(field.value)}"
    return f"{prefix}.{field.number} wire={field.wire_type} value={field.value}"


def _format_bytes(data: bytes, limit: int = 32) -> str:
    if not data:
        return "bytes=<empty>"
    text = _maybe_text(data)
    if text is not None:
        if len(text) > 80:
            text = text[:77] + "..."
        return f"text={text!r}"
    suffix = "..." if len(data) > limit else ""
    return f"hex={data[:limit].hex(' ')}{suffix}"


def _maybe_text(data: bytes) -> str | None:
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        return None
    if not text:
        return ""
    printable = sum(1 for char in text if char.isprintable() or char in "\r\n\t")
    if printable / len(text) < 0.85:
        return None
    return text.replace("\r", "\\r").replace("\n", "\\n")


def _decode_text(data: bytes) -> str:
    return data.decode("utf-8", errors="replace")


def _redact_url(url: str) -> str:
    if not url:
        return url
    try:
        parts = urlsplit(url)
    except ValueError:
        return url
    query = []
    for key, value in parse_qsl(parts.query, keep_blank_values=True):
        if _contains_sensitive(key):
            query.append((key, REDACTED))
        else:
            query.append((key, value))
    return urlunsplit((parts.scheme, parts.netloc, parts.path, urlencode(query, doseq=True), parts.fragment))


def _redact_header_value(key: str, value: str) -> str:
    if _contains_sensitive(key, header=True):
        return REDACTED
    if len(value) > 160:
        return value[:157] + "..."
    return value


def _contains_sensitive(value: str, *, header: bool = False) -> bool:
    lowered = value.casefold()
    parts = SENSITIVE_HEADER_PARTS if header else SENSITIVE_QUERY_PARTS
    return any(part in lowered for part in parts)


def _format_bool(value: bool | None) -> str:
    if value is None:
        return "unknown"
    return "true" if value else "false"
