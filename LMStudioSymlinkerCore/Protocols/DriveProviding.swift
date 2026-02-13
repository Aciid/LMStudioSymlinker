// DriveProviding.swift - Abstract drive/volume and path operations

import Foundation

/// Abstraction over platform-specific volume/drive and filesystem operations.
///
/// On macOS the implementation uses `diskutil` and `DiskArbitration`.
/// On Linux it parses `/proc/mounts`.
public protocol DriveProviding: Sendable {
    /// Base path of the LM Studio data directory (e.g. `~/.lmstudio`).
    var lmStudioBasePath: String { get }

    /// Path where the `models` symlink should live (e.g. `~/.lmstudio/models`).
    var modelsSymlinkPath: String { get }

    /// Path where the `hub` symlink should live (e.g. `~/.lmstudio/hub`).
    var hubSymlinkPath: String { get }

    /// Returns all detected external/removable drives.
    ///
    /// - Throws: If the underlying system query fails.
    func getExternalDrives() async throws -> [DriveInfo]

    /// Returns detailed drive information for a specific mount path,
    /// or `nil` if the path is not a valid mounted volume.
    func getDriveInfo(for volumePath: String) async -> DriveInfo?

    /// Returns a human-readable storage usage string (e.g. `"42G"`) for
    /// the given path, or `nil` if it cannot be determined.
    func getStorageUsage(for path: String) async -> String?

    /// Returns structured storage information (total, used, available)
    /// for the given volume path.
    func getVolumeStorageInfo(for volumePath: String) async -> StorageInfo?

    /// Determines the filesystem type of the given path (symlink, directory,
    /// file, or non-existent).
    func getPathType(for path: String) async -> PathType

    /// Resolves a volume UUID to its current mount path, or `nil` when the
    /// volume is not mounted.
    func getVolumePath(for uuid: String) async -> String?

    /// Returns the current symlink status for both the `models` and `hub` paths.
    func getSymlinkStatus() async -> SymlinkStatus

    /// Returns `true` when the LM Studio models directory exists on disk.
    func lmStudioModelsExist() async -> Bool

    /// Returns `true` when the LM Studio hub directory exists on disk.
    func lmStudioHubExists() async -> Bool
}
