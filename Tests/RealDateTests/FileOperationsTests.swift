//
//  FileOperationsTests.swift
//  realdate
//
//  Created by Anton Fillmann on 08.06.2026.
//

import Testing
import Foundation
@testable import realdate

@Suite("File Operations")
struct FileOperationsTests {
    
    @Test("Process single file")
    func processSingleFile() throws {
        let tempDir = try createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let curTestURL = tempDir.appendingPathComponent("2026.06.07 TestDocument.txt")
        let newTestURL = tempDir.appendingPathComponent("TestDocument.txt")
        try "Test content".write(to: curTestURL, atomically: true, encoding: .utf8)

        let modifiedBefore = try #require( FileManager.default.attributesOfItem(atPath: curTestURL.path(percentEncoded: false))[.modificationDate] as? Date )

        var realDate = makeRealDate(path: curTestURL.path(percentEncoded: false), rename: true)
        try realDate.run()
        
        #expect(FileManager.default.fileExists(atPath: curTestURL.path(percentEncoded: false)) == false)
        #expect(FileManager.default.fileExists(atPath: newTestURL.path(percentEncoded: false)))
        
        let formatters = realDate.format.map { $0.customDateFormatter() }
        let date = try #require( realDate.parseDateFromFilename(curTestURL.lastPathComponent, dateFormatters: formatters)?.date )
        let attributes = try FileManager.default.attributesOfItem(atPath: newTestURL.path(percentEncoded: false))
        #expect(attributes[.creationDate] as? Date == date)
        // The file was written just now, so its modification date is newer than the date in
        // its name and has to survive untouched.
        #expect(attributes[.modificationDate] as? Date == modifiedBefore)
    }

    @Test("Skip file with no date")
    func skipFileWithNoDate() throws {
        let tempDir = try createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
                
        let oldTestURL = tempDir.appendingPathComponent("NoDatFile.txt")
        try "Content".write(to: oldTestURL, atomically: true, encoding: .utf8)
        
        let oldAttributes = try FileManager.default.attributesOfItem(atPath: oldTestURL.path(percentEncoded: false))
        let oldCreatedDate = try #require( oldAttributes[.creationDate] as? Date )
        let oldModifiedDate = try #require( oldAttributes[.modificationDate] as? Date )

        var realDate = makeRealDate(path: oldTestURL.path(percentEncoded: false), rename: true)
        try realDate.run()
        
        #expect(FileManager.default.fileExists(atPath: oldTestURL.path(percentEncoded: false)))
        
        let newAttributes = try FileManager.default.attributesOfItem(atPath: oldTestURL.path(percentEncoded: false))
        #expect(newAttributes[.creationDate] as? Date == oldCreatedDate)
        #expect(newAttributes[.modificationDate] as? Date == oldModifiedDate)
    }

    @Test("Skip directories")
    func skipDirectories() throws {
        let tempDir = try createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let testDir = tempDir.appendingPathComponent("2026.06.07 TestDir")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)

        var realDate = makeRealDate(path: testDir.path(percentEncoded: false), rename: true)
        try realDate.run()

        #expect(FileManager.default.fileExists(atPath: testDir.path(percentEncoded: false)))
    }

    @Test("Handle duplicate filenames")
    func handleDuplicateFilenames() throws {
        let tempDir = try createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        // Create two files with different dates but same target name
        let oldTest1URL = tempDir.appendingPathComponent("2026.06.06 Document.txt")
        let newTest1URL = tempDir.appendingPathComponent("Document.txt")
        try "Content 1".write(to: oldTest1URL, atomically: true, encoding: .utf8)
        
        let oldTest2URL = tempDir.appendingPathComponent("2026.06.07 Document.txt")
        let newTest2URL = tempDir.appendingPathComponent("Document 2.txt")
        try "Content 2".write(to: oldTest2URL, atomically: true, encoding: .utf8)
        
        let oldTest3URL = tempDir.appendingPathComponent("2026.06.08 Document.txt")
        let newTest3URL = tempDir.appendingPathComponent("Document 3.txt")
        try "Content 3".write(to: oldTest3URL, atomically: true, encoding: .utf8)

        var realDate = makeRealDate(path: tempDir.path(percentEncoded: false), rename: true)
        try realDate.run()
        
        #expect(FileManager.default.fileExists(atPath: oldTest1URL.path(percentEncoded: false)) == false)
        #expect(FileManager.default.fileExists(atPath: newTest1URL.path(percentEncoded: false)))
        
        #expect(FileManager.default.fileExists(atPath: oldTest2URL.path(percentEncoded: false)) == false)
        #expect(FileManager.default.fileExists(atPath: newTest2URL.path(percentEncoded: false)))
        
        #expect(FileManager.default.fileExists(atPath: oldTest3URL.path(percentEncoded: false)) == false)
        #expect(FileManager.default.fileExists(atPath: newTest3URL.path(percentEncoded: false)))
    }

    @Test("Time removed from filename")
    func timeRemovedFromFilename() throws {
        let tempDir = try createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let oldTestURL = tempDir.appendingPathComponent("2026.06.07 14-30 Email.eml")
        let newTestURL = tempDir.appendingPathComponent("Email.eml")
        try "Email content".write(to: oldTestURL, atomically: true, encoding: .utf8)

        let modifiedBefore = try #require( FileManager.default.attributesOfItem(atPath: oldTestURL.path(percentEncoded: false))[.modificationDate] as? Date )

        var realDate = makeRealDate(path: tempDir.path(percentEncoded: false), rename: true)
        try realDate.run()
        
        #expect(FileManager.default.fileExists(atPath: oldTestURL.path(percentEncoded: false)) == false)
        #expect(FileManager.default.fileExists(atPath: newTestURL.path(percentEncoded: false)))
        
        let formatters = realDate.format.map { $0.customDateFormatter() }
        let date = try #require( realDate.parseDateFromFilename(oldTestURL.lastPathComponent, dateFormatters: formatters)?.date )
        let attributes = try FileManager.default.attributesOfItem(atPath: newTestURL.path(percentEncoded: false))
        #expect(attributes[.creationDate] as? Date == date)
        // The file was written just now, so its modification date is newer than the date in
        // its name and has to survive untouched.
        #expect(attributes[.modificationDate] as? Date == modifiedBefore)
    }
}
