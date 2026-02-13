// SystemServiceInstalling.swift - Abstract system service install (LaunchAgents vs systemd)

import Foundation

/// Manages installation and lifecycle of a platform-specific system service
/// that keeps LM Studio symlinks in sync across reboots and drive events.
///
/// On macOS the implementation uses LaunchAgents; on Linux it uses systemd
/// user units.
public protocol SystemServiceInstalling: Sendable {
    /// Installs and starts the system service for the given volume.
    ///
    /// - Parameters:
    ///   - volumeUUID: The UUID of the target external volume (used by the
    ///     generated script to verify mount status).
    ///   - volumePath: The expected mount path (e.g. `/Volumes/MyDrive`).
    /// - Throws: If script installation, plist/unit creation, or service
    ///   loading fails.
    func install(volumeUUID: String, volumePath: String) async throws

    /// Stops and removes the system service and associated scripts/logs.
    ///
    /// - Throws: If unloading or file removal fails.
    func uninstall() async throws

    /// Returns `true` when the service plist or unit file exists on disk.
    func isInstalled() async -> Bool

    /// Returns a dictionary of service component names to their running status.
    ///
    /// Keys are human-readable labels (e.g. `"Login"`, `"Disk Watch"`);
    /// values are `true` when the component is active.
    func getStatus() async -> [String: Bool]
}
