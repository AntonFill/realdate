//
//  CommandTests.swift
//  realdate
//
//  Created by Anton Fillmann on 17.08.2026.
//

import Testing
import Foundation
@testable import realdate

/// Acceptance level of the test pyramid: every test here launches the built binary
/// as a subprocess (see `CommandRunner`), so what is under test is the command a
/// user types. Argument parsing, exit codes, the split between stdout and stderr,
/// and what the run leaves on disk are only visible from here. The in-process
/// suites next to this file call `run()` on the command directly and cannot see any
/// of it.
///
/// The suite stays thin on purpose. The top layer is the second line of defence,
/// not the first: format matching, trimming and the timestamp rules are covered
/// in-process, and each test here pins one contract a user can observe.
///
/// This file holds the contracts for what the command **does**. What it refuses to do
/// and what it cannot do lives in `CommandFailureTests.swift`, because exit codes and
/// the stream a failure went to are their own concern.
///
/// Rendered dates are deliberately never asserted. `DateFormatter.mediumDateShortTime`
/// renders in the machine's locale, so `05.03.2026, 00:00` here would be
/// `Mar 5, 2026 at 12:00 AM` elsewhere. The tests assert the timestamps on disk and
/// the fixed English fragments around them, which is the part the tool controls.
@Suite("Command")
struct CommandTests {

    // MARK: - Invocation

    @Test("Reports its version on standard output, alone")
    func reportsVersion() throws {
        let command = try CommandRunner()
        defer {
            command.removeWorkspace()
        }

        let run = try command.run(["--version"])

        #expect(run.exitCode == 0)
        // Compared against the constant, not against a literal: this catches a stale
        // build, where the binary on disk predates the bump in the sources.
        #expect(run.standardOutput == "\(RealDate.version)\n")
        #expect(run.standardError.isEmpty)
    }

    // MARK: - Timestamps

    @Test("Sets the creation date from the name and stays silent about it")
    func setsCreationDateQuietly() throws {
        let command = try CommandRunner()
        defer {
            command.removeWorkspace()
        }
        try command.makeFile(named: "2026.03.05 Receipt.md")

        let run = try command.run(["2026.03.05 Receipt.md"])

        #expect(run.exitCode == 0)
        // Detail belongs behind -v, so a plain run says nothing on either stream.
        #expect(run.standardOutput.isEmpty)
        #expect(run.standardError.isEmpty)
        #expect(try command.creationDate(of: "2026.03.05 Receipt.md") == makeUTCDate(2026, 3, 5))
        // Without --rename the name is untouched.
        #expect(try command.contents() == ["2026.03.05 Receipt.md"])
    }

    @Test("A date-only name does not overwrite a real clock time on the same day")
    func keepsClockTimeOnSameDay() throws {
        let command = try CommandRunner()
        defer {
            command.removeWorkspace()
        }
        try command.makeFile(named: "2026.03.05 Receipt.md")
        let created = try #require(makeUTCDate(2026, 3, 5, hour: 9, minute: 30))
        try command.setTimestamps(of: "2026.03.05 Receipt.md", creation: created)

        let run = try command.run(["-v", "2026.03.05 Receipt.md"])

        #expect(run.exitCode == 0)
        // The midnight in the name is a product of the format, not a measurement.
        #expect(try command.creationDate(of: "2026.03.05 Receipt.md") == created)
        #expect(run.standardOutput.contains("time kept"))
    }

    @Test("Lifts a modification date that sits before the date in the name")
    func liftsEarlierModificationDate() throws {
        let command = try CommandRunner()
        defer {
            command.removeWorkspace()
        }
        try command.makeFile(named: "2026.03.05 Receipt.md")
        let earlier = try #require(makeUTCDate(2026, 1, 1))
        try command.setTimestamps(of: "2026.03.05 Receipt.md", modification: earlier)

        let run = try command.run(["2026.03.05 Receipt.md"])

        #expect(run.exitCode == 0)
        // Otherwise the file would claim it was modified before it was created.
        #expect(try command.modificationDate(of: "2026.03.05 Receipt.md") == makeUTCDate(2026, 3, 5))
    }

    @Test("Leaves a later modification date alone")
    func keepsLaterModificationDate() throws {
        let command = try CommandRunner()
        defer {
            command.removeWorkspace()
        }
        try command.makeFile(named: "2026.03.05 Receipt.md")
        let later = try #require(makeUTCDate(2026, 6, 1, hour: 14, minute: 0))
        try command.setTimestamps(of: "2026.03.05 Receipt.md", modification: later)

        let run = try command.run(["2026.03.05 Receipt.md"])

        #expect(run.exitCode == 0)
        // An edit after the date in the name is a fact, and the name does not know it.
        #expect(try command.modificationDate(of: "2026.03.05 Receipt.md") == later)
        #expect(try command.creationDate(of: "2026.03.05 Receipt.md") == makeUTCDate(2026, 3, 5))
    }

    // MARK: - Renaming

    @Test("Strips the date prefix with --rename, and keeps the contents")
    func renamesAndKeepsContents() throws {
        let command = try CommandRunner()
        defer {
            command.removeWorkspace()
        }
        try command.makeFile(named: "2026.03.05 Receipt.md", content: "Invoice total")

        let run = try command.run(["--rename", "2026.03.05 Receipt.md"])

        #expect(run.exitCode == 0)
        #expect(try command.contents() == ["Receipt.md"])
        #expect(try command.read("Receipt.md") == "Invoice total")
        #expect(try command.creationDate(of: "Receipt.md") == makeUTCDate(2026, 3, 5))
    }

    @Test("Numbers the file instead of overwriting an existing target name")
    func numbersDuplicateTarget() throws {
        let command = try CommandRunner()
        defer {
            command.removeWorkspace()
        }
        try command.makeFile(named: "Receipt.md", content: "The first one")
        try command.makeFile(named: "2026.03.05 Receipt.md", content: "The second one")

        let run = try command.run(["--rename", "2026.03.05 Receipt.md"])

        #expect(run.exitCode == 0)
        #expect(try command.contents() == ["Receipt 2.md", "Receipt.md"])
        // The file that was already there must be the one that keeps its name.
        #expect(try command.read("Receipt.md") == "The first one")
        #expect(try command.read("Receipt 2.md") == "The second one")
    }

    // MARK: - Skipping

    @Test("Skips a symbolic link, reports it as a link, and never touches its target")
    func skipsSymbolicLink() throws {
        let command = try CommandRunner()
        defer {
            command.removeWorkspace()
        }
        try command.makeFile(named: "Target.md")
        let untouched = try #require(makeUTCDate(2020, 1, 1))
        try command.setTimestamps(of: "Target.md", creation: untouched)
        try command.makeSymbolicLink(named: "2026.03.05 Link.md", to: "Target.md")

        let run = try command.run(["--rename", "2026.03.05 Link.md"])

        #expect(run.exitCode == 0)
        // The timestamp would otherwise land outside the path the user named.
        #expect(try command.creationDate(of: "Target.md") == untouched)
        #expect(command.exists("2026.03.05 Link.md"))
        // A dangling link is reported as a link, not as a missing file, so the wording matters.
        #expect(run.standardOutput.contains("realdate: 2026.03.05 Link.md: Skipping symbolic link"))
    }

    @Test("Leaves a name without a date prefix alone, and only mentions it with -v")
    func skipsNameWithoutDatePrefix() throws {
        let command = try CommandRunner()
        defer {
            command.removeWorkspace()
        }
        try command.makeFile(named: "Undated.md")
        let untouched = try #require(makeUTCDate(2020, 1, 1))
        try command.setTimestamps(of: "Undated.md", creation: untouched)

        let quiet = try command.run(["--rename", "Undated.md"])

        #expect(quiet.exitCode == 0)
        #expect(quiet.standardOutput.isEmpty)
        // No date guessing: a name matching no format is left as it is.
        #expect(try command.creationDate(of: "Undated.md") == untouched)
        #expect(try command.contents() == ["Undated.md"])

        let verbose = try command.run(["-v", "--rename", "Undated.md"])

        #expect(verbose.standardOutput.contains("realdate: Undated.md: No date prefix found, skipping"))
    }

    // MARK: - Directories

    @Test("Processes the contents of a directory but leaves the directory itself alone")
    func leavesDirectoryAloneWithoutFlag() throws {
        let command = try CommandRunner()
        defer {
            command.removeWorkspace()
        }
        try command.makeDirectory(named: "2026.01.02 Folder")
        try command.makeFile(named: "2026.01.02 Folder/2026.01.04 File.md")

        let run = try command.run(["--rename", "2026.01.02 Folder"])

        #expect(run.exitCode == 0)
        // The directory keeps its prefix without -d, so this stays a non-breaking default.
        #expect(try command.contents() == ["2026.01.02 Folder"])
        #expect(command.exists("2026.01.02 Folder/File.md"))
        #expect(try command.creationDate(of: "2026.01.02 Folder/File.md") == makeUTCDate(2026, 1, 4))
    }

    @Test("Dates and renames the directory itself with -d")
    func datesDirectoryWithFlag() throws {
        let command = try CommandRunner()
        defer {
            command.removeWorkspace()
        }
        try command.makeDirectory(named: "2026.01.02 Folder")
        try command.makeFile(named: "2026.01.02 Folder/2026.01.04 File.md")

        let run = try command.run(["-d", "--rename", "2026.01.02 Folder"])

        #expect(run.exitCode == 0)
        #expect(try command.contents() == ["Folder"])
        #expect(try command.creationDate(of: "Folder") == makeUTCDate(2026, 1, 2))
        #expect(command.exists("Folder/File.md"))
    }

    @Test("Handles a directory after everything inside it")
    func processesDirectoryAfterItsContents() throws {
        let command = try CommandRunner()
        defer {
            command.removeWorkspace()
        }
        try command.makeDirectory(named: "2026.01.02 Folder/2026.01.03 Inner")
        try command.makeFile(named: "2026.01.02 Folder/2026.01.04 File.md")

        let run = try command.run(["-r", "-d", "-v", "--rename", "2026.01.02 Folder"])

        #expect(run.exitCode == 0)

        let lines = run.standardOutput.split(separator: "\n").map(String.init)
        let outer = try #require(lines.firstIndex { $0.contains("2026.01.02 Folder: Renamed to Folder") })
        let inner = try #require(lines.firstIndex { $0.contains("2026.01.03 Inner: Renamed to Inner") })
        let file = try #require(lines.firstIndex { $0.contains("2026.01.04 File.md: Renamed to File.md") })

        // Every write inside a directory lifts its modification date, so dating it first
        // would be undone immediately.
        #expect(outer > inner)
        #expect(outer > file)
        #expect(try command.contents() == ["Folder"])
        #expect(command.exists("Folder/Inner"))
        #expect(command.exists("Folder/File.md"))
    }

    // MARK: - Formats

    @Test("Uses the format given with --format instead of the presets")
    func usesGivenFormat() throws {
        let command = try CommandRunner()
        defer {
            command.removeWorkspace()
        }
        try command.makeFile(named: "05-03-2026 Receipt.md")

        let run = try command.run(["--format", "dd-MM-yyyy", "--rename", "05-03-2026 Receipt.md"])

        #expect(run.exitCode == 0)
        #expect(try command.contents() == ["Receipt.md"])
        #expect(try command.creationDate(of: "Receipt.md") == makeUTCDate(2026, 3, 5))
    }

    @Test("Falls through the formats in the order they were given")
    func triesFormatsInOrder() throws {
        let command = try CommandRunner()
        defer {
            command.removeWorkspace()
        }
        try command.makeFile(named: "2026.03.05.09.41 Mail.md")
        try command.makeFile(named: "2026.03.05 Note.md")

        // Both presets in their default order: the one carrying a time has to be tried first,
        // or the shorter one would match its prefix and swallow the time.
        let run = try command.run(["-r", "--rename", "."])

        #expect(run.exitCode == 0)
        #expect(try command.contents() == ["Mail.md", "Note.md"])
        #expect(try command.creationDate(of: "Mail.md") == makeUTCDate(2026, 3, 5, hour: 9, minute: 41))
        #expect(try command.creationDate(of: "Note.md") == makeUTCDate(2026, 3, 5))
    }
}
