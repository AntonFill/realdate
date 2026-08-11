//
//  TestingHelpers.swift
//  realdate
//
//  Created by Anton Fillmann on 10.06.2026.
//

import Foundation
@testable import realdate

func createTestDirectory(_ fileID: String = #fileID) throws -> URL {
    let fileID = fileID.replacingOccurrences(of: "/", with: "_")
    let url = FileManager.default.temporaryDirectory.appending(path: "\(fileID)_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Builds a fully initialized command.
///
/// Every property has to hold a value before `run()`: an `@Flag` or `@Option` that was neither
/// parsed from the command line nor assigned traps at runtime. Setting them one by one in each
/// test meant that adding a single flag broke every test at once, so the defaults live here.
func makeRealDate(
    path: String,
    format: [String] = ["yyyy.MM.dd.HH.mm", "yyyy.MM.dd"],
    recursive: Bool = false,
    rename: Bool = false,
    verbose: Bool = false,
    directories: Bool = false
) -> RealDate {
    var realDate = RealDate()
    realDate.format = format
    realDate.recursive = recursive
    realDate.rename = rename
    realDate.verbose = verbose
    realDate.directories = directories
    realDate.path = path
    return realDate
}
