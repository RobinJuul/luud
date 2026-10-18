import AppKit
import Foundation

struct ShellResult: Sendable {
    let status: Int32
    let output: String

    var succeeded: Bool { status == 0 }
    /// osascript reports error -128 when the user dismisses the password prompt.
    var wasCancelled: Bool { output.contains("-128") }
}

enum Shell {
    @discardableResult
    static func run(_ executable: String, _ arguments: [String]) -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return ShellResult(status: -1, output: error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ShellResult(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    }

    /// Runs a shell command as root after the standard macOS administrator password prompt.
    static func runAsAdmin(_ command: String) -> ShellResult {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return run("/usr/bin/osascript", ["-e", "do shell script \"\(escaped)\" with administrator privileges"])
    }

    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

enum SystemSettings {
    static func openFullDiskAccess() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
    }

    static func openLoginItems() {
        open("x-apple.systempreferences:com.apple.LoginItems-Settings.extension")
    }

    private static func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}

extension URL {
    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([self])
    }
}

extension NSWorkspace {
    /// Moves items to the Trash. Wraps the completion-handler API so it stays on the main actor.
    @MainActor
    func moveToTrash(_ urls: [URL]) async throws -> [URL: URL] {
        try await withCheckedThrowingContinuation { continuation in
            recycle(urls) { moved, error in
                if let error, moved.isEmpty {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: moved)
                }
            }
        }
    }
}
