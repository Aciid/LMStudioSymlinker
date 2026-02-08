// AppState.swift

import Foundation

enum InitializationState: Equatable, Sendable {
    case uninitialized
    case initialized
    case error(String)
}

enum PathType: Equatable, Sendable {
    case symlink(target: String)
    case realDirectory
    case file
    case doesNotExist
}

struct DriveInfo: Equatable, Sendable {
    let path: String
    let name: String
    let uuid: String
    let isExternal: Bool
    let isRemovable: Bool

    var volumePath: String {
        path
    }
}

struct StorageInfo: Equatable, Sendable {
    let totalSize: String
    let usedSize: String
    let availableSize: String
}

struct SymlinkStatus: Equatable, Sendable {
    let modelsPathType: PathType
    let hubPathType: PathType
}

struct AppConfiguration: Codable, Equatable, Sendable {
    var externalDrivePath: String?
    var externalDriveUUID: String?
    var externalDriveName: String?
    var isInitialized: Bool

    static let `default` = AppConfiguration(
        externalDrivePath: nil,
        externalDriveUUID: nil,
        externalDriveName: nil,
        isInitialized: false
    )
}
