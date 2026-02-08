// DriveProviding.swift - Abstract drive/volume and path operations

import Foundation

public protocol DriveProviding: Sendable {
    var lmStudioBasePath: String { get }
    var modelsSymlinkPath: String { get }
    var hubSymlinkPath: String { get }

    func getExternalDrives() async throws -> [DriveInfo]
    func getDriveInfo(for volumePath: String) async -> DriveInfo?
    func getStorageUsage(for path: String) async -> String?
    func getVolumeStorageInfo(for volumePath: String) async -> StorageInfo?
    func getPathType(for path: String) async -> PathType
    func getVolumePath(for uuid: String) async -> String?
    func getSymlinkStatus() async -> SymlinkStatus
    func lmStudioModelsExist() async -> Bool
    func lmStudioHubExists() async -> Bool
}

