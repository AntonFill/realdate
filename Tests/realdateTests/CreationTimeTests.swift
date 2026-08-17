//
//  CreationTimeTests.swift
//  realdate
//
//  Created by Anton Fillmann on 12.08.2026.
//

import Testing
import Foundation
@testable import realdate

@Suite("Creation Time")
struct CreationTimeTests {

    /// Writes a file and forces a creation date on it, so the test can state where the file
    /// stood before the run.
    private func makeFile(named name: String, createdAt date: Date, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try "Test content".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.creationDate: date],
            ofItemAtPath: url.path(percentEncoded: false)
        )
        return url
    }

    private func creationDate(of url: URL) throws -> Date? {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        return attributes[.creationDate] as? Date
    }

    @Test("Date-only name keeps the clock time it already has on that day")
    func keepsTimeOnSameDay() throws {
        let tempDir = try createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let created = try makeDate(2020, 1, 2, hour: 12, minute: 15)
        let fileURL = try self.makeFile(named: "2020.01.02 Note.md", createdAt: created, in: tempDir)

        var realDate = makeRealDate(path: tempDir.path(percentEncoded: false))
        try realDate.run()

        // Midnight comes from the format, not from a measurement, so it must not win here.
        #expect(try self.creationDate(of: fileURL) == created)
    }

    @Test("A file whose date already matches is still renamed")
    func renamesEvenWhenTimeIsKept() throws {
        let tempDir = try createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let created = try makeDate(2020, 1, 2, hour: 12, minute: 15)
        _ = try self.makeFile(named: "2020.01.02 Note.md", createdAt: created, in: tempDir)
        let renamedURL = tempDir.appendingPathComponent("Note.md")

        var realDate = makeRealDate(path: tempDir.path(percentEncoded: false), rename: true)
        try realDate.run()

        // v1.0.0 skipped the whole item on a matching date and left the prefix in place.
        #expect(FileManager.default.fileExists(atPath: renamedURL.path(percentEncoded: false)))
        #expect(try self.creationDate(of: renamedURL) == created)
    }

    @Test("Date-only name on a different day sets midnight")
    func setsMidnightOnDifferentDay() throws {
        let tempDir = try createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let created = try makeDate(2020, 1, 5, hour: 12, minute: 15)
        let fileURL = try self.makeFile(named: "2020.01.02 Note.md", createdAt: created, in: tempDir)

        var realDate = makeRealDate(path: tempDir.path(percentEncoded: false))
        try realDate.run()

        #expect(try self.creationDate(of: fileURL) == (try makeDate(2020, 1, 2)))
    }

    @Test("Name carrying a time overrules the clock time on the same day")
    func nameWithTimeWins() throws {
        let tempDir = try createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let created = try makeDate(2020, 1, 2, hour: 12, minute: 15)
        let fileURL = try self.makeFile(named: "2020.01.02.08.30 Note.md", createdAt: created, in: tempDir)

        var realDate = makeRealDate(path: tempDir.path(percentEncoded: false))
        try realDate.run()

        // The name states a time of its own, so it is a measurement and takes precedence.
        #expect(try self.creationDate(of: fileURL) == (try makeDate(2020, 1, 2, hour: 8, minute: 30)))
    }
}
