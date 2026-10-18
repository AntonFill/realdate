//
//  TestingHelpers.swift
//  realdate
//
//  Created by Anton Fillmann on 10.06.2026.
//

import Testing
import Foundation
@testable import realdate

/// Builds a local-time date, so tests can state a wall clock time instead of an interval.
func makeDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) throws -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    return try #require(Calendar.current.date(from: components))
}

func createTestDirectory(_ fileID: String = #fileID) throws -> URL {
    let fileID = fileID.replacingOccurrences(of: "/", with: "_")
    let url = FileManager.default.temporaryDirectory.appending(path: "\(fileID)_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Builds the command a plain command line would build, so a test names only what it changes.
///
/// The defaults are the command line's defaults. A test that wants the command exactly as a
/// user's arguments produce it goes through `RealDate.invocation(from:)` instead.
func makeRealDate(
    path: String,
    format: [String] = RealDate.defaultFormats,
    defaultTime: ClockTime? = nil,
    recursive: Bool = false,
    rename: Bool = false,
    verbose: Bool = false,
    directories: Bool = false
) -> RealDate {
    RealDate(
        format: format,
        defaultTime: defaultTime,
        recursive: recursive,
        verbose: verbose,
        rename: rename,
        directories: directories,
        path: path
    )
}
