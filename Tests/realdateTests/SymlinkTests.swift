//
//  SymlinkTests.swift
//  realdate
//
//  Created by Anton Fillmann on 11.08.2026.
//

import Testing
import Foundation
@testable import realdate

@Suite("Symbolic Links")
struct SymlinkTests {

    @Test("Link target outside the given path stays untouched")
    func doNotWriteThroughLink() throws {
        let tempDir = try createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let outsideDir = tempDir.appendingPathComponent("outside")
        let workDir = tempDir.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)

        let targetURL = outsideDir.appendingPathComponent("original.txt")
        try "Content".write(to: targetURL, atomically: true, encoding: .utf8)

        // The date sits in the link's name, the content lives elsewhere. Following the link
        // would date a file the user never named.
        let linkURL = workDir.appendingPathComponent("2026.03.09 link.txt")
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: targetURL)

        let attributesBefore = try FileManager.default.attributesOfItem(atPath: targetURL.path(percentEncoded: false))
        let createdBefore = try #require( attributesBefore[.creationDate] as? Date )

        var realDate = makeRealDate(path: workDir.path(percentEncoded: false), rename: true)
        try realDate.run()

        let attributesAfter = try FileManager.default.attributesOfItem(atPath: targetURL.path(percentEncoded: false))
        #expect(attributesAfter[.creationDate] as? Date == createdBefore)

        // The link itself keeps its name too, so nothing suggests work was done.
        #expect(FileManager.default.fileExists(atPath: linkURL.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: workDir.appendingPathComponent("link.txt").path(percentEncoded: false)) == false)
    }

    @Test("Link given as the argument is skipped")
    func skipLinkAsArgument() throws {
        let tempDir = try createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let targetURL = tempDir.appendingPathComponent("original.txt")
        try "Content".write(to: targetURL, atomically: true, encoding: .utf8)

        let linkURL = tempDir.appendingPathComponent("2026.03.09 link.txt")
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: targetURL)

        let attributesBefore = try FileManager.default.attributesOfItem(atPath: targetURL.path(percentEncoded: false))
        let createdBefore = try #require( attributesBefore[.creationDate] as? Date )

        var realDate = makeRealDate(path: linkURL.path(percentEncoded: false), rename: true)
        try realDate.run()

        let attributesAfter = try FileManager.default.attributesOfItem(atPath: targetURL.path(percentEncoded: false))
        #expect(attributesAfter[.creationDate] as? Date == createdBefore)
        #expect(FileManager.default.fileExists(atPath: linkURL.path(percentEncoded: false)))
    }

    @Test("Recursion does not escape through a link into the parent")
    func doNotEscapeThroughLink() throws {
        let tempDir = try createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // Sibling of the processed directory: reachable only by following the link upwards.
        let siblingURL = tempDir.appendingPathComponent("2026.01.01 Sibling.txt")
        try "Sibling".write(to: siblingURL, atomically: true, encoding: .utf8)

        let deepDir = tempDir.appendingPathComponent("deep")
        try FileManager.default.createDirectory(at: deepDir, withIntermediateDirectories: true)

        // The link points at this test's own directory, never above it. Tests run in parallel,
        // so a link to the shared temp directory would send a regressed tool straight through
        // every other test's files.
        try FileManager.default.createSymbolicLink(at: deepDir.appendingPathComponent("back"), withDestinationURL: tempDir)

        var realDate = makeRealDate(path: deepDir.path(percentEncoded: false), recursive: true, rename: true)
        try realDate.run()

        // Untouched name proves the run stayed inside the given directory, and that the cycle
        // was never entered.
        #expect(FileManager.default.fileExists(atPath: siblingURL.path(percentEncoded: false)))
    }

    @Test("Dangling link does not raise an error")
    func skipDanglingLink() throws {
        let tempDir = try createTestDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let linkURL = tempDir.appendingPathComponent("2026.04.01 dangling.txt")
        try FileManager.default.createSymbolicLink(atPath: linkURL.path(percentEncoded: false), withDestinationPath: "/no/such/target")

        var realDate = makeRealDate(path: tempDir.path(percentEncoded: false), rename: true)
        try realDate.run()

        #expect(FileManager.default.isSymbolicLink(atPath: linkURL.path(percentEncoded: false)))
    }
}
