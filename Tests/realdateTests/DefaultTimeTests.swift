//
//  DefaultTimeTests.swift
//  realdate
//
//  Created by Anton Fillmann on 18.10.2026.
//

import Testing
import Foundation
@testable import realdate

/// `--default-time` fills the time a date-only name leaves open, and never replaces one the
/// file system measured. Anton's decision 4B of 2026-10-18; each test below is one row of
/// the behavior table that decision was made on.
@Suite("Default Time")
struct DefaultTimeTests {

    private let ninePM = ClockTime(hour: 21, minute: 0)

    /// Writes a file with both timestamps, the modification date first: APFS pulls the
    /// creation date down to any earlier modification date it is given, but lets a later
    /// creation date stand.
    private func makeFile(named name: String, created: Date, modified: Date, in directory: URL) throws -> String {
        let path = directory.appendingPathComponent(name).path(percentEncoded: false)
        try "Test content".write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: path)
        try FileManager.default.setAttributes([.creationDate: created], ofItemAtPath: path)
        return path
    }

    private func timestamps(of path: String) throws -> (created: Date?, modified: Date?) {
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        return (attributes[.creationDate] as? Date, attributes[.modificationDate] as? Date)
    }

    @Test("A name with only a day gets the default time, and a later edit stays")
    func setsDefaultTime() throws {
        let tempDir = try createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // The case that asked for the option: a review named after the Sunday it covers,
        // written days later, would otherwise sort before that Sunday's own notes.
        let written = try makeDate(2020, 1, 5, hour: 9, minute: 30)
        let path = try self.makeFile(named: "2020.01.02 Review.md", created: written, modified: written, in: tempDir)

        var realDate = makeRealDate(path: path, defaultTime: self.ninePM)
        try realDate.run()

        let after = try self.timestamps(of: path)
        #expect(after.created == (try makeDate(2020, 1, 2, hour: 21)))
        #expect(after.modified == written)
    }

    @Test("An older modification date is lifted to the default time, not to midnight")
    func liftsToDefaultTime() throws {
        let tempDir = try createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let stale = Date(timeIntervalSince1970: 1_000_000_000) // 2001-09-09
        let path = try self.makeFile(named: "2020.01.02 Review.md", created: stale, modified: stale, in: tempDir)

        var realDate = makeRealDate(path: path, defaultTime: self.ninePM)
        try realDate.run()

        // Lifted only to midnight, the modification date would drag the 21:00 down with it,
        // and the option would do nothing without a word.
        let after = try self.timestamps(of: path)
        #expect(after.created == (try makeDate(2020, 1, 2, hour: 21)))
        #expect(after.modified == (try makeDate(2020, 1, 2, hour: 21)))
    }

    @Test("An edit earlier on that day wins over the default time")
    func earlierEditWins() throws {
        let tempDir = try createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let created = try makeDate(2020, 1, 1, hour: 8)
        let edited = try makeDate(2020, 1, 2, hour: 10)
        let path = try self.makeFile(named: "2020.01.02 Review.md", created: created, modified: edited, in: tempDir)

        var realDate = makeRealDate(path: path, defaultTime: self.ninePM)
        try realDate.run()

        // The file existed at 10:00 on that day. 21:00 would put its creation after its own
        // edit, and lifting the edit to match would overwrite a measured time.
        let after = try self.timestamps(of: path)
        #expect(after.created == edited)
        #expect(after.modified == edited)
    }

    @Test("An edit later on that day leaves the default time alone")
    func laterEditLeavesDefaultTime() throws {
        let tempDir = try createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let created = try makeDate(2020, 1, 1, hour: 8)
        let edited = try makeDate(2020, 1, 2, hour: 22, minute: 30)
        let path = try self.makeFile(named: "2020.01.02 Review.md", created: created, modified: edited, in: tempDir)

        var realDate = makeRealDate(path: path, defaultTime: self.ninePM)
        try realDate.run()

        let after = try self.timestamps(of: path)
        #expect(after.created == (try makeDate(2020, 1, 2, hour: 21)))
        #expect(after.modified == edited)
    }

    @Test("A creation time already on that day wins over the default time")
    func creationOnSameDayWins() throws {
        let tempDir = try createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let created = try makeDate(2020, 1, 2, hour: 12, minute: 15)
        let edited = try makeDate(2020, 1, 2, hour: 13)
        let path = try self.makeFile(named: "2020.01.02 Note.md", created: created, modified: edited, in: tempDir)

        var realDate = makeRealDate(path: path, defaultTime: self.ninePM)
        try realDate.run()

        let after = try self.timestamps(of: path)
        #expect(after.created == created)
        #expect(after.modified == edited)
    }

    @Test("A name that carries a time ignores the default time")
    func nameWithTimeIgnoresDefaultTime() throws {
        let tempDir = try createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let written = try makeDate(2020, 1, 5, hour: 9, minute: 30)
        let path = try self.makeFile(named: "2020.01.02.08.30 Note.md", created: written, modified: written, in: tempDir)

        var realDate = makeRealDate(path: path, defaultTime: self.ninePM)
        try realDate.run()

        // The name is the single source of truth wherever it states a time.
        #expect(try self.timestamps(of: path).created == (try makeDate(2020, 1, 2, hour: 8, minute: 30)))
    }
}
