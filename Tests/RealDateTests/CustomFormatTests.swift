//
//  FileOperationsTests.swift
//  realdate
//
//  Created by Anton Fillmann on 09.06.2026.
//

import Testing
import Foundation
@testable import realdate

@Suite("Custom Format Tests")
struct CustomFormatTests {

    @Test("Process file with format flag and check attributes are set")
    func processFileWithCustomFormat() throws {
        let tempDir = try createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let oldTest1URL = tempDir.appendingPathComponent("2026.06.07 TestDocument.txt")
        let newTest1URL = tempDir.appendingPathComponent("TestDocument.txt")
        try "Test content".write(to: oldTest1URL, atomically: true, encoding: .utf8)
        
        let oldTest2URL = tempDir.appendingPathComponent("14.05.2026 TestImage.txt")
        let newTest2URL = tempDir.appendingPathComponent("TestImage.txt")
        try "Test image".write(to: oldTest2URL, atomically: true, encoding: .utf8)

        let dateFormat = "dd.MM.yyyy"
        let modifiedBefore = try #require( FileManager.default.attributesOfItem(atPath: oldTest2URL.path(percentEncoded: false))[.modificationDate] as? Date )

        var realDate = makeRealDate(path: tempDir.path(percentEncoded: false), format: [dateFormat], rename: true)
        try realDate.run()
        
        #expect(FileManager.default.fileExists(atPath: oldTest1URL.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: newTest1URL.path(percentEncoded: false)) == false)
        
        #expect(FileManager.default.fileExists(atPath: oldTest2URL.path(percentEncoded: false)) == false)
        #expect(FileManager.default.fileExists(atPath: newTest2URL.path(percentEncoded: false)))

        let formatter = dateFormat.customDateFormatter()
        let date = try #require( realDate.parseDateFromFilename(oldTest2URL.lastPathComponent, dateFormatters: [formatter])?.date )
        let attributes = try FileManager.default.attributesOfItem(atPath: newTest2URL.path(percentEncoded: false))
        #expect(attributes[.creationDate] as? Date == date)
        // The file was written just now, so its modification date is newer than the date in
        // its name and has to survive untouched.
        #expect(attributes[.modificationDate] as? Date == modifiedBefore)
    }
}
