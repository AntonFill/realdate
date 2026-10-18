//
//  RealDate.swift
//  RealDate
//
//  Created by Anton Fillmann on 07.06.2026.
//

import Foundation
import CommandLineOptions

@main
struct RealDate: Equatable {
    static let appname = "realdate"
    static let version = "1.4.0"

    /// The format with a time comes first: the date-only one also matches the start of a
    /// name that carries a time, and the time would be lost.
    static let defaultFormats = ["yyyy.MM.dd.HH.mm", "yyyy.MM.dd"]

    /// Date formats, tried in order.
    var format: [String] = RealDate.defaultFormats
    var recursive = false
    var verbose = false
    var rename = false
    var directories = false
    /// The file or directory to process.
    var path: String

    /// Whether anything failed along the way.
    ///
    /// A run over a tree does not stop at the first unreadable item, the same way
    /// `chmod -R` does not: the remaining items are still processed, and the failure
    /// surfaces once at the end as a non-zero exit code.
    var hadFailure = false

    mutating func run() throws {
        let dateFormatters = self.format.map { $0.customDateFormatter() }

        let fileManager = FileManager.default
        var isDir: ObjCBool = false

        // Checked before existence: a dangling link exists as a link, and reporting it
        // as a missing file would hide what it actually is.
        if fileManager.isSymbolicLink(atPath: self.path) {
            print("realdate: \(self.path): Skipping symbolic link")
            return
        }

        guard fileManager.fileExists(atPath: self.path, isDirectory: &isDir) else {
            printIf(true, "realdate: \(self.path): No such file or directory", to: .standardError)
            throw Failure()
        }

        if isDir.boolValue {
            self.processDirectory(self.path, dateFormatters: dateFormatters)
        } else {
            self.processFile(self.path, dateFormatters: dateFormatters)
        }

        if self.hadFailure {
            throw Failure()
        }
    }
}

// MARK: - Command line
extension RealDate {

    /// What a command line asks for.
    enum Invocation: Equatable {
        case help
        case version
        case run(RealDate)
    }

    /// A command line the command refuses before anything ran. It ends in exit code 64.
    struct UsageError: Error, Equatable, CustomStringConvertible {
        let description: String
    }

    /// The run did not get everything done. What went wrong is already on standard error,
    /// so this only carries the outcome to the exit code, which is 1.
    struct Failure: Error {}

    static let optionParser = OptionParser([
        .value("format"),
        .flag("recursive", short: "r"),
        .flag("verbose", short: "v"),
        .flag("rename"),
        .flag("directories", short: "d"),
        .flag("version"),
        .flag("help", short: "h"),
    ])

    /// Reads the arguments after the command's name.
    static func invocation(from arguments: [String]) throws -> Invocation {
        let parsed: ParsedArguments
        do {
            parsed = try Self.optionParser.parse(arguments)
        }
        catch {
            throw UsageError(description: "\(error)")
        }

        // Help and the version need nothing else on the line, not even a path.
        if parsed.isSet("help") {
            return .help
        }
        if parsed.isSet("version") {
            return .version
        }

        guard let path = parsed.operands.first else {
            throw UsageError(description: "missing path")
        }
        guard parsed.operands.count == 1 else {
            throw UsageError(description: "unexpected argument '\(parsed.operands[1])'")
        }

        // The empty format is the one that does damage, and it arrives by accident rather
        // than by intent: `--format "$FORMAT"` with an unset variable. A `DateFormatter`
        // with an empty format parses every name to its reference date, so a whole tree
        // gets dated to 2000-01-01 from a typo, and because nothing is trimmed off the
        // name, `--rename` leaves no visible trace either. This is the same rule as "no
        // date guessing", one step earlier: a format that matches everything is not a format.
        let formats = parsed.values(of: "format")
        guard formats.allSatisfy({ $0.isEmpty == false }) else {
            throw UsageError(description: "--format needs a date format, not an empty string.")
        }

        let command = RealDate(
            format: formats.isEmpty ? Self.defaultFormats : formats,
            recursive: parsed.isSet("recursive"),
            verbose: parsed.isSet("verbose"),
            rename: parsed.isSet("rename"),
            directories: parsed.isSet("directories"),
            path: path
        )
        return .run(command)
    }
}

// MARK: - Help
extension RealDate {

    /// What follows a usage error, the way `rm` and `cp` print theirs.
    static let usage = """
        usage: realdate [--format <format> ...] [--recursive] [--verbose] [--rename] [--directories] <path>
        See 'realdate --help' for more information.
        """

    /// Written by hand in the layout ArgumentParser generated up to 1.3.0. The `## Options`
    /// block in the README is a copy of what this prints.
    static let help = """
        OVERVIEW: Extract date from filename prefix, set file timestamps, and remove
        date from filename.

        USAGE: realdate [--format <format> ...] [--recursive] [--verbose] [--rename] [--directories] <path>

        ARGUMENTS:
          <path>                  Path to file(s) or directory.

        OPTIONS:
          --format <format>       Date custom format (e.g. dd-MM-yyyy, yyyy-MM-dd,
                                  yyyy-MM-dd-HH-mm). (default: yyyy.MM.dd.HH.mm,
                                  yyyy.MM.dd)
          -r, --recursive         Search recursively in subdirectories.
          -v, --verbose           Show detailed information.
          --rename                Set timestamps, and rename files.
          -d, --directories       Treat a directory itself as an item: set its
                                  timestamps, and rename it with --rename. Applies to
                                  the given directory, and to every visited
                                  subdirectory with -r.
          --version               Show the version.
          -h, --help              Show help information.

        """
}

// MARK: - Entry point
extension RealDate {

    static func main() {
        let invocation: Invocation
        do {
            invocation = try Self.invocation(from: Array(CommandLine.arguments.dropFirst()))
        }
        catch {
            // EX_USAGE, the code `rm` and `cp` exit with on a command line they cannot use.
            printIf(true, "realdate: \(error)", to: .standardError)
            printIf(true, Self.usage, to: .standardError)
            exit(EX_USAGE)
        }

        switch invocation {
        case .help:
            print(Self.help)
        case .version:
            print(Self.version)
        case .run(var command):
            do {
                try command.run()
            }
            catch {
                exit(EXIT_FAILURE)
            }
        }
    }
}

// MARK: -
extension RealDate {
        
    struct DateFilenameTuple {
        let date: Date
        let name: String
        /// Whether the matched format carried a time of day rather than a bare date.
        let hasTime: Bool
    }
}

extension RealDate {
    
    mutating func processDirectory(_ dirPath: String, dateFormatters: [DateFormatter]) {
        printIf(self.verbose, "realdate: Processing directory: \(dirPath)")

        do {
            let fileManager = FileManager.default
            
            // Get directory contents and sort them alphabetically
            let contents = try fileManager.contentsOfDirectory(atPath: dirPath)
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

            for item in contents {
                // Skip hidden files/directories
                if item.hasPrefix(".") {
                    printIf(self.verbose, "realdate: \(item): Skipping hidden item")
                    continue
                }

                let fullPath = (dirPath as NSString).appendingPathComponent(item)

                // Symbolic links are never followed: the timestamps would land on the link's
                // target, outside the given path, and a link cycle would recurse until the
                // path length runs out.
                if fileManager.isSymbolicLink(atPath: fullPath) {
                    printIf(self.verbose, "realdate: \(item): Skipping symbolic link")
                    continue
                }

                var isDir: ObjCBool = false

                guard fileManager.fileExists(atPath: fullPath, isDirectory: &isDir) else {
                    continue
                }

                if isDir.boolValue {
                    if self.recursive {
                        self.processDirectory(fullPath, dateFormatters: dateFormatters)
                    }
                    else {
                        printIf(self.verbose, "realdate: \(item): Skipping subdirectory (use -r for recursive)")
                    }
                }
                else {
                    self.processFile(fullPath, dateFormatters: dateFormatters)
                }
            }

            // The directory itself comes last: dating or renaming it before its contents
            // would be undone by every write inside it.
            if self.directories {
                self.applyDate(toItemAtPath: dirPath, dateFormatters: dateFormatters)
            }
        }
        catch {
            // Foundation's own text is unusable as CLI output: it names the item in
            // typographic quotes, it is localized, and it does not carry the path in this
            // tool's shape. So the reason stays behind -v and the line above it does not.
            printIf(true, "realdate: \(dirPath): cannot be read", to: .standardError)
            printIf(self.verbose, "realdate: \(dirPath): \(error.localizedDescription)", to: .standardError)
            self.hadFailure = true
        }
    }

    mutating func processFile(_ filePath: String, dateFormatters: [DateFormatter]) {
        let fileManager = FileManager.default
        var isDir: ObjCBool = false

        guard fileManager.fileExists(atPath: filePath, isDirectory: &isDir) else {
            printIf(self.verbose, "realdate: \(filePath): No such file or directory")
            return
        }

        // Skip directories
        if isDir.boolValue {
            printIf(self.verbose, "realdate: \(filePath): Expecting file, but is a directory. skipping")
            return
        }

        self.applyDate(toItemAtPath: filePath, dateFormatters: dateFormatters)
    }

    /// Sets the timestamps from the date in the item's name and, with `--rename`, strips the
    /// date prefix from it. Works for files and directories alike.
    mutating func applyDate(toItemAtPath itemPath: String, dateFormatters: [DateFormatter]) {
        let fileManager = FileManager.default
        let itemName = URL(fileURLWithPath: itemPath).lastPathComponent

        guard let tuple = self.parseDateFromFilename(itemName, dateFormatters: dateFormatters) else {
            printIf(self.verbose, "realdate: \(itemName): No date prefix found, skipping")
            return
        }

        do {
            let currentAttributes = try fileManager.attributesOfItem(atPath: itemPath)
            var attributes: [FileAttributeKey: Any] = [:]

            let keptTime = self.existingTimeToKeep(for: tuple, attributes: currentAttributes)
            let creationDate = keptTime ?? tuple.date
            if keptTime == nil {
                attributes[.creationDate] = creationDate
            }

            // The modification date is only lifted, never pulled back: an item edited after
            // the date in its name keeps the record of that edit. It is lifted to the creation
            // date the item ends up with rather than to the date in the name: APFS pulls a
            // creation date down to any earlier modification date it is given, so lifting only
            // as far as the name would undo a kept clock time (measured 2026-10-18).
            if let modified = currentAttributes[.modificationDate] as? Date, modified < creationDate {
                attributes[.modificationDate] = creationDate
            }

            if attributes.isEmpty == false {
                try fileManager.setAttributes(attributes, ofItemAtPath: itemPath)
            }

            let dateString: String
            if let keptTime {
                dateString = "already on \(DateFormatter.mediumDateShortTime.string(from: keptTime)), time kept"
            }
            else {
                dateString = "set to \(DateFormatter.mediumDateShortTime.string(from: tuple.date))"
            }

            guard self.rename else {
                printIf(self.verbose, "realdate: \(itemName): Date \(dateString) (filename unchanged)")
                return
            }

            // Rename item and set timestamps
            let itemURL = URL(fileURLWithPath: itemPath)
            let directory = itemURL.deletingLastPathComponent().path
            var newPath = (directory as NSString).appendingPathComponent(tuple.name)

            // Compared against the URL's path rather than against the string the caller
            // passed in: `itemPath` may be relative, while `newPath` was built from the
            // same URL and is therefore absolute. Comparing the two raw strings made an
            // item whose target name equals its current name look like a collision, so it
            // was moved to "<name> 2" instead of being left alone.
            if fileManager.fileExists(atPath: newPath) && newPath != itemURL.path {
                newPath = self.findAvailablePath(newPath)
                let newName = URL(fileURLWithPath: newPath).lastPathComponent
                printIf(self.verbose, "realdate: \(itemName): Duplicate found, renamed to \(newName)")
            }

            // Rename item
            try fileManager.moveItem(atPath: itemPath, toPath: newPath)

            let newName = URL(fileURLWithPath: newPath).lastPathComponent
            printIf(self.verbose, "realdate: \(itemName): Renamed to \(newName): Date \(dateString)")
        }
        catch {
            // Same reason as in processDirectory: the tool's own line first, Foundation's
            // localized one behind -v. Reading the attributes, writing them and the rename
            // all land here, which is why the message names no single operation.
            printIf(true, "realdate: \(itemName): cannot be updated", to: .standardError)
            printIf(self.verbose, "realdate: \(itemName): \(error.localizedDescription)", to: .standardError)
            self.hadFailure = true
        }
    }

    /// Returns the creation time that has to survive, if any.
    ///
    /// A date-only format always parses to midnight. That midnight is a product of the format,
    /// not a measurement, so it never replaces a real clock time that already sits on the same
    /// day. Renaming happens either way, only the timestamp is spared.
    func existingTimeToKeep(for tuple: DateFilenameTuple, attributes: [FileAttributeKey: Any]) -> Date? {
        guard tuple.hasTime == false else {
            return nil
        }
        guard let created = attributes[.creationDate] as? Date else {
            return nil
        }
        guard created.isSameDay(as: tuple.date) else {
            return nil
        }
        return created
    }

    func parseDateFromFilename(_ filename: String, dateFormatters: [DateFormatter]) -> DateFilenameTuple? {
        for formatter in dateFormatters {
            guard let date = formatter.date(fromFilename: filename) else {
                continue // next formatter.
            }
            let trimmingChars = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-_."))
            let realFilename = filename
                .dropFirst(formatter.dateFormat.count) // cut away date string.
                .drop(while: { char in
                    char.unicodeScalars.allSatisfy { trimmingChars.contains($0) } // trims left all chars from trimmingChars set.
                })
            
            guard realFilename.count > 0 else {
                return nil // if no name left, to much trimmed away. Cancels for this filename.
            }
            
            return DateFilenameTuple(date: date, name: String(realFilename), hasTime: formatter.hasTimeComponent)
        }
        return nil
    }

    func findAvailablePath(_ filePath: String) -> String {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: filePath) else {
            return filePath
        }

        let url = URL(fileURLWithPath: filePath)
        let dirPath = url.deletingLastPathComponent().path
        let filename = url.lastPathComponent
        let fileExtension = url.pathExtension
        let baseName = fileExtension.isEmpty ? filename : String(filename.dropLast(fileExtension.count + 1))

        var counter = 2
        while true {
            let newFilename = fileExtension.isEmpty ?
                "\(baseName) \(counter)" :
                "\(baseName) \(counter).\(fileExtension)"
            let newPath = (dirPath as NSString).appendingPathComponent(newFilename)

            if fileManager.fileExists(atPath: newPath) == false {
                return newPath
            }
            counter += 1
        }
    }
}

// MARK: - globals
/// Which stream a message goes to.
///
/// The split follows the file tools rather than this project's sibling mail2md, which
/// puts everything on stderr: `cp -v` and `mv -v` report the work they did on stdout,
/// and only failures go to stderr. So a log of what happened stays readable with
/// `realdate -v … | less`, while `2>/dev/null` still silences nothing but the errors.
enum MessageStream {
    case standardOutput
    case standardError
}

func printIf(_ condition: Bool, _ message: @autoclosure () -> String, to stream: MessageStream = .standardOutput) {
    guard condition else {
        return
    }

    switch stream {
    case .standardOutput:
        print(message())
    case .standardError:
        FileHandle.standardError.write(Data("\(message())\n".utf8))
    }
}

// MARK: - extensions
extension FileManager {

    /// `attributesOfItem` reports the link itself instead of its target, so a symbolic link
    /// can be told apart before anything follows it.
    func isSymbolicLink(atPath path: String) -> Bool {
        let attributes = try? self.attributesOfItem(atPath: path)
        return attributes?[.type] as? FileAttributeType == .typeSymbolicLink
    }
}

extension DateFormatter {
    
    static var mediumDateShortTime: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = TimeZone.current
        return formatter
    }
    
    /// Whether the format carries a time of day. A date-only format parses to midnight, which
    /// says nothing about the actual time an item was created.
    var hasTimeComponent: Bool {
        let timeSymbols = CharacterSet(charactersIn: "HhKkmsSa")
        return self.dateFormat.unicodeScalars.contains { scalar in
            timeSymbols.contains(scalar)
        }
    }

    func date(fromFilename filename: String) -> Date? {
        let dateLength = self.dateFormat.count
        let separators = CharacterSet(charactersIn: "-_: ")
        let dateString = String(filename.prefix(dateLength))
            .components(separatedBy: separators)
            .joined(separator: ".")
        return self.date(from: dateString)
    }
}

extension String {
    
    func customDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = self
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter
    }
}

extension Date {
    static let currentCalendar = Calendar.current
    
    func isSameDay(as otherDate: Date) -> Bool {
        Self.currentCalendar.isDate(self, inSameDayAs: otherDate)
    }
}
