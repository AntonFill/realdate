# realdate

A CLI tool that extracts dates from filenames, sets macOS file timestamps, and cleans up filenames for better file system sorting.

## Problem

When organizing documents (PDFs, scans, notes) with embedded dates in filenames like `2026.06.07 MyDocument.pdf`, the Finder sorts by filename rather than actual file creation/modification date. This tool moves the date from the filename into the file's metadata attributes.

## Features

- **Extract dates** from filename prefix (flexible format: `yyyy.MM.dd.HH.mm`, `yyyy.MM.dd`, `yyyy-MM-dd`, `yyyy_MM_dd`)
- **Parse optional time** from the prefix (`2026.06.07.14.30` sets 14:30, a date without time falls back to 00:00)
- **Set macOS timestamps** (both creation and modification dates)
- **Clean filenames** by removing the date prefix
- **Duplicate handling** with automatic counter (`Document.txt`, `Document 2.txt`, `Document 3.txt`)
- **Recursive processing** with `-r` flag
- **Verbose mode** with `-v` flag for detailed output
- **Skip files** without a leading date, plus hidden files and folders (safe to run on mixed directories)

## Installation

```bash
brew install antonfill/tap/realdate
```

The formula builds from source, so Xcode 26.4 or newer has to be installed.

### From source

```bash
make build       # release build
make install     # installs to /usr/local/bin
swift test       # run the test suite
```

### Uninstallation

```bash
brew uninstall realdate     # installed via Homebrew
make uninstall              # installed from source
```

## Usage

```bash
# Process single file assigning scanned leading date from filename into the file's metadata attributes
realdate "2026.06.07 MyDocument.pdf"

# Process directory
realdate ~/Documents

# Process recursively
realdate -r ~/Paperless

# Process assigning date into attributes and renaming/removing leading dates in filename
realdate --rename ~/Paperless

# Process with custom date format for scanning filename prefix different from listing above
realdate --format "dd.MM.yyyy" ~/Paperless

# Verbose output
realdate -v -r .

# Show help
realdate --help
```

## Filename Format

### Supported Date Formats
- **Dots:** `2026.06.07 MyDocument.pdf` → `MyDocument.pdf`
- **Dashes:** `2026-06-07 MyDocument.pdf` → `MyDocument.pdf`
- **Underscores:** `2026_06_08 MyDocument.pdf` → `MyDocument.pdf`

### With Time
- **Time format:** `2026.06.07.14.30 Email.eml` → `Email.eml` (time: 14:30)
- Time is optional; if missing, defaults to 00:00

Since v1.1.0 the filename is the single source of truth and timestamps are synchronised to the minute. Earlier versions compared the existing timestamp first and skipped a file whose date already matched, which left the time wrong.

### Edge Cases
- **Multiple spaces:** `2026.06.07 My Important Doc.pdf` → `My Important Doc.pdf`
- **No date:** `MyDocument.pdf` → skipped silently (or with message in verbose mode)
- **Trailing dates:** `2026.06.07 Document 2025.05.10.pdf` → `Document 2025.05.10.pdf` (only first date processed)
- **Duplicates:** Automatic counter added (`Document.txt`, `Document 2.txt`, etc.)

## Options
```bash
ARGUMENTS:
  <path>                  Path to file(s) or directory.

OPTIONS:
  --format <format>       Date custom format (e.g. dd-MM-yyyy, yyyy-MM-dd,
                          yyyy-MM-dd-HH-mm). (default: yyyy.MM.dd.HH.mm,
                          yyyy.MM.dd)
  -r, --recursive         Search recursively in subdirectories.
  -v, --verbose           Show detailed information.
  --rename                Set timestamps, and rename files.
  --version               Show the version.
  -h, --help              Show help information.
```

## Development

```bash
swift build -c release   # binary: .build/release/realdate
swift test               # run the test suite
make clean               # clean build artifacts
```

## Use Cases
- **Paperless Office**: Organize scanned documents by their archive date, not scan date.
- **Obsidian Vault**: Sort markdown notes by creation date stored in filename
- **Email Archives**: Extract emails with timestamps intact
- **Bulk Organization**: Rename and timestamp entire directories recursively

## Implementation Details

- **Date parsing:** Two-pass approach with `DateFormatter` (tries time format first, then date-only)
- **Flexible separators:** Normalizes `-`, `_`, `:`, and spaces to `.` for parsing
- **Duplicate handling:** Incremental counter like macOS Finder
- **Verbose mode:** Shows skipped files, ignored files, duplicate handling, and timestamp details

## Compatibility

- Runs on macOS 13+
- Builds with Swift 6.3 (Xcode 26.4)
- Requires file system write permissions
