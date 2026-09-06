import Foundation
import os

/// Central `os.Logger` categories for the app.
///
/// Replaces `print`: unified logging is off the hot path, is filterable by
/// category in Console.app, and — unlike `print` — costs nothing in release
/// builds when the level is disabled.
///
/// Technical diagnostics are interpolated with `privacy: .public` at the call
/// site so they stay readable in Console; nothing logged here contains user
/// content (no captured words, images, or coordinates).
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "WordHunter"

    /// Scanner lifecycle and the capture pipeline.
    static let scan = Logger(subsystem: subsystem, category: "scan")

    /// SQLite lexicon loading and queries.
    static let lexicon = Logger(subsystem: subsystem, category: "lexicon")

    /// Collection export and import.
    static let transfer = Logger(subsystem: subsystem, category: "transfer")

    /// Achievement presentation (audio, haptics).
    static let achievements = Logger(subsystem: subsystem, category: "achievements")

    /// Asset loading, font registration, and other UI resources.
    static let assets = Logger(subsystem: subsystem, category: "assets")

    /// Startup and progress timing instrumentation.
    static let boot = Logger(subsystem: subsystem, category: "boot")
}
