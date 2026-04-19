# Changelog

All notable changes to ZuluBar will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-04-19

### Added
- Configurable global copy shortcut — set a system-wide hotkey to copy the current time without clicking the menu bar icon
- Shortcut recorder panel with Record, Clear, and Done actions
- Existing shortcut is preserved if a new binding cannot be registered (e.g. claimed by macOS or another app)

## [0.1.0] - 2026-02-24

### Added
- Menu bar display of current UTC time, updating every second
- Left-click to instantly copy the current time to clipboard with visual confirmation
- Right-click menu for settings and preferences
- Toggle seconds display on/off
- Date prefix formats: none, `Tue Dec 2`, or `Tue 2 Dec`
- Display suffix options: `Z`, `UTC`, or none
- Three copy formats:
  - Display (`14:23:45Z`)
  - Unix Timestamp (`1733150625`)
  - RFC 3339 (`2025-12-02T14:23:45Z`)
- All preferences persisted via UserDefaults

[unreleased]: https://github.com/tra0x/ZuluBar/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/tra0x/ZuluBar/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/tra0x/ZuluBar/releases/tag/v0.1.0
