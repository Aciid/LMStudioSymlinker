// ProcessRunner.swift - Shared process execution utility

import Foundation

/// A lightweight utility for running external processes asynchronously.
///
/// Consolidates the duplicated `runCommand` helpers found across `DiskService`,
/// `SymlinkService`, `LaunchAgentService`, `LinuxDiskService`, and `SystemdUserService`.
public enum ProcessRunner {

    /// Runs an external command and returns its standard-output as a `String`,
    /// or `nil` when the process exits with a non-zero status or cannot be launched.
    ///
    /// The call is non-blocking with respect to the Swift cooperative thread pool:
    /// the actual `waitUntilExit()` is dispatched to a GCD background queue.
    ///
    /// - Parameters:
    ///   - command: Absolute path to the executable (e.g. `/usr/bin/du`).
    ///   - arguments: Command-line arguments.
    ///   - environment: Optional environment dictionary. When `nil` the current
    ///     process environment is inherited.
    ///   - mergeStderr: When `true` (the default) standard-error is merged into
    ///     the same pipe as standard-output. Set to `false` to discard stderr.
    /// - Returns: The UTF-8 standard-output string, or `nil` on failure.
    public static func run(
        _ command: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        mergeStderr: Bool = true
    ) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                let outPipe = Pipe()

                process.executableURL = URL(fileURLWithPath: command)
                process.arguments = arguments
                process.standardOutput = outPipe
                process.standardError = mergeStderr ? outPipe : Pipe()

                if let environment {
                    process.environment = environment
                }

                do {
                    try process.run()
                    let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()

                    if process.terminationStatus == 0 {
                        continuation.resume(returning: String(data: data, encoding: .utf8))
                    } else {
                        continuation.resume(returning: nil)
                    }
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Runs an external command and returns whether it exited successfully
    /// (termination status == 0).
    ///
    /// Standard output and error are discarded.
    ///
    /// - Parameters:
    ///   - command: Absolute path to the executable.
    ///   - arguments: Command-line arguments.
    /// - Returns: `true` when the process exits with status 0.
    public static func runForStatus(
        _ command: String,
        arguments: [String] = []
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: command)
                process.arguments = arguments
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus == 0)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    /// Runs an external command via `/usr/bin/env` lookup (useful on Linux where
    /// the command may not have a fixed absolute path).
    ///
    /// - Parameters:
    ///   - command: Command name or path resolved by `env`.
    ///   - arguments: Command-line arguments.
    /// - Returns: The UTF-8 standard-output string, or `nil` on failure.
    public static func runViaEnv(
        _ command: String,
        arguments: [String] = []
    ) async -> String? {
        await run("/usr/bin/env", arguments: [command] + arguments, mergeStderr: false)
    }
}
