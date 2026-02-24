# ZuluBar

A minimal macOS menu bar app that displays UTC time with one-click copying and customizable display formats.

## Usage

- **Left-click** → Copy UTC time to clipboard
- **Right-click** → Settings menu

Display options:

- Toggle seconds on/off
- Suffix: `14:23:45 UTC` or `14:23:45Z` or `14:23:45`
- Date prefix: none, `Tue Dec 2 14:23:45 UTC`, or `Tue 2 Dec 14:23:45 UTC`

Copy formats:

- Human Readable: `14:23:45 UTC`
- ISO 8601: `2025-12-02T14:23:45Z`
- Unix Timestamp: `1733150625`
- RFC 3339: `2025-12-02T14:23:45Z`

## Development

Requires macOS 14.0+ and Xcode 16.0+. Open `ZuluBar.xcodeproj` and run (⌘R).

Architecture:

- `ZuluBarApp.swift` - App entry point
- `AppDelegate.swift` - Menu bar management and UI
- `TimeFormatter.swift` - Time formatting logic

**Run tests:** ⌘U in Xcode or:

```bash
xcodebuild test \
  -project ZuluBar.xcodeproj \
  -scheme ZuluBar \
  -configuration Debug-Free \
  -derivedDataPath ./build/DerivedDataLocal \
  CODE_SIGNING_ALLOWED=NO
```

Build configurations:

- `Debug-Free` / `Release-Free` (unsigned)
- `Debug-Paid` / `Release-Paid` (signed)

Common commands:

```bash
# Free (unsigned)
make build-free
make build-free-release
make zip-free

# Paid (signed)
make build-paid
make build-paid-release
make zip
```

## Contributing

Pull requests welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT - see [LICENSE](LICENSE)
