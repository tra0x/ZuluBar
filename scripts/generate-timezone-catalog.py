#!/usr/bin/env python3
"""Generate ZuluBar/TimeZoneCatalog.json (names/search metadata, not tz
rules) from a pinned IANA tzdb release's zone.tab and backward files.

Offline, deterministic, Python 3 stdlib only.

Usage:
    python3 scripts/generate-timezone-catalog.py \
        --source-dir build/timezone-inputs \
        --version 2026e \
        --output ZuluBar/TimeZoneCatalog.json
"""

import argparse
import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional

RECOGNIZED_PREFIXES = {
    "Africa", "America", "Antarctica", "Arctic", "Asia", "Atlantic",
    "Australia", "Europe", "Indian", "Pacific",
}

# 'backward' section headers that mean "this is a renamed/compatibility
# spelling of an existing city, not a new one" vs. "this is a real,
# distinct city that happens to share civil time with its link target".
ALIAS_SECTION_MARKERS = (
    "Pre-1993 naming conventions",
    "Two-part names that were renamed",
    "Alternate names for the same location",
)
GEOGRAPHIC_SECTION_MARKERS = (
    "Non-zone.tab locations with timestamps since 1970 that duplicate",
    "Pre-2013 practice, which typically had a Zone per zone.tab line",
)

LINK_RE = re.compile(r"^Link\s+(\S+)\s+(\S+)")
TARGET1_RE = re.compile(r"#=\s*(\S+)")


@dataclass
class LinkRecord:
    target: str
    linkname: str
    section: str  # "alias" or "geographic"
    target1: Optional[str]


def derive_city(identifier: str) -> str:
    return identifier.rsplit("/", 1)[-1].replace("_", " ")


def parse_zone_tab(path: Path) -> List[tuple]:
    rows = []
    with path.open(encoding="utf-8") as f:
        for line in f:
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            columns = line.rstrip("\n").split("\t")
            if len(columns) < 3:
                continue
            country_code, _coordinates, identifier = columns[0], columns[1], columns[2]
            rows.append((identifier, country_code))
    return rows


def parse_backward(path: Path) -> List[LinkRecord]:
    records = []
    section = "alias"
    with path.open(encoding="utf-8") as f:
        for line in f:
            stripped = line.strip()
            if not stripped:
                continue
            if stripped.startswith("#"):
                text = stripped.lstrip("#").strip()
                if any(text.startswith(marker) for marker in ALIAS_SECTION_MARKERS):
                    section = "alias"
                elif any(text.startswith(marker) for marker in GEOGRAPHIC_SECTION_MARKERS):
                    section = "geographic"
                continue
            if not stripped.startswith("Link"):
                continue  # skip Rule/Zone lines, not geographic names
            match = LINK_RE.match(stripped)
            if not match:
                continue
            target, linkname = match.group(1), match.group(2)
            target1_match = TARGET1_RE.search(stripped)
            target1 = target1_match.group(1) if target1_match else None
            records.append(LinkRecord(target=target, linkname=linkname, section=section, target1=target1))
    return records


def resolve_canonical(start: str, canonical_rows: Dict[str, dict], full_link_map: Dict[str, str],
                       max_depth: int = 30) -> Optional[str]:
    current = start
    visited = set()
    while current not in canonical_rows:
        if current in visited or len(visited) >= max_depth:
            return None  # cycle or runaway chain
        visited.add(current)
        if current not in full_link_map:
            return None  # dead end, e.g. Etc/UTC: not a geographic row
        current = full_link_map[current]
    return current


def build_catalog(source_dir: Path) -> List[dict]:
    zone_tab_rows = parse_zone_tab(source_dir / "zone.tab")
    backward_records = parse_backward(source_dir / "backward")

    canonical_rows: Dict[str, dict] = {}
    row_order: List[str] = []

    for identifier, country_code in zone_tab_rows:
        if identifier not in canonical_rows:
            canonical_rows[identifier] = {
                "identifier": identifier,
                "city": derive_city(identifier),
                "countryCodes": [country_code],
                "aliases": [],
            }
            row_order.append(identifier)
        elif country_code not in canonical_rows[identifier]["countryCodes"]:
            canonical_rows[identifier]["countryCodes"].append(country_code)

    full_link_map = {record.linkname: record.target for record in backward_records}

    for record in backward_records:
        if record.section != "geographic":
            continue
        if record.linkname in canonical_rows:
            continue
        prefix = record.linkname.split("/", 1)[0]
        if prefix not in RECOGNIZED_PREFIXES:
            continue
        resolved_target = resolve_canonical(record.target, canonical_rows, full_link_map)
        if resolved_target is None:
            continue
        if derive_city(record.linkname).casefold() == derive_city(resolved_target).casefold():
            continue  # same final city name as its target; not a distinct city
        # A Link only expresses matching timezone rules, not shared
        # geography, so a linked city with no own zone.tab entry has no
        # authoritative country data: use [] rather than guessing the
        # rule target's country (e.g. Coral_Harbour is not Panama).
        canonical_rows[record.linkname] = {
            "identifier": record.linkname,
            "city": derive_city(record.linkname),
            "countryCodes": [],
            "aliases": [],
        }
        row_order.append(record.linkname)

    for record in backward_records:
        if record.section != "alias":
            continue
        effective_target = record.target1 if record.target1 else record.target
        resolved = resolve_canonical(effective_target, canonical_rows, full_link_map)
        if resolved is None:
            continue  # e.g. UTC/GMT compatibility names: not a geographic row
        if record.linkname == resolved or record.linkname in canonical_rows:
            continue
        aliases = canonical_rows[resolved]["aliases"]
        if record.linkname not in aliases:
            aliases.append(record.linkname)

    for identifier in row_order:
        canonical_rows[identifier]["aliases"].sort()

    return [canonical_rows[identifier] for identifier in row_order]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", required=True, type=Path,
                         help="Directory containing the pinned zone.tab and backward files")
    parser.add_argument("--version", required=True,
                         help="Pinned tzdb release version, e.g. 2026e")
    parser.add_argument("--output", required=True, type=Path,
                         help="Output path for the generated JSON catalog")
    args = parser.parse_args()

    entries = build_catalog(args.source_dir)

    envelope = {
        "generatedNote": (
            "Generated by scripts/generate-timezone-catalog.py from the IANA tzdb "
            "zone.tab and backward files. Names/search metadata only, not timezone "
            "rules. Do not edit by hand."
        ),
        "sourceVersion": args.version,
        "sourceURLs": [
            "https://www.iana.org/time-zones",
            f"https://data.iana.org/time-zones/releases/tzdata{args.version}.tar.gz",
        ],
        "entries": entries,
    }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8") as f:
        json.dump(envelope, f, indent=2)
        f.write("\n")


if __name__ == "__main__":
    main()
