//
//  ArgumentTests.swift
//  realdate
//
//  Created by Anton Fillmann on 18.10.2026.
//

import Testing
@testable import realdate

/// How a command line turns into a command. In process since 1.4.0, when ArgumentParser
/// left: reading the line is a function now, so it no longer needs the built binary.
/// The getopt rules themselves are pinned in `OptionParserTests`; this suite pins what
/// realdate makes of them.
@Suite("Arguments")
struct ArgumentTests {

    // MARK: - Commands

    @Test("A path alone gives the command with every default")
    func pathAloneGivesDefaults() throws {
        #expect(try RealDate.invocation(from: ["notes"]) == .run(makeRealDate(path: "notes")))
    }

    @Test("Reads every flag, grouped or not, before or after the path")
    func readsEveryFlag() throws {
        let expected = makeRealDate(path: "notes", recursive: true, rename: true, verbose: true, directories: true)

        #expect(try RealDate.invocation(from: ["-rvd", "--rename", "notes"]) == .run(expected))
        #expect(try RealDate.invocation(from: ["notes", "--recursive", "--verbose", "--directories", "--rename"]) == .run(expected))
    }

    @Test("Given formats replace the defaults, in the order given")
    func givenFormatsReplaceDefaults() throws {
        let invocation = try RealDate.invocation(from: ["--format", "dd-MM-yyyy", "--format=yyyy", "notes"])

        #expect(invocation == .run(makeRealDate(path: "notes", format: ["dd-MM-yyyy", "yyyy"])))
    }

    @Test("Reads the default time as a clock time")
    func readsDefaultTime() throws {
        let invocation = try RealDate.invocation(from: ["--default-time", "21:00", "notes"])

        #expect(invocation == .run(makeRealDate(path: "notes", defaultTime: ClockTime(hour: 21, minute: 0))))
        #expect(try RealDate.invocation(from: ["--default-time=9:05", "notes"]) == .run(makeRealDate(path: "notes", defaultTime: ClockTime(hour: 9, minute: 5))))
    }

    @Test("A path that starts with a dash is reachable after a double dash")
    func pathAfterDoubleDash() throws {
        #expect(try RealDate.invocation(from: ["--", "-notes"]) == .run(makeRealDate(path: "-notes")))
    }

    // MARK: - Help and version

    @Test("Help and the version need no path")
    func helpAndVersionNeedNoPath() throws {
        #expect(try RealDate.invocation(from: ["--help"]) == .help)
        #expect(try RealDate.invocation(from: ["-h"]) == .help)
        #expect(try RealDate.invocation(from: ["--version"]) == .version)
        #expect(try RealDate.invocation(from: ["-r", "notes", "--version"]) == .version)
    }

    // MARK: - Refusals

    @Test("Refuses a command line without a path, or with two")
    func refusesWrongPathCount() throws {
        #expect(throws: RealDate.UsageError(description: "missing path")) {
            try RealDate.invocation(from: ["-r"])
        }
        // What a glob with two matches produces; the shell, not the user, typed the second.
        #expect(throws: RealDate.UsageError(description: "unexpected argument 'b.md'")) {
            try RealDate.invocation(from: ["a.md", "b.md"])
        }
    }

    @Test("Refuses an empty format before anything runs")
    func refusesEmptyFormat() throws {
        #expect(throws: RealDate.UsageError(description: "--format needs a date format, not an empty string.")) {
            try RealDate.invocation(from: ["--format", "yyyy", "--format", "", "notes"])
        }
    }

    @Test("Refuses a default time that is not exactly a clock time", arguments: ["24:00", "21:60", "21:5", "9pm", "21:00:00", "+9:00", "21.00", ""])
    func refusesInvalidDefaultTime(text: String) throws {
        #expect(throws: RealDate.UsageError(description: "--default-time needs a time as HH:mm, not '\(text)'.")) {
            try RealDate.invocation(from: ["--default-time=\(text)", "notes"])
        }
    }

    @Test("Passes the parser's refusal on in the tool's words")
    func passesParserRefusalOn() throws {
        #expect(throws: RealDate.UsageError(description: "unknown option '--bogus'")) {
            try RealDate.invocation(from: ["--bogus", "notes"])
        }
        #expect(throws: RealDate.UsageError(description: "option '--format' needs a value")) {
            try RealDate.invocation(from: ["notes", "--format"])
        }
    }
}
