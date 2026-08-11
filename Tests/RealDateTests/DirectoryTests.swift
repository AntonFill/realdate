//
//  DirectoryTests.swift
//  realdate
//
//  Created by Anton Fillmann on 11.08.2026.
//

import Testing
import Foundation
@testable import realdate

@Suite("Directories")
struct DirectoryTests {

    @Test("Directory keeps its date prefix without the flag")
    func directoryUntouchedByDefault() throws {
        let tempDir = try createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let testDir = tempDir.appendingPathComponent("2026.06.07 Holiday")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)

        var realDate = makeRealDate(path: testDir.path(percentEncoded: false), rename: true)
        try realDate.run()

        #expect(FileManager.default.fileExists(atPath: testDir.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("Holiday").path(percentEncoded: false)) == false)
    }

    @Test("Given directory is dated and renamed with the flag")
    func processGivenDirectory() throws {
        let tempDir = try createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let oldDirURL = tempDir.appendingPathComponent("2026.06.07 Holiday")
        let newDirURL = tempDir.appendingPathComponent("Holiday")
        try FileManager.default.createDirectory(at: oldDirURL, withIntermediateDirectories: true)

        var realDate = makeRealDate(path: oldDirURL.path(percentEncoded: false), rename: true, directories: true)
        try realDate.run()

        #expect(FileManager.default.fileExists(atPath: oldDirURL.path(percentEncoded: false)) == false)
        #expect(FileManager.default.fileExists(atPath: newDirURL.path(percentEncoded: false)))

        let formatters = realDate.format.map { $0.customDateFormatter() }
        let date = try #require( realDate.parseDateFromFilename(oldDirURL.lastPathComponent, dateFormatters: formatters)?.date )
        let attributes = try FileManager.default.attributesOfItem(atPath: newDirURL.path(percentEncoded: false))
        #expect(attributes[.creationDate] as? Date == date)
    }

    @Test("Subdirectories are processed with -r")
    func processSubdirectoriesRecursively() throws {
        let tempDir = try createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let oldSubURL = tempDir.appendingPathComponent("2026.06.07 Holiday")
        let newSubURL = tempDir.appendingPathComponent("Holiday")
        try FileManager.default.createDirectory(at: oldSubURL, withIntermediateDirectories: true)

        var realDate = makeRealDate(path: tempDir.path(percentEncoded: false), recursive: true, rename: true, directories: true)
        try realDate.run()

        #expect(FileManager.default.fileExists(atPath: oldSubURL.path(percentEncoded: false)) == false)
        #expect(FileManager.default.fileExists(atPath: newSubURL.path(percentEncoded: false)))
    }

    @Test("Directory is processed after its contents")
    func directoryProcessedLast() throws {
        let tempDir = try createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let dirURL = tempDir.appendingPathComponent("2026.06.07 Holiday")
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        try "Photo".write(to: dirURL.appendingPathComponent("2026.06.07 Photo.txt"), atomically: true, encoding: .utf8)

        var realDate = makeRealDate(path: dirURL.path(percentEncoded: false), rename: true, directories: true)
        try realDate.run()

        let newDirURL = tempDir.appendingPathComponent("Holiday")
        let formatters = realDate.format.map { $0.customDateFormatter() }
        let date = try #require( realDate.parseDateFromFilename(dirURL.lastPathComponent, dateFormatters: formatters)?.date )
        let attributes = try FileManager.default.attributesOfItem(atPath: newDirURL.path(percentEncoded: false))

        // Renaming the file inside bumps the directory's modification date. Had the directory
        // been dated first, that write would have undone the work.
        #expect(attributes[.creationDate] as? Date == date)
        #expect(FileManager.default.fileExists(atPath: newDirURL.appendingPathComponent("Photo.txt").path(percentEncoded: false)))
    }

    @Test("Directory without a date prefix is left alone")
    func directoryWithoutDateUntouched() throws {
        let tempDir = try createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let dirURL = tempDir.appendingPathComponent("Holiday")
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

        let attributesBefore = try FileManager.default.attributesOfItem(atPath: dirURL.path(percentEncoded: false))
        let createdBefore = try #require( attributesBefore[.creationDate] as? Date )

        var realDate = makeRealDate(path: dirURL.path(percentEncoded: false), rename: true, directories: true)
        try realDate.run()

        #expect(FileManager.default.fileExists(atPath: dirURL.path(percentEncoded: false)))
        let attributesAfter = try FileManager.default.attributesOfItem(atPath: dirURL.path(percentEncoded: false))
        #expect(attributesAfter[.creationDate] as? Date == createdBefore)
    }
}
