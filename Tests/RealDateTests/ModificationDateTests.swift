//
//  ModificationDateTests.swift
//  realdate
//
//  Created by Anton Fillmann on 11.08.2026.
//

import Testing
import Foundation
@testable import realdate

@Suite("Modification Date")
struct ModificationDateTests {

    @Test("Modification date newer than the name is kept")
    func keepNewerModificationDate() throws {
        let tempDir = try createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let testURL = tempDir.appendingPathComponent("2026.06.07 TestDocument.txt")
        try "Test content".write(to: testURL, atomically: true, encoding: .utf8)

        // A file edited long after the date in its name: that edit is a fact about the file
        // and must not be overwritten by the filename.
        let editedAt = Date(timeIntervalSince1970: 1_800_000_000) // 2027-01-15
        try FileManager.default.setAttributes([.modificationDate: editedAt], ofItemAtPath: testURL.path(percentEncoded: false))

        var realDate = makeRealDate(path: testURL.path(percentEncoded: false))
        try realDate.run()

        let formatters = realDate.format.map { $0.customDateFormatter() }
        let date = try #require( realDate.parseDateFromFilename(testURL.lastPathComponent, dateFormatters: formatters)?.date )
        let attributes = try FileManager.default.attributesOfItem(atPath: testURL.path(percentEncoded: false))

        #expect(attributes[.creationDate] as? Date == date)
        #expect(attributes[.modificationDate] as? Date == editedAt)
    }

    @Test("Modification date older than the name is lifted")
    func liftOlderModificationDate() throws {
        let tempDir = try createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let testURL = tempDir.appendingPathComponent("2026.06.07 TestDocument.txt")
        try "Test content".write(to: testURL, atomically: true, encoding: .utf8)

        // Without lifting it, the file would end up modified before it was created.
        let staleDate = Date(timeIntervalSince1970: 1_000_000_000) // 2001-09-09
        try FileManager.default.setAttributes([.modificationDate: staleDate], ofItemAtPath: testURL.path(percentEncoded: false))

        var realDate = makeRealDate(path: testURL.path(percentEncoded: false))
        try realDate.run()

        let formatters = realDate.format.map { $0.customDateFormatter() }
        let date = try #require( realDate.parseDateFromFilename(testURL.lastPathComponent, dateFormatters: formatters)?.date )
        let attributes = try FileManager.default.attributesOfItem(atPath: testURL.path(percentEncoded: false))

        #expect(attributes[.creationDate] as? Date == date)
        #expect(attributes[.modificationDate] as? Date == date)
    }

    @Test("Creation date is never left behind the modification date")
    func creationNeverAfterModification() throws {
        let tempDir = try createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let testURL = tempDir.appendingPathComponent("2026.06.07 TestDocument.txt")
        try "Test content".write(to: testURL, atomically: true, encoding: .utf8)

        var realDate = makeRealDate(path: testURL.path(percentEncoded: false))
        try realDate.run()

        let attributes = try FileManager.default.attributesOfItem(atPath: testURL.path(percentEncoded: false))
        let created = try #require( attributes[.creationDate] as? Date )
        let modified = try #require( attributes[.modificationDate] as? Date )

        #expect(created <= modified)
    }
}
