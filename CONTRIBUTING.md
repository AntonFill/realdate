# Contributing to realdate

This is a small tool with one author and a deliberately narrow scope.

Issues and pull requests are welcome. The conventions below are strict, and they are written down so that following them is a matter of reading rather than guessing. Nothing here is a matter of taste being enforced after the fact.

## Getting started

```sh
swift build            # debug build
swift test             # the full suite
swift build -c release # must stay warning-free
make install           # installs to /usr/local/bin
```

Requires Swift 6.0 and macOS 13 or later. There is no formatter and no linter, on purpose (see [Layout and style](#layout-and-style)).

## What belongs in this tool

realdate reads **the filename and nothing else**. It does not open the file, and it does not guess.

That line is why some obvious-looking features are absent:

- **No content inspection.** No EXIF, no PDF metadata, no parsing of the document to find a date inside it. Those dates live in a hundred dialects and a wrong one is worse than none.
- **No date guessing.** The formats are given with `--format` and tried in order. A name that matches none of them is skipped and said so with `-v`, rather than being reinterpreted until something fits.
- **Symbolic links are never followed**, not in a directory and not as the given argument. They were followed until v1.2.0, which meant the timestamp landed on the link's target outside the given path, and a link pointing upwards turned one recursive run into 290 directories. There is no `--follow-symlinks`, and adding one would require cycle protection in the same change.

### A coarser statement never replaces a finer one

This is the rule behind the timestamp behavior, and it is worth stating before you change anything in `applyDate`:

- The **creation date** comes from the name. But a date-only format parses to midnight, and that midnight is a product of the format rather than a measurement. If the file already carries a real clock time on that same day, the time stays.
- The **modification date** is only ever lifted, never pulled back. An edit made after the date in the name is a fact, and the name does not know about it. Lifting happens only when the name is newer, which would otherwise leave a file modified before it was created.

Both follow from the same idea: the name says when a document *is from*, the file system says what *happened to it*. Neither gets to overwrite the other with something vaguer.

## Conventions

These are not negotiable, and they apply to sources and tests alike.

- **English** for code comments, identifiers, CLI text, and commit messages.
- **Explicit `self.`** for member access.
- **File header comment**, matching the existing files:
  `//  <File>.swift  //  realdate  //  Created by <author> on DD.MM.YYYY.`
- **Group code with `// MARK: -`** and extensions, rather than one large type body.
- **Bump `static let version`** in `RealDate.swift` with every user-visible change. Commit `883e0ed` exists solely because that was forgotten once.

### Tests

- **Swift Testing** (`import Testing`, `@Suite`, `@Test`, `#expect`, `#require`), not XCTest.
- **One test file per concern**, named after it: `SymlinkTests`, `DirectoryTests`, `CreationTimeTests`. New behavior is proven by a test, and the test names state the rule rather than the mechanics.
- **Build the command with `makeRealDate(…)`** from `TestingHelpers.swift`, never by assigning properties by hand. ArgumentParser traps at runtime on a `@Flag` that was neither parsed nor assigned, so a single new flag otherwise crashes every test at once. **Adding a flag means adding it to that helper, with its default.**
- **Every test that touches the file system gets its own directory** from `createTestDirectory()`, which keys on `#fileID` plus a UUID. Suites run in parallel; a shared path means a regressed tool walks through another test's files.
- Prove a behavior by disabling it. If the suite still passes with the code removed, the test was measuring something else.

#### The two levels, and which one your test belongs on

Most suites run **in process**: they build the command with `makeRealDate(…)` and call `run()` on it. That is where a behavior gets covered thoroughly, because a test there costs nothing.

`CommandTests.swift` and `CommandFailureTests.swift` are the level above. Every test in them launches the **built binary** as a subprocess through `CommandRunner`, so what it measures is the command a user types: argument parsing, the exit code, the split between stdout and stderr, and what the run left on disk. None of that is reachable in process, because `run()` neither parses arguments nor exits.

The two files split by outcome, because that is what a user sees: `CommandTests` holds what the command does, `CommandFailureTests` what it refuses (exit 64, nothing ran) and what it cannot do (exit 1, work started and failed).

- **Put a behavior in process** unless it needs one of those four things. The upper level is the second line of defence, not the first: it stays around two dozen tests in total and does not repeat what the suites below already pin.
- **`CommandRunner` pins `TZ=UTC` for the subprocess**, and that is load-bearing rather than hygiene. The command parses the date from the name with `TimeZone.current`, so an unpinned zone makes every expected timestamp depend on the machine. Build expectations with `makeUTCDate(…)` from `CommandRunner.swift`, never with `makeDate(…)`, which is local time for the in-process suites.
- **Never assert a rendered date.** `DateFormatter.mediumDateShortTime` renders in the machine's locale, so `05.03.2026, 00:00` on one machine is `Mar 5, 2026 at 12:00 AM` on the next. Assert the timestamp on disk plus the fixed English fragments around it.
- **Measure the expected output at the running command** before writing the test, rather than deriving it from the sources. A test derived from the code under test only proves the derivation.
- **The rest of the environment is inherited on purpose.** Under `--enable-code-coverage` the child picks up `LLVM_PROFILE_FILE` and writes into the same merge pool, which is how `RealDate.swift` gets counted for a subprocess run at all.

> Coverage does not tell you whether this level exists. Measured on 2026-08-17: adding it moved line coverage from 90.94 % to 93.03 %, because the in-process suites already execute nearly every line. What was missing was not execution but assertion, and the first run of the new level found two defects the 39 tests below could not see.

### Output and errors

- Error style is Unix: `realdate: <path>: <message>`.
- Detail goes through `printIf(self.verbose, …)`. Anything the user did not ask for stays behind `-v`.
- A skip says **what** was skipped and why: a dangling link is reported as a link, not as a missing file, which is why the symlink check runs before the existence check.

Unix means the stream and the exit code too, not just the shape of the line. Until 1.3.0 every failure went to stdout with exit 0, so `realdate … || echo failed` could never fire. The split now:

| | Stream | Exit code | Examples |
|---|---|---|---|
| **Failure** | stderr, unconditional | non-zero | path does not exist, directory cannot be read, rename denied |
| **Skip** | stdout, mostly behind `-v` | 0 | symbolic link, no date prefix, hidden item, subdirectory without `-r` |
| **Detail** | stdout, behind `-v` | 0 | what was renamed, which timestamp was set or kept |

- **A skip is not a failure.** The tool decided not to touch something and says so; `find` and `cp` exit 0 in the same situation. Only a request the tool could not carry out is a failure.
- **Diagnostics stay on stdout, unlike in the sibling mail2md**, which puts everything on stderr. This tool produces no data on stdout, so `-v` output can live there the way `cp -v` and `mv -v` do, and `2>/dev/null` then silences errors only.
- **A tree run does not stop at the first failure.** It sets `self.hadFailure` and carries on, and `run()` throws `ExitCode.failure` at the end, the way `chmod -R` behaves. That is why `processDirectory`, `processFile` and `applyDate` are `mutating`.
- **Never let Foundation's own error text be the whole message.** It names the item in typographic quotes, it is localized, and it carries no path in this tool's shape. Write the tool's line unconditionally and put `error.localizedDescription` behind `-v`.
- **Reject bad input in `validate()`**, not inside `run()`. ArgumentParser then produces the usage error itself: stderr, exit 64, and the usage block. `--format ""` is the case that exists, and it earned the rule.

## Layout and style

The style was set by hand across the sources and is the reference. **When in doubt, copy the shape of the surrounding code.** Please do not run a formatter over this repo.

- **No `!` as a negation, anywhere.** Write the comparison out: `self.rename == false`, `attributes.isEmpty == false`, `tuple.hasTime == false`. A leading `!` is one character that flips a meaning and is easy to read past.
- **No single-line bodies.** Every `if`, `guard` and `else` body goes on its own line between braces, even `return nil`. So never `guard let x else { return nil }`.
- **`catch` starts its own line**, under the closing brace of the `do` block, never cuddled as `} catch`.
- **Line length is not a limit.** A signature or a call stays on one line even at 150 characters. Breaking a line is a way to show structure, not a way to obey a number.
- **Comments state the reason, not the mechanics.** `// Skip hidden files` says what the next line already says. The comments worth writing are the ones explaining why a directory is processed after its contents, or why midnight loses against a real time.

## Before you open a pull request

```sh
swift test                    # all tests green
swift build -c release        # must be warning-free

# No leading ! as a negation.
grep -rnE '(^|[ (\[{,=&|])![A-Za-z_(]' Sources Tests | grep -v '!='
```

Two more by eye:

- Does the change alter anything a user can see? Then bump `version`, and copy the `## Options` block in the README from the actual `realdate --help` output. Do not retype it. A hand-copied options block sat in the README for two months claiming the opposite of what the tool did.
- Does it change timestamp behavior? Then say which of the two rules above it follows, or why it needs a third.

A rule nobody checks is decoration. That is why the commands are here and not just the rules.
