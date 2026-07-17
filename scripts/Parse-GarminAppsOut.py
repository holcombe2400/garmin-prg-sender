#!/usr/bin/env python3
import argparse
import json
from pathlib import Path


def read_varint(buf, pos):
    shift = 0
    value = 0
    while pos < len(buf):
        byte = buf[pos]
        pos += 1
        value |= (byte & 0x7F) << shift
        if byte < 0x80:
            return value, pos
        shift += 7
        if shift > 70:
            raise ValueError("varint is too long")
    raise ValueError("unexpected EOF while reading varint")


def read_field(buf, pos):
    offset = pos
    key, pos = read_varint(buf, pos)
    field = key >> 3
    wire_type = key & 7

    if wire_type == 0:
        value, pos = read_varint(buf, pos)
    elif wire_type == 1:
        value = buf[pos:pos + 8]
        pos += 8
    elif wire_type == 2:
        length, pos = read_varint(buf, pos)
        value = buf[pos:pos + length]
        pos += length
    elif wire_type == 5:
        value = buf[pos:pos + 4]
        pos += 4
    else:
        raise ValueError(f"unsupported protobuf wire type {wire_type} at 0x{offset:x}")

    return offset, field, wire_type, value, pos


def text_or_hex(value):
    if not isinstance(value, bytes):
        return value
    try:
        text = value.decode("utf-8").rstrip("\x00")
    except UnicodeDecodeError:
        return value.hex()
    if all(ord(ch) >= 32 or ch in "\r\n\t" for ch in text):
        return text
    return value.hex()


def extract_entries(data):
    # Observed fenix 6 Pro layout:
    # OUT -> field 3 len -> field 2 len -> header fields + repeated field 3 records.
    _, outer_field, outer_wire, outer, pos = read_field(data, 0)
    if outer_field != 3 or outer_wire != 2 or pos != len(data):
        raise ValueError("unexpected OUT wrapper; expected one length-delimited field 3")

    _, inner_field, inner_wire, inner, pos = read_field(outer, 0)
    if inner_field != 2 or inner_wire != 2 or pos != len(outer):
        raise ValueError("unexpected OUT payload; expected one length-delimited field 2")

    header = {}
    records = []
    pos = 0
    while pos < len(inner):
        offset, field, wire_type, value, pos = read_field(inner, pos)
        if field == 3 and wire_type == 2:
            records.append((offset, value))
        else:
            header[str(field)] = text_or_hex(value)
    return header, records


def parse_record(index, offset, record):
    parsed = {
        "index": index,
        "offset": offset,
        "length": len(record),
        "fields": [],
    }
    pos = 0
    while pos < len(record):
        field_offset, field, wire_type, value, pos = read_field(record, pos)
        clean = text_or_hex(value)
        parsed["fields"].append({
            "field": field,
            "wire_type": wire_type,
            "offset": field_offset,
            "value": clean,
        })

        if field == 1 and wire_type == 2 and isinstance(value, bytes) and len(value) == 16:
            parsed["uuid_hex"] = value.hex()
        elif field == 2 and wire_type == 0:
            parsed["entry_type"] = value
        elif field == 3 and wire_type == 2:
            parsed["name"] = clean
        elif field == 4 and wire_type == 0:
            parsed["field4"] = value
        elif field == 5 and wire_type == 0:
            parsed["field5"] = value
        elif field == 6 and wire_type == 2:
            parsed["filename"] = clean
        elif field == 7 and wire_type == 0:
            parsed["size_or_id"] = value
        elif field == 8 and wire_type == 0:
            parsed["field8"] = value
        elif field == 9 and wire_type == 0:
            parsed["field9"] = value

    return parsed


def parse_out(path):
    header, raw_records = extract_entries(path.read_bytes())
    records = [parse_record(i + 1, offset, record) for i, (offset, record) in enumerate(raw_records)]
    return {
        "source": str(path),
        "header": header,
        "record_count": len(records),
        "records": records,
    }


def write_text(summary, path):
    lines = [
        f"Source: {summary['source']}",
        f"Records: {summary['record_count']}",
        "",
        "Records with PRG filenames:",
    ]
    for record in summary["records"]:
        filename = record.get("filename")
        if not filename:
            continue
        name = record.get("name", "")
        uuid_hex = record.get("uuid_hex", "")
        size = record.get("size_or_id", "")
        entry_type = record.get("entry_type", "")
        lines.append(
            f"{record['index']:03d}  {name:<24} {filename:<34} "
            f"size_or_id={size:<10} type={entry_type:<3} uuid={uuid_hex}"
        )
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description="Parse Garmin GARMIN\\Apps\\OUT registry protobuf.")
    parser.add_argument("out_bin", type=Path)
    parser.add_argument("--json", type=Path)
    parser.add_argument("--text", type=Path)
    args = parser.parse_args()

    summary = parse_out(args.out_bin)
    if args.json:
        args.json.write_text(json.dumps(summary, indent=2), encoding="utf-8")
    if args.text:
        write_text(summary, args.text)
    if not args.json and not args.text:
        print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
