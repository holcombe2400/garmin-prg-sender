#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
from typing import Any


IGNORED_FILENAMES = {
    "apps-listing.json",
    "listing.json",
    "snapshot-meta.json",
    "out-apps.json",
    "out-apps.txt",
    "snapshot-diff.json",
    "snapshot-diff.txt",
}

REGISTRY_FIELDS = (
    "uuid_hex",
    "entry_type",
    "name",
    "field4",
    "field5",
    "filename",
    "size_or_id",
    "field8",
    "field9",
)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def file_manifest(snapshot: Path) -> dict[str, dict[str, Any]]:
    files: dict[str, dict[str, Any]] = {}
    for path in sorted(snapshot.rglob("*")):
        if not path.is_file():
            continue
        if path.name in IGNORED_FILENAMES:
            continue
        rel = path.relative_to(snapshot).as_posix()
        files[rel] = {
            "size": path.stat().st_size,
            "sha256": sha256_file(path),
        }
    return files


def load_parser(script_dir: Path):
    parser_path = script_dir / "Parse-GarminAppsOut.py"
    spec = importlib.util.spec_from_file_location("garmin_apps_out_parser", parser_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Could not load parser: {parser_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_registry(snapshot: Path, parser_module) -> dict[str, Any] | None:
    json_path = snapshot / "out-apps.json"
    if json_path.exists():
        return json.loads(json_path.read_text(encoding="utf-8"))
    out_bin = snapshot / "ROOT_FILES" / "OUT.BIN"
    if out_bin.exists():
        return parser_module.parse_out(out_bin)
    return None


def record_key(record: dict[str, Any]) -> str:
    uuid_hex = record.get("uuid_hex")
    if uuid_hex:
        return f"uuid:{str(uuid_hex).lower()}"
    filename = record.get("filename")
    if filename:
        return f"file:{str(filename).lower()}"
    name = record.get("name")
    if name:
        return f"name:{str(name).lower()}#{record.get('index', '')}"
    return f"index:{record.get('index', '')}"


def simplify_record(record: dict[str, Any]) -> dict[str, Any]:
    return {field: record.get(field) for field in REGISTRY_FIELDS if field in record}


def registry_records(summary: dict[str, Any] | None) -> dict[str, dict[str, Any]]:
    if not summary:
        return {}
    out: dict[str, dict[str, Any]] = {}
    for record in summary.get("records", []):
        if isinstance(record, dict):
            out[record_key(record)] = record
    return out


def compare_maps(before: dict[str, Any], after: dict[str, Any]) -> dict[str, Any]:
    before_keys = set(before)
    after_keys = set(after)
    added = sorted(after_keys - before_keys)
    removed = sorted(before_keys - after_keys)
    changed = []
    unchanged = []
    for key in sorted(before_keys & after_keys):
        if before[key] == after[key]:
            unchanged.append(key)
        else:
            changed.append(key)
    return {
        "added": added,
        "removed": removed,
        "changed": changed,
        "unchanged_count": len(unchanged),
    }


def find_targets(records: dict[str, dict[str, Any]], target_filename: str, target_name: str, target_uuid: str) -> list[dict[str, Any]]:
    filename = target_filename.casefold() if target_filename else ""
    name = target_name.casefold() if target_name else ""
    uuid_hex = target_uuid.replace("-", "").casefold() if target_uuid else ""
    matches = []
    for record in records.values():
        if filename and str(record.get("filename", "")).casefold() == filename:
            matches.append(record)
            continue
        if name and str(record.get("name", "")).casefold() == name:
            matches.append(record)
            continue
        if uuid_hex and str(record.get("uuid_hex", "")).casefold() == uuid_hex:
            matches.append(record)
    return matches


def format_record(record: dict[str, Any]) -> str:
    return (
        f"{int(record.get('index', 0)):03d}  "
        f"{record.get('name', '')}  "
        f"file={record.get('filename', '')}  "
        f"size_or_id={record.get('size_or_id', '')}  "
        f"type={record.get('entry_type', '')}  "
        f"uuid={record.get('uuid_hex', '')}"
    )


def build_diff(before: Path, after: Path, parser_module, target_filename: str, target_name: str, target_uuid: str) -> dict[str, Any]:
    before_files = file_manifest(before)
    after_files = file_manifest(after)
    file_diff = compare_maps(before_files, after_files)

    before_registry = registry_records(load_registry(before, parser_module))
    after_registry = registry_records(load_registry(after, parser_module))
    simple_before_registry = {key: simplify_record(value) for key, value in before_registry.items()}
    simple_after_registry = {key: simplify_record(value) for key, value in after_registry.items()}
    registry_diff = compare_maps(simple_before_registry, simple_after_registry)

    return {
        "before": str(before),
        "after": str(after),
        "files": {
            "before_count": len(before_files),
            "after_count": len(after_files),
            "diff": file_diff,
            "before": before_files,
            "after": after_files,
        },
        "registry": {
            "before_count": len(before_registry),
            "after_count": len(after_registry),
            "diff": registry_diff,
            "before": before_registry,
            "after": after_registry,
        },
        "target": {
            "filename": target_filename,
            "name": target_name,
            "uuid": target_uuid,
            "before": find_targets(before_registry, target_filename, target_name, target_uuid),
            "after": find_targets(after_registry, target_filename, target_name, target_uuid),
        },
    }


def write_text(diff: dict[str, Any], path: Path) -> None:
    file_diff = diff["files"]["diff"]
    registry_diff = diff["registry"]["diff"]
    lines = [
        f"Before: {diff['before']}",
        f"After:  {diff['after']}",
        "",
        "Files:",
        f"  before={diff['files']['before_count']} after={diff['files']['after_count']}",
        f"  added={len(file_diff['added'])} removed={len(file_diff['removed'])} changed={len(file_diff['changed'])} unchanged={file_diff['unchanged_count']}",
    ]
    for label in ("added", "removed", "changed"):
        if file_diff[label]:
            lines.append(f"  {label}:")
            for rel in file_diff[label][:60]:
                details = diff["files"]["after"].get(rel) or diff["files"]["before"].get(rel) or {}
                lines.append(f"    {rel} size={details.get('size', '')} sha256={str(details.get('sha256', ''))[:16]}")
            if len(file_diff[label]) > 60:
                lines.append(f"    ... {len(file_diff[label]) - 60} more")

    lines.extend([
        "",
        "Registry:",
        f"  before={diff['registry']['before_count']} after={diff['registry']['after_count']}",
        f"  added={len(registry_diff['added'])} removed={len(registry_diff['removed'])} changed={len(registry_diff['changed'])} unchanged={registry_diff['unchanged_count']}",
    ])
    for label in ("added", "removed", "changed"):
        if registry_diff[label]:
            lines.append(f"  {label}:")
            source = diff["registry"]["after"] if label != "removed" else diff["registry"]["before"]
            for key in registry_diff[label][:80]:
                record = source[key]
                lines.append(f"    {format_record(record)}")
            if len(registry_diff[label]) > 80:
                lines.append(f"    ... {len(registry_diff[label]) - 80} more")

    target = diff["target"]
    if target["filename"] or target["name"] or target["uuid"]:
        lines.extend([
            "",
            "Target:",
            f"  filename={target['filename']} name={target['name']} uuid={target['uuid']}",
            f"  before_matches={len(target['before'])} after_matches={len(target['after'])}",
        ])
        for label in ("before", "after"):
            for record in target[label]:
                lines.append(f"  {label}: {format_record(record)}")

    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Compare two Garmin GARMIN\\Apps MTP snapshots.")
    parser.add_argument("before", type=Path)
    parser.add_argument("after", type=Path)
    parser.add_argument("--target-filename", default="")
    parser.add_argument("--target-name", default="")
    parser.add_argument("--target-uuid", default="")
    parser.add_argument("--json", type=Path)
    parser.add_argument("--text", type=Path)
    args = parser.parse_args()

    script_dir = Path(__file__).resolve().parent
    parser_module = load_parser(script_dir)
    diff = build_diff(
        args.before,
        args.after,
        parser_module,
        args.target_filename,
        args.target_name,
        args.target_uuid,
    )

    if args.json:
        args.json.write_text(json.dumps(diff, indent=2), encoding="utf-8")
    if args.text:
        write_text(diff, args.text)
        print(args.text.read_text(encoding="utf-8"))
    if not args.json and not args.text:
        print(json.dumps(diff, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
