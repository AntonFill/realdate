//
//  CommandFailureTests.swift
//  realdate
//
//  Created by Anton Fillmann on 17.08.2026.
//

import Testing
import Foundation
@testable import realdate

/// Acceptance level, failure half: what the command refuses to do, and what it
/// cannot do. The level itself is described in `CommandTests.swift`, and the
/// process plumbing lives in `CommandRunner.swift`.
///
/// Split off from `CommandTests` because these are their own concern, and because
/// they are the only tests that can see the failure contract at all: the exit code,
/// the stream a message went to, and whether a tree run gave up or carried on. An
/// in-process test observes none of the three.
///
/// The two kinds are kept apart by their exit code, which is the user-visible
/// difference: **64** means the command line itself was wrong and nothing ran,
/// **1** means the work started and something in it failed.
@Suite("Command Failures")
struct CommandFailureTests {

    // MARK: - Wrong command line, nothing ran

    @Test("Refuses to run without a path, and says so on standard error")
    func refusesWithoutPath() throws {
        let command = try CommandRunner()
        defer {
            command.removeWorkspace()
        }

        let run = try command.run([])

        // 64 is EX_USAGE, which ArgumentParser exits with on a usage error.
        #expect(run.exitCode == 64)
        #expect(run.standardOutput.isEmpty)
        #expect(run.standardError.contains("Missing expected argument '<path>'"))
    }

    @Test("Rejects an unknown option instead of ignoring it")
    func rejectsUnknownOption() throws {
        let command = try CommandRunner()
        defer {
            command.removeWorkspace()
        }
        try command.makeFile(named: "2026.03.05 Receipt.md")

        let run = try command.run(["--bogus", "2026.03.05 Receipt.md"])

        #expect(run.exitCode == 64)
        #expect(run.standardError.contains("Unknown option '--bogus'"))
        // The run must not have half-processed the file before noticing.
        #expect(command.exists("2026.03.05 Receipt.md"))
    }

    @Test("Rejects an empty format instead of dating a whole tree to the reference date")
    func rejectsEmptyFormat() throws {
        let command = try CommandRunner()
        defer {
            command.removeWorkspace()
        }
        try command.makeFile(named: "Important.md")
        try command.makeDirectory(named: "Inner")
        try command.makeFile(named: "Inner/2026.08.01 Note.md")
        let untouched = try #require(makeUTCDate(2026, 8, 1, hour: 16, minute: 12))
        try command.setTimestamps(of: "Important.md", creation: untouched)

        // How this arrives in practice: --format "$FORMAT" with the variable unset.
        let run = try command.run(["-r", "--rename", "--format", "", "."])

        #expect(run.exitCode == 64)
        #expect(run.standardError.contains("--format needs a date format, not an empty string."))
        // An empty format matches every name, dates it to 2000-01-01, and trims nothing
        // off, so --rename would move each file aside without any visible reason.
        #expect(try command.contents().sorted() == ["Important.md", "Inner"])
        #expect(try command.creationDate(of: "Important.md") == untouched)
        #expect(command.exists("Inner/2026.08.01 Note.md"))
    }

    // MARK: - Work started and failed

    @Test("Reports a missing path on standard error and exits non-zero")
    func failsOnMissingPath() throws {
        let command = try CommandRunner()
        defer {
            command.removeWorkspace()
        }

        let run = try command.run(["does-not-exist.md"])

        // Until 1.3.0 this was stdout with exit 0, so `realdate x || echo failed` never fired.
        #expect(run.exitCode == 1)
        #expect(run.standardOutput.isEmpty)
        #expect(run.standardError == "realdate: does-not-exist.md: No such file or directory\n")
    }

    @Test("Reports an unreadable directory in the tool's own shape, and keeps Foundation's text behind -v")
    func failsOnUnreadableDirectory() throws {
        let command = try CommandRunner()
        defer {
            try? command.setPermissions(of: "locked", 0o755)
            command.removeWorkspace()
        }
        try command.makeDirectory(named: "locked")
        try command.setPermissions(of: "locked", 0o000)

        let quiet = try command.run(["locked"])

        #expect(quiet.exitCode == 1)
        // Foundation's own line names the item in typographic quotes and is localized,
        // so it must not be the whole message a user gets.
        #expect(quiet.standardError == "realdate: locked: cannot be read\n")

        let verbose = try command.run(["-v", "locked"])

        #expect(verbose.exitCode == 1)
        #expect(verbose.standardError.contains("realdate: locked: cannot be read\n"))
        // The reason is still worth having, one level down.
        #expect(verbose.standardError.contains("permission"))
    }

    @Test("Reports a rename it was not allowed to perform")
    func failsOnDeniedRename() throws {
        let command = try CommandRunner()
        defer {
            try? command.setPermissions(of: "ro", 0o755)
            command.removeWorkspace()
        }
        try command.makeDirectory(named: "ro")
        try command.makeFile(named: "ro/2026.04.01 Invoice.md")
        try command.setPermissions(of: "ro", 0o555)

        let run = try command.run(["--rename", "ro/2026.04.01 Invoice.md"])

        #expect(run.exitCode == 1)
        #expect(run.standardError == "realdate: 2026.04.01 Invoice.md: cannot be updated\n")
    }

    @Test("Works through the rest of the tree after a failure, and still exits non-zero")
    func continuesAfterFailure() throws {
        let command = try CommandRunner()
        defer {
            try? command.setPermissions(of: "tree/locked", 0o755)
            command.removeWorkspace()
        }
        try command.makeDirectory(named: "tree")
        try command.makeFile(named: "tree/2026.02.02 Good.md")
        try command.makeDirectory(named: "tree/locked")
        try command.setPermissions(of: "tree/locked", 0o000)

        let run = try command.run(["-r", "--rename", "tree"])

        // Same shape as chmod -R: one bad item does not abandon the others, and the
        // failure surfaces once, at the end, as the exit code.
        #expect(run.exitCode == 1)
        #expect(run.standardError == "realdate: tree/locked: cannot be read\n")
        #expect(command.exists("tree/Good.md"))
        #expect(try command.creationDate(of: "tree/Good.md") == makeUTCDate(2026, 2, 2))
    }
}
