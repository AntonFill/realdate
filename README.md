# realdate

[![CI](https://github.com/AntonFill/realdate/actions/workflows/ci.yml/badge.svg)](https://github.com/AntonFill/realdate/actions/workflows/ci.yml)

Turn filename dates into real file timestamps and clean the name up. Built for paperless archives, Obsidian vaults, and AI-ready personal data pipelines.

Part of a family of local-first CLI tools (realdate, [mail2md](https://github.com/AntonFill/mail2md)) that make personal data usable without it ever leaving your Mac.

## Problem

When organizing documents (PDFs, scans, notes) with embedded dates in filenames like `2026.06.07 MyDocument.pdf`, the Finder sorts by filename rather than actual file creation/modification date. This tool moves the date from the filename into the file's metadata attributes.

## Features

- **Extract dates** from filename prefix (flexible format: `yyyy.MM.dd.HH.mm`, `yyyy.MM.dd`, `yyyy-MM-dd`, `yyyy_MM_dd`)
- **Parse optional time** from the prefix (`2026.06.07.14.30` sets 14:30, a date without time means 00:00)
- **Default time** for names that state only a day, with `--default-time 21:00`, so a weekly review named after its Sunday sorts after that Sunday's notes
- **Set macOS timestamps** by one rule: a coarser statement never replaces a finer one. Midnight from a date-only name does not overwrite a real time on that same day, and the modification date is only lifted, never pulled back
- **Clean filenames** by removing the date prefix
- **Duplicate handling** with automatic counter (`Document.txt`, `Document 2.txt`, `Document 3.txt`)
- **Recursive processing** with `-r` flag
- **Directories as items** with `-d` flag, so `2026.06.07 Holiday/` can be dated and renamed too
- **Verbose mode** with `-v` flag for detailed output
- **Skip files** without a leading date, plus hidden files and folders (safe to run on mixed directories)
- **Never follow symbolic links**, so nothing is written outside the given path

## Installation

```bash
brew install antonfill/tap/realdate
```

The formula builds from source, so it needs Xcode 16 or newer, and with it macOS 14.5 or later.

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

# Process directories themselves as well, not just the files inside them
realdate -r -d --rename ~/Paperless

# Give names that state only a day an evening time instead of midnight
realdate --default-time 21:00 ~/Notes/Reviews

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
- Time is optional; if missing, defaults to 00:00, or to the time given with `--default-time`

Since v1.1.0 the filename is the single source of truth and timestamps are synchronised to the minute. Earlier versions compared the existing timestamp first and skipped a file whose date already matched, which left the time wrong.

### Edge Cases
- **Multiple spaces:** `2026.06.07 My Important Doc.pdf` → `My Important Doc.pdf`
- **No date:** `MyDocument.pdf` → skipped silently (or with message in verbose mode)
- **Trailing dates:** `2026.06.07 Document 2025.05.10.pdf` → `Document 2025.05.10.pdf` (only first date processed)
- **Duplicates:** Automatic counter added (`Document.txt`, `Document 2.txt`, etc.)
- **Already on that day:** `2026.06.07 Doc.pdf`, created on 2026-06-07 at 12:15, keeps its 12:15 and is still renamed to `Doc.pdf`

## Timestamps

Both timestamps follow one rule: **a coarser statement never replaces a finer one.**

The creation date comes from the name, with one exception. A date-only format parses to midnight, and that midnight is a product of the format rather than a measurement, so it never replaces a real clock time the file already carries on that same day. `2026.08.12 Notes.md`, created at 12:15 on that very day, keeps its 12:15. A name that states a time of its own, such as `2026.08.12.09.30 Notes.md`, always wins, because it *is* a measurement. The rename happens either way, only the timestamp is spared.

The modification date is only lifted when the creation date the file ends up with is *newer* than it, and left alone otherwise. The name says when a document is *from*, the modification date says when the file was last *edited*, and an edit that happened after the document's date is a fact worth keeping. Only when the creation date is newer would the file end up modified before it was created, and that inconsistency is corrected by lifting the modification date to exactly the creation date. Lifting it only as far as the name, as up to v1.3.0, could undo a kept clock time, because APFS pulls a creation date down to an earlier modification date.

Both behaviors arrived in v1.2.0. Before that, both dates were set from the name unconditionally.

`--default-time` (since v1.4.0) follows the same rule. It fills the time a date-only name leaves open, and it never replaces a time the file already has on that day: a creation time on that day is kept as before, and an edit earlier on that day wins over the default, because the file demonstrably existed by then. A review named `2026.08.09 Weekly Review.md` and written four days later gets 21:00 on the 9th with `--default-time 21:00`, and its modification date from the 13th stays.

## Directories

Without `-d`, directories are only traversed, never touched, and their own date prefix stays in place. With `-d` a directory is treated like any other item: its timestamps are set, and with `--rename` the prefix is stripped from its name. It applies to the directory given on the command line, and with `-r` to every subdirectory visited.

A directory is always processed after its contents. Every write inside a directory bumps its modification date, so doing it the other way round would undo the work immediately.

## Symbolic Links

Symbolic links are skipped, wherever they turn up: inside a processed directory, and as the path given on the command line. They are never followed.

Following them meant writing outside the path the user actually named, because the timestamp would land on the link's target. In a recursive run a link pointing back up also sent the traversal around the same cycle until the path length ran out, and it processed unrelated directories along the way. Both were fixed in v1.2.0.

## Exit Codes and Streams

Safe to use in a script: a failure is reported on stderr and answered with a non-zero exit code.

| Code | Meaning |
|---|---|
| `0` | Everything the tool was asked to do succeeded. Items it deliberately skipped, such as symbolic links or names without a date, do not change this. |
| `1` | At least one item could not be processed, for example an unreadable directory or a rename that was denied. A run over a tree still processes the remaining items and reports the failure at the end, like `chmod -R`. |
| `64` | The command line itself was wrong: a missing path, an unknown option, an empty `--format`, or a `--default-time` that is not a time like `21:00`. |

Failures go to **stderr**. Everything else, including the `-v` log of what was renamed and dated, goes to **stdout**, the way `cp -v` does. So `realdate -v -r … 2>/dev/null` shows the log and hides only the errors.

Before v1.3.0 every failure was printed to stdout with exit code 0.

## Options

Copied from `realdate --help`, which is the authority. If the two ever disagree, the help is right. In a terminal the help wraps to the width of the window; here it is shown at 80 columns, as a pipe prints it.

```bash
ARGUMENTS:
  <path>                  Path to file(s) or directory.

OPTIONS:
  --format <format>       Date custom format (e.g. dd-MM-yyyy, yyyy-MM-dd,
                          yyyy-MM-dd-HH-mm). (default: yyyy.MM.dd.HH.mm,
                          yyyy.MM.dd)
  --default-time <HH:mm>  Clock time for a name that states only a day, instead
                          of midnight. A time the item already has on that day,
                          from its creation or an edit, comes first.
  -r, --recursive         Search recursively in subdirectories.
  -v, --verbose           Show detailed information.
  --rename                Set timestamps, and rename files.
  -d, --directories       Treat a directory itself as an item: set its
                          timestamps, and rename it with --rename. Applies to
                          the given directory, and to every visited
                          subdirectory with -r.
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

- Building needs Swift 6.0 or newer, which comes with Xcode 16, and Xcode 16 needs macOS 14.5 or later. The package itself targets macOS 13, but the formula builds from source, so an installation starts at 14.5.
- CI builds the release binary with Xcode 16.0, the oldest toolchain the package declares, and runs the test suite with the current one.
- Requires file system write permissions
