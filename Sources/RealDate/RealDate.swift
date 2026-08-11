//
//  RealDate.swift
//  RealDate
//
//  Created by Anton Fillmann on 07.06.2026.
//

import Foundation
import ArgumentParser

@main
struct RealDate: ParsableCommand {
    static let appname = "realdate"
    static let abstract = "Extract date from filename prefix, set file timestamps, and remove date from filename."
    static let version = "1.2.0"

    static let configuration = CommandConfiguration(
        commandName: Self.appname,
        abstract: Self.abstract,
        version: Self.version
    )

    @Option(name: .long, help: "Date custom format (e.g. dd-MM-yyyy, yyyy-MM-dd, yyyy-MM-dd-HH-mm).")
    var format: [String] = ["yyyy.MM.dd.HH.mm", "yyyy.MM.dd"] // Valid preset.

    @Flag(name: .shortAndLong, help: "Search recursively in subdirectories.")
    var recursive = false

    @Flag(name: .shortAndLong, help: "Show detailed information.")
    var verbose = false

    @Flag(name: .long, help: "Set timestamps, and rename files.")
    var rename = false

    @Flag(name: .shortAndLong, help: "Treat a directory itself as an item: set its timestamps, and rename it with --rename. Applies to the given directory, and to every visited subdirectory with -r.")
    var directories = false

    @Argument(help: "Path to file(s) or directory.")
    var path: String

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
            print("realdate: \(self.path): No such file or directory")
            return
        }

        if isDir.boolValue {
            self.processDirectory(self.path, dateFormatters: dateFormatters)
        } else {
            self.processFile(self.path, dateFormatters: dateFormatters)
        }
    }
}

// MARK: -
extension RealDate {
        
    struct DateFilenameTuple {
        let date: Date
        let name: String
    }
}

extension RealDate {
    
    func processDirectory(_ dirPath: String, dateFormatters: [DateFormatter]) {
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
            print("realdate: \(dirPath): \(error.localizedDescription)")
        }
    }

    func processFile(_ filePath: String, dateFormatters: [DateFormatter]) {
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
    func applyDate(toItemAtPath itemPath: String, dateFormatters: [DateFormatter]) {
        let fileManager = FileManager.default
        let itemName = URL(fileURLWithPath: itemPath).lastPathComponent

        guard let tuple = self.parseDateFromFilename(itemName, dateFormatters: dateFormatters) else {
            printIf(self.verbose, "realdate: \(itemName): No date prefix found, skipping")
            return
        }

        do {
            var attributes: [FileAttributeKey: Any] = [.creationDate: tuple.date]

            // The modification date is only lifted, never pulled back: an item edited after
            // the date in its name keeps the record of that edit.
            let currentAttributes = try fileManager.attributesOfItem(atPath: itemPath)
            if let modified = currentAttributes[.modificationDate] as? Date, modified < tuple.date {
                attributes[.modificationDate] = tuple.date
            }
            try fileManager.setAttributes(attributes, ofItemAtPath: itemPath)

            let dateString = DateFormatter.mediumDateShortTime.string(from: tuple.date)
            guard self.rename else {
                printIf(self.verbose, "realdate: \(itemName): Date set to \(dateString) (filename unchanged)")
                return
            }

            // Rename item and set timestamps
            let directory = URL(fileURLWithPath: itemPath).deletingLastPathComponent().path
            var newPath = (directory as NSString).appendingPathComponent(tuple.name)

            // Handle duplicates
            if fileManager.fileExists(atPath: newPath) && newPath != itemPath {
                newPath = self.findAvailablePath(newPath)
                let newName = URL(fileURLWithPath: newPath).lastPathComponent
                printIf(self.verbose, "realdate: \(itemName): Duplicate found, renamed to \(newName)")
            }

            // Rename item
            try fileManager.moveItem(atPath: itemPath, toPath: newPath)

            let newName = URL(fileURLWithPath: newPath).lastPathComponent
            printIf(self.verbose, "realdate: \(itemName): Renamed to \(newName): Date set to \(dateString)")
        }
        catch {
            print("realdate: \(itemName): \(error.localizedDescription)")
        }
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
            
            return DateFilenameTuple(date: date, name: String(realFilename))
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

            if !fileManager.fileExists(atPath: newPath) {
                return newPath
            }
            counter += 1
        }
    }
}

// MARK: - globals
func printIf(_ condition: Bool, _ message: @autoclosure () -> String) {
    if condition {
        print(message())
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
