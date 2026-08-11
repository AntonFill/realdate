//
//  HiddenFilesTests.swift
//  realdate
//
//  Created by Anton Fillmann on 09.06.2026.
//

import Testing
import Foundation
@testable import realdate

@Suite("Hidden Files Tests")
struct HiddenFilesTests {

    @Test("Skip hidden files by default")
    func skipHiddenFilesByDefault() throws {
        let tempDir = try createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let oldHiddenURL = tempDir.appendingPathComponent(".2026.06.07 HiddenDocument.txt")
        let newHiddenURL = tempDir.appendingPathComponent("HiddenDocument.txt")
        try "Hidden content".write(to: oldHiddenURL, atomically: true, encoding: .utf8)
        
        let oldNormalURL = tempDir.appendingPathComponent("2026.06.07 NormalDocument.txt")
        let newNormalURL = tempDir.appendingPathComponent("NormalDocument.txt")
        try "Normal content".write(to: oldNormalURL, atomically: true, encoding: .utf8)

        var realDate = makeRealDate(path: tempDir.path(percentEncoded: false), rename: true)
        try realDate.run()
        
        // Hidden file should still exist with original name
        #expect(FileManager.default.fileExists(atPath: oldHiddenURL.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: newHiddenURL.path(percentEncoded: false)) == false)
        
        // Normal file should be processed
        #expect(FileManager.default.fileExists(atPath: oldNormalURL.path(percentEncoded: false)) == false)
        #expect(FileManager.default.fileExists(atPath: newNormalURL.path(percentEncoded: false)))
    }

    @Test("Skip hidden directories by default")
    func skipHiddenDirectoriesByDefault() throws {
        let tempDir = try createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let hiddenDirURL = tempDir.appendingPathComponent(".hidden_subdir")
        try FileManager.default.createDirectory(at: hiddenDirURL, withIntermediateDirectories: true)
        
        let testFileURL = hiddenDirURL.appendingPathComponent("2026.06.07 TestInHiddenDir.txt")
        try "Content".write(to: testFileURL, atomically: true, encoding: .utf8)

        var realDate = makeRealDate(path: tempDir.path(percentEncoded: false), recursive: true, rename: true)
        try realDate.run()

        #expect(FileManager.default.fileExists(atPath: testFileURL.path(percentEncoded: false)))
    }
}
