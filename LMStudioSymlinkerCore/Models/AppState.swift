// AppState.swift - Shared models

import Foundation

public enum InitializationState: Equatable, Sendable {
    case uninitialized
    case initialized
    case error(String)
}

public enum PathType: Equatable, Sendable {
    case symlink(target: String)
    case realDirectory
    case file
    case doesNotExist
}

public struct DriveInfo: Equatable, Sendable {
    public let path: String
    public let name: String
    public let uuid: String
    public let isExternal: Bool
    public let isRemovable: Bool

    public var volumePath: String { path }

    public init(path: String, name: String, uuid: String, isExternal: Bool, isRemovable: Bool) {
        self.path = path
        self.name = name
        self.uuid = uuid
        self.isExternal = isExternal
        self.isRemovable = isRemovable
    }
}

public struct StorageInfo: Equatable, Sendable {
    public let totalSize: String
    public let usedSize: String
    public let availableSize: String

    public init(totalSize: String, usedSize: String, availableSize: String) {
        self.totalSize = totalSize
        self.usedSize = usedSize
        self.availableSize = availableSize
    }
}

public struct SymlinkStatus: Equatable, Sendable {
    public let modelsPathType: PathType
    public let hubPathType: PathType

    public init(modelsPathType: PathType, hubPathType: PathType) {
        self.modelsPathType = modelsPathType
        self.hubPathType = hubPathType
    }
}

public struct AppConfiguration: Codable, Equatable, Sendable {
    public var externalDrivePath: String?
    public var externalDriveUUID: String?
    public var externalDriveName: String?
    public var isInitialized: Bool

    public init(externalDrivePath: String?, externalDriveUUID: String?, externalDriveName: String?, isInitialized: Bool) {
        self.externalDrivePath = externalDrivePath
        self.externalDriveUUID = externalDriveUUID
        self.externalDriveName = externalDriveName
        self.isInitialized = isInitialized
    }

    public static let `default` = AppConfiguration(
        externalDrivePath: nil,
        externalDriveUUID: nil,
        externalDriveName: nil,
        isInitialized: false
    )
}
