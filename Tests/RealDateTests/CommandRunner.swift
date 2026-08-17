//
//  CommandRunner.swift
//  realdate
//
//  Created by Anton Fillmann on 17.08.2026.
//

import Foundation
@testable import realdate

/// Launches the built `realdate` binary for the acceptance suite: a throwaway
/// workspace on disk, the items under test created inside it, and one subprocess
/// run per invocation.
///
/// Infrastructure rather than a test file, kept separate so that
/// `RealDateCommandTests.swift` reads as the list of contracts the command keeps
/// instead of process plumbing.
struct CommandRunner {

    /// Creates the workspace the run happens in. Every test gets its own, so
    /// runs cannot see each other's files. Same reason as `createTestDirectory()`
    /// in `TestingHelpers.swift`: suites run in parallel.
    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("realdate-command-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        self.workspace = url
    }

    let workspace: URL

    /// What one invocation of the command left behind.
    struct Invocation {
        let exitCode: Int32
        let standardOutput: String
        let standardError: String
    }

    /// Thrown when the built binary cannot be found, so a failure reads as
    /// "the test setup is broken" rather than "the command misbehaved".
    struct BinaryNotFound: Error, CustomStringConvertible {
        let reason: String

        var description: String {
            return "built \(RealDate.appname) binary not found: \(self.reason)"
        }
    }
}

// MARK: - Running
extension CommandRunner {

    /// Runs the built binary with `arguments`, from inside the workspace, and
    /// collects both streams.
    ///
    /// The working directory is the workspace, so tests pass bare item names and
    /// the command echoes those same names back. An absolute path would put the
    /// temporary directory into every expected line.
    ///
    /// The streams are redirected into files rather than `Pipe`s: a pipe has to be
    /// drained while the child still runs, and draining two of them one after the
    /// other can block on the one not being read. Files cannot deadlock. They live
    /// outside the workspace, so a test can list the workspace without seeing them.
    ///
    /// `TZ` is pinned to UTC, and that is load-bearing here rather than hygiene:
    /// the command parses the date from the name with `TimeZone.current`, so an
    /// unpinned zone would make every expected timestamp depend on the machine
    /// running the tests. It also keeps the conversion visible, because the
    /// timestamp a test asserts is then a UTC one while the developer machine sits
    /// on `Europe/Zurich`.
    ///
    /// The rest of the environment is inherited, and that is load-bearing for the
    /// coverage number: under `--enable-code-coverage` the child picks up
    /// `LLVM_PROFILE_FILE` from it and writes into the same merge pool, which is how
    /// `RealDate.swift` gets counted for the run at all. The tests do not need it,
    /// the number does.
    func run(_ arguments: [String]) throws -> Invocation {
        let outputURL = self.streamsDirectory.appendingPathComponent("stdout.log")
        let errorURL = self.streamsDirectory.appendingPathComponent("stderr.log")
        try FileManager.default.createDirectory(at: self.streamsDirectory, withIntermediateDirectories: true)
        try Data().write(to: outputURL)
        try Data().write(to: errorURL)

        let outputHandle = try FileHandle(forWritingTo: outputURL)
        let errorHandle = try FileHandle(forWritingTo: errorURL)

        let process = Process()
        process.executableURL = try self.binaryURL()
        process.arguments = arguments
        process.currentDirectoryURL = self.workspace
        process.standardOutput = outputHandle
        process.standardError = errorHandle

        var environment = ProcessInfo.processInfo.environment
        environment["TZ"] = "UTC"
        process.environment = environment

        try process.run()
        process.waitUntilExit()
        try outputHandle.close()
        try errorHandle.close()

        return Invocation(
            exitCode: process.terminationStatus,
            standardOutput: try String(contentsOf: outputURL, encoding: .utf8),
            standardError: try String(contentsOf: errorURL, encoding: .utf8)
        )
    }

    /// Where the captured streams go. A sibling of the workspace rather than a
    /// subdirectory of it, so a recursive run under test never walks into them.
    private var streamsDirectory: URL {
        return self.workspace.deletingLastPathComponent()
            .appendingPathComponent("\(self.workspace.lastPathComponent)-streams")
    }

    /// The built binary, found by walking up from this test code's own image until
    /// a directory holds an executable named like the command.
    ///
    /// The SwiftPM idiom (`Bundle.allBundles`, take the `.xctest` one) does not work
    /// under Swift Testing, measured on 2026-08-17: `swift test` loads the test code
    /// as a library into `swiftpm-testing-helper`, so `Bundle.main` points into the
    /// toolchain and no `.xctest` bundle is registered. Asking the dynamic linker
    /// where this very code sits holds for `swift test`, for `-c release` and inside
    /// Xcode's DerivedData, because the products directory is always the one above
    /// the test bundle.
    func binaryURL() throws -> URL {
        var image = Dl_info()

        guard dladdr(#dsohandle, &image) != 0,
            let imagePath = image.dli_fname
        else {
            throw BinaryNotFound(reason: "the dynamic linker does not know where the test code lives")
        }

        let start = URL(fileURLWithPath: String(cString: imagePath)).deletingLastPathComponent()
        var directory = start

        // …/debug/realdatePackageTests.xctest/Contents/MacOS is three levels below the
        // products directory; the extra steps cover a different bundle layout.
        for _ in 0..<5 {
            let candidate = directory.appendingPathComponent(RealDate.appname)
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory)

            if exists, isDirectory.boolValue == false, FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }

            directory = directory.deletingLastPathComponent()
        }

        throw BinaryNotFound(reason: "no executable above \(start.path)")
    }
}

// MARK: - Items in the workspace
extension CommandRunner {

    /// Creates an empty file. The tool reads the name and nothing else, so content
    /// would be decoration.
    @discardableResult
    func makeFile(named name: String) throws -> URL {
        let url = self.path(name)
        try Data().write(to: url)
        return url
    }

    /// Creates a file carrying content, for the cases where a test has to prove the
    /// bytes survived a rename.
    @discardableResult
    func makeFile(named name: String, content: String) throws -> URL {
        let url = self.path(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @discardableResult
    func makeDirectory(named name: String) throws -> URL {
        let url = self.path(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Creates a symbolic link. `destination` is stored as given, so a test can
    /// point one at something that does not exist.
    @discardableResult
    func makeSymbolicLink(named name: String, to destination: String) throws -> URL {
        let url = self.path(name)
        try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: destination)
        return url
    }

    /// A path in the workspace, existing or not.
    func path(_ name: String) -> URL {
        return self.workspace.appendingPathComponent(name)
    }

    func exists(_ name: String) -> Bool {
        return FileManager.default.fileExists(atPath: self.path(name).path)
    }

    func read(_ name: String) throws -> String {
        return try String(contentsOf: self.path(name), encoding: .utf8)
    }

    /// The workspace's own entries, sorted, without the ones a test did not create.
    func contents() throws -> [String] {
        return try FileManager.default.contentsOfDirectory(atPath: self.workspace.path).sorted()
    }

    /// Drops the whole workspace and its stream files. Called from a `defer` in
    /// every test.
    func removeWorkspace() {
        try? FileManager.default.removeItem(at: self.workspace)
        try? FileManager.default.removeItem(at: self.streamsDirectory)
    }
}

// MARK: - Timestamps
extension CommandRunner {

    func creationDate(of name: String) throws -> Date? {
        let attributes = try FileManager.default.attributesOfItem(atPath: self.path(name).path)
        return attributes[.creationDate] as? Date
    }

    func modificationDate(of name: String) throws -> Date? {
        let attributes = try FileManager.default.attributesOfItem(atPath: self.path(name).path)
        return attributes[.modificationDate] as? Date
    }

    /// Puts a timestamp on an item, for the tests that need a starting state the
    /// command then has to respect.
    func setTimestamps(of name: String, creation: Date? = nil, modification: Date? = nil) throws {
        var attributes: [FileAttributeKey: Any] = [:]

        if let creation {
            attributes[.creationDate] = creation
        }
        if let modification {
            attributes[.modificationDate] = modification
        }

        try FileManager.default.setAttributes(attributes, ofItemAtPath: self.path(name).path)
    }
}

// MARK: - Dates
/// Builds a UTC date, matching the zone `run(_:)` pins for the subprocess.
///
/// Separate from `makeDate(…)` in `TestingHelpers.swift`, which builds a local-time
/// date for the in-process suites. Mixing the two would produce expectations that
/// pass only in `Europe/Zurich`.
func makeUTCDate(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date? {
    var calendar = Calendar(identifier: .gregorian)
    guard let utc = TimeZone(identifier: "UTC") else {
        return nil
    }
    calendar.timeZone = utc

    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute

    return calendar.date(from: components)
}
