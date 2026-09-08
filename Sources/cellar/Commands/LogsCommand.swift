import ArgumentParser
import CellarKit
import Foundation

struct LogsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "logs",
        abstract: "Show what Cellar has been doing — set-ups, launches, crashes — and package it up to send.",
        discussion: """
        Cellar keeps a rolling record of every set-up, launch, play session and failure, from both
        the app and this CLI. It is capped at about 1.5 MB, so it never grows without bound.

          cellar logs                      the last 40 entries
          cellar logs --level warn         only warnings and errors
          cellar logs --game diablo-4      only one game
          cellar logs export               one text file to attach to a bug report

        Set CELLAR_LOG_LEVEL=off to stop writing it, or =info to leave out the debug detail.
        """,
        subcommands: [Show.self, Path.self, Export.self, Clear.self],
        defaultSubcommand: Show.self
    )
}

// MARK: - show

extension LogsCommand {
    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "show",
            abstract: "Print the most recent entries.")

        @Option(name: .shortAndLong, help: "How many entries to show.")
        var lines: Int = 40

        @Option(name: .long, help: "Lowest level to show: debug, info, warn or error.")
        var level: String = "debug"

        @Option(name: .long, help: "Only entries about one game, by profile slug.")
        var game: String?

        @Flag(name: .long, help: "Print the raw file lines instead of the formatted view.")
        var raw = false

        func run() throws {
            guard let minimum = LogLevel(rawValue: level.lowercased()) else {
                throw CellarError.invalidArgument(
                    "'\(level)' isn't a level. Use one of: debug, info, warn, error.")
            }
            let entries = CellarLog.entries(limit: lines, minimumLevel: minimum, subject: game)

            guard !entries.isEmpty else {
                print(Term.dim("Nothing logged yet\(game.map { " for \($0)" } ?? "")."))
                print("Cellar writes here whenever it sets a game up, launches one, or hits a problem.")
                print(Term.dim("File: \(CellarLog.fileURL.path)"))
                return
            }

            var day = ""
            for entry in entries {
                let today = Self.dayFormatter.string(from: entry.date)
                if today != day {
                    day = today
                    print(Term.dim("— \(day) —"))
                }
                print(raw ? entry.line : format(entry))
            }
            print("")
            print(Term.dim("\(entries.count) entries · \(CellarLog.fileURL.path) · "
                + "package it up with: cellar logs export"))
        }

        /// Level is carried by a mark *and* a word, so it survives a pipe and a colour-blind reader.
        private func format(_ entry: LogEntry) -> String {
            let time = Self.timeFormatter.string(from: entry.date)
            let tag = "\(entry.level.symbol) \(entry.level.rawValue)"
                .padding(toLength: 8, withPad: " ", startingAt: 0)
            let where_ = [entry.category.rawValue, entry.subject].compactMap { $0 }.joined(separator: "/")
                .padding(toLength: 24, withPad: " ", startingAt: 0)
            let head = "\(Term.dim(time))  \(tag) \(Term.dim(where_))  "
            switch entry.level {
            case .error: return head + Term.red(entry.message)
            case .warn:  return head + Term.yellow(entry.message)
            case .info:  return head + entry.message
            case .debug: return head + Term.dim(entry.message)
            }
        }

        private static let timeFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            return formatter
        }()

        private static let dayFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE d MMMM"
            return formatter
        }()
    }
}

// MARK: - path

extension LogsCommand {
    struct Path: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "path",
            abstract: "Print where the logs live.")

        func run() throws {
            print(CellarLog.fileURL.path)
            for file in CellarLog.files.dropLast() { print(Term.dim(file.path)) }
            for file in Diagnostics.wineLogs(limit: 8) { print(Term.dim(file.path)) }
        }
    }
}

// MARK: - export

extension LogsCommand {
    struct Export: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "export",
            abstract: "Write one text file with the log, your Mac's details and the Wine output — ready to attach to a bug report.")

        @Option(name: .shortAndLong, help: "Where to write it. Defaults to your Desktop.")
        var output: String?

        func run() throws {
            let destination = output.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            let url = try Diagnostics.exportReport(to: destination)
            let size = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int) ?? 0

            print(Term.green("Wrote \(url.path)") + Term.dim(" (\(size / 1024) KB)"))
            print("It holds your Mac's details, the installed runners and bottles, Cellar's event log")
            print("and the tail of each Wine log. Account names, your home path and anything")
            print("token-shaped are removed — but read it before you post it.")
            print(Term.dim("Attach it to an issue at https://github.com/Echarnus/Cellar/issues"))
        }
    }
}

// MARK: - clear

extension LogsCommand {
    struct Clear: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "clear",
            abstract: "Delete the kept history and start a fresh log.")

        func run() throws {
            let kept = CellarLog.files.count
            CellarLog.clear()
            print("Cleared \(kept) log file(s). Cellar starts a new one on the next thing it does.")
        }
    }
}
