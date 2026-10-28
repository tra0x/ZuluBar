#!/usr/bin/env python3
"""Stdlib unittest fixtures for generate-timezone-catalog.py.

Run with:
    python3 -m unittest discover -s scripts -p 'test_generate_timezone_catalog.py'
"""

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

_MODULE_PATH = Path(__file__).resolve().with_name("generate-timezone-catalog.py")
_spec = importlib.util.spec_from_file_location("generate_timezone_catalog", _MODULE_PATH)
generate_timezone_catalog = importlib.util.module_from_spec(_spec)
sys.modules[_spec.name] = generate_timezone_catalog
_spec.loader.exec_module(generate_timezone_catalog)

build_catalog = generate_timezone_catalog.build_catalog


def write_source_dir(zone_tab: str, backward: str) -> Path:
    tmp = Path(tempfile.mkdtemp())
    (tmp / "zone.tab").write_text(zone_tab, encoding="utf-8")
    (tmp / "backward").write_text(backward, encoding="utf-8")
    return tmp


class LinkedCityCountryInferenceTests(unittest.TestCase):
    """A Link expresses matching timezone rules, not shared geography."""

    def test_geographic_linked_city_without_zone_tab_entry_has_no_country(self):
        zone_tab = "PA\t+0858-07932\tAmerica/Panama\n"
        backward = (
            "# Non-zone.tab locations with timestamps since 1970 that duplicate\n"
            "# those of an existing location\n"
            "Link\tAmerica/Panama\t\tAmerica/Coral_Harbour\n"
        )
        entries = build_catalog(write_source_dir(zone_tab, backward))
        by_id = {e["identifier"]: e for e in entries}

        self.assertIn("America/Coral_Harbour", by_id)
        self.assertEqual(by_id["America/Coral_Harbour"]["countryCodes"], [])
        self.assertEqual(by_id["America/Coral_Harbour"]["city"], "Coral Harbour")
        # The real zone.tab row keeps its own authoritative country data.
        self.assertEqual(by_id["America/Panama"]["countryCodes"], ["PA"])

    def test_multiple_geographic_linked_cities_stay_distinct_and_countryless(self):
        zone_tab = (
            "NZ\t-3652+17446\tPacific/Auckland\n"
            "DE\t+5230+01322\tEurope/Berlin\n"
        )
        backward = (
            "# Non-zone.tab locations with timestamps since 1970 that duplicate\n"
            "Link\tPacific/Auckland\tAntarctica/South_Pole\n"
            "Link\tEurope/Berlin\tAtlantic/Jan_Mayen\n"
        )
        entries = build_catalog(write_source_dir(zone_tab, backward))
        by_id = {e["identifier"]: e for e in entries}

        self.assertIn("Antarctica/South_Pole", by_id)
        self.assertIn("Atlantic/Jan_Mayen", by_id)
        self.assertEqual(by_id["Antarctica/South_Pole"]["countryCodes"], [])
        self.assertEqual(by_id["Atlantic/Jan_Mayen"]["countryCodes"], [])
        self.assertNotEqual(
            by_id["Antarctica/South_Pole"]["identifier"],
            by_id["Atlantic/Jan_Mayen"]["identifier"],
        )


class AliasAndRenameResolutionTests(unittest.TestCase):
    def test_old_spelling_becomes_alias_of_current_spelling(self):
        zone_tab = "IN\t+2232+08822\tAsia/Kolkata\n"
        backward = (
            "# Alternate names for the same location\n"
            "Link\tAsia/Kolkata\tAsia/Calcutta\n"
        )
        entries = build_catalog(write_source_dir(zone_tab, backward))
        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]["identifier"], "Asia/Kolkata")
        self.assertIn("Asia/Calcutta", entries[0]["aliases"])

    def test_technical_alias_resolves_through_target1_indirection(self):
        # Mirrors the real Australia/ACT line: linked to Australia/Sydney,
        # but the "#= TARGET1" comment says the intended target is the
        # (non-zone.tab) Australia/Canberra, which itself should resolve to
        # the real canonical row.
        zone_tab = "AU\t-3352+15113\tAustralia/Sydney\n"
        backward = (
            "# Non-zone.tab locations with timestamps since 1970 that duplicate\n"
            "Link\tAustralia/Sydney\tAustralia/Canberra\n"
            "# Pre-1993 naming conventions\n"
            "Link\tAustralia/Sydney\tAustralia/ACT\t#= Australia/Canberra\n"
        )
        entries = build_catalog(write_source_dir(zone_tab, backward))
        by_id = {e["identifier"]: e for e in entries}
        # TARGET1 ("#= Australia/Canberra") takes precedence over the direct
        # link-to-link-avoidance TARGET (Australia/Sydney): this matches the
        # real generated catalog, where Australia/ACT is an alias of the
        # distinct Australia/Canberra row, not of Australia/Sydney.
        self.assertIn("Australia/ACT", by_id["Australia/Canberra"]["aliases"])

    def test_technical_alias_with_no_geographic_row_still_resolves(self):
        zone_tab = "CA\t+4339-07923\tAmerica/Toronto\n"
        backward = (
            "# Pre-1993 naming conventions\n"
            "Link\tAmerica/Toronto\tCanada/Eastern\n"
        )
        entries = build_catalog(write_source_dir(zone_tab, backward))
        self.assertEqual(len(entries), 1)
        self.assertIn("Canada/Eastern", entries[0]["aliases"])


class IgnoredCommentsTests(unittest.TestCase):
    def test_commented_out_link_line_is_skipped(self):
        zone_tab = "CA\t+5024-10439\tAmerica/Regina\n"
        backward = (
            "# Pre-1993 naming conventions\n"
            "# This line is commented out, as the name exceeded the limit.\n"
            "#Link\tAmerica/Regina\t\tCanada/East-Saskatchewan\n"
        )
        entries = build_catalog(write_source_dir(zone_tab, backward))
        self.assertEqual(entries[0]["aliases"], [])

    def test_non_link_lines_are_skipped(self):
        zone_tab = "GB\t+513030-0000731\tEurope/London\n"
        backward = (
            "# This file is in the public domain.\n"
            "\n"
            "Zone Europe/London -0:01:15 - LMT 1847\n"
            "Rule Britain 1916 only - May 21 2:00s 1:00 BST\n"
        )
        entries = build_catalog(write_source_dir(zone_tab, backward))
        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]["identifier"], "Europe/London")


class CycleProtectionTests(unittest.TestCase):
    def test_link_cycle_with_no_zone_tab_entry_is_dropped_without_crashing(self):
        # Both link targets are recognized geographic prefixes, but neither
        # has a real zone.tab row or chain that terminates in one, so
        # resolve_canonical must detect the cycle and return None rather
        # than looping forever or raising.
        zone_tab = "US\t+404251-0740023\tAmerica/New_York\n"
        backward = (
            "# Non-zone.tab locations with timestamps since 1970 that duplicate\n"
            "Link\tAmerica/CycleB\tAmerica/CycleA\n"
            "Link\tAmerica/CycleA\tAmerica/CycleB\n"
        )
        entries = build_catalog(write_source_dir(zone_tab, backward))
        identifiers = [e["identifier"] for e in entries]
        self.assertEqual(identifiers, ["America/New_York"])
        self.assertNotIn("America/CycleA", identifiers)
        self.assertNotIn("America/CycleB", identifiers)


class DeterministicGenerationTests(unittest.TestCase):
    def test_build_catalog_is_deterministic_across_runs(self):
        zone_tab = (
            "CA\t+4339-07923\tAmerica/Toronto\n"
            "US\t+404251-0740023\tAmerica/New_York\n"
        )
        backward = (
            "# Pre-1993 naming conventions\n"
            "Link\tAmerica/Toronto\tCanada/Eastern\n"
            "# Non-zone.tab locations with timestamps since 1970 that duplicate\n"
            "Link\tAmerica/Toronto\tAmerica/Montreal\n"
        )
        source_dir = write_source_dir(zone_tab, backward)
        first = build_catalog(source_dir)
        second = build_catalog(source_dir)
        self.assertEqual(first, second)


if __name__ == "__main__":
    unittest.main()
