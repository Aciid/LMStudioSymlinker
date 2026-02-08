// SymlinkService.swift - Shared symlink/copy logic (platform-agnostic)

import Foundation

public actor SymlinkService {
    private let fileManager = FileManager.default
    private let driveProvider: DriveProviding

    public init(driveProvider: DriveProviding) {
        self.driveProvider = driveProvider
    }

    public enum SymlinkError: LocalizedError, Sendable {
        case volumeNotMounted
        case sourceDoesNotExist(String)
        case pathIsRootOrEmpty(String)
        case copyFailed(String)
        case removeFailed(String)
        case symlinkFailed(String)
        case backupFailed(String)

        public var errorDescription: String? {
            switch self {
            case .volumeNotMounted:
                return "Target volume is not mounted"
            case .sourceDoesNotExist(let path):
                return "Source path does not exist: \(path)"
            case .pathIsRootOrEmpty(let path):
                return "Path is empty or root, refusing to operate: \(path)"
            case .copyFailed(let reason):
                return "Failed to copy files: \(reason)"
            case .removeFailed(let reason):
                return "Failed to remove files: \(reason)"
            case .symlinkFailed(let reason):
                return "Failed to create symlink: \(reason)"
            case .backupFailed(let reason):
                return "Failed to create backup: \(reason)"
            }
        }
    }

    // MARK: - Path Validation

    private func validatePathNotRootOrEmpty(_ path: String) throws {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "/" {
            throw SymlinkError.pathIsRootOrEmpty(path)
        }
    }

    // MARK: - Initialize (First-time Setup)

    public func initialize(
        volumePath: String,
        modelsSymlinkPath: String,
        hubSymlinkPath: String,
        progressHandler: @escaping @Sendable (String) -> Void
    ) async throws {
        try validatePathNotRootOrEmpty(modelsSymlinkPath)
        try validatePathNotRootOrEmpty(hubSymlinkPath)
        try validatePathNotRootOrEmpty(volumePath)

        let sourceModelsPath = volumePath + "/models"
        let sourceHubPath = volumePath + "/hub"

        guard fileManager.fileExists(atPath: volumePath) else {
            throw SymlinkError.volumeNotMounted
        }

        progressHandler("Checking existing paths...")

        let modelsPathType = await driveProvider.getPathType(for: modelsSymlinkPath)
        let hubPathType = await driveProvider.getPathType(for: hubSymlinkPath)

        try await handlePath(
            currentPathType: modelsPathType,
            symlinkPath: modelsSymlinkPath,
            sourcePath: sourceModelsPath,
            name: "models",
            progressHandler: progressHandler
        )

        try await handlePath(
            currentPathType: hubPathType,
            symlinkPath: hubSymlinkPath,
            sourcePath: sourceHubPath,
            name: "hub",
            progressHandler: progressHandler
        )

        progressHandler("Initialization complete!")
    }

    private func handlePath(
        currentPathType: PathType,
        symlinkPath: String,
        sourcePath: String,
        name: String,
        progressHandler: @escaping @Sendable (String) -> Void
    ) async throws {
        switch currentPathType {
        case .realDirectory:
            progressHandler("Copying \(name) to external drive...")
            try await copyDirectory(from: symlinkPath, to: sourcePath)
            progressHandler("Removing original \(name) directory...")
            try await removeDirectory(at: symlinkPath)
            progressHandler("Creating symlink for \(name)...")
            try createSymlink(from: symlinkPath, to: sourcePath)

        case .symlink(let target):
            if target == sourcePath {
                progressHandler("\(name) already linked to correct location")
            } else {
                progressHandler("Updating \(name) symlink...")
                try await removeSymlink(at: symlinkPath)
                try createSymlink(from: symlinkPath, to: sourcePath)
            }

        case .doesNotExist:
            if !fileManager.fileExists(atPath: sourcePath) {
                progressHandler("Creating \(name) directory on external drive...")
                try fileManager.createDirectory(atPath: sourcePath, withIntermediateDirectories: true)
            }
            progressHandler("Creating symlink for \(name)...")
            try createSymlink(from: symlinkPath, to: sourcePath)

        case .file:
            progressHandler("Warning: \(name) path is a file, backing up...")
            let backupPath = symlinkPath + ".backup.\(Int(Date().timeIntervalSince1970))"
            try fileManager.moveItem(atPath: symlinkPath, toPath: backupPath)
            if !fileManager.fileExists(atPath: sourcePath) {
                try fileManager.createDirectory(atPath: sourcePath, withIntermediateDirectories: true)
            }
            try createSymlink(from: symlinkPath, to: sourcePath)
        }
    }

    // MARK: - Copy Directory

    private func copyDirectory(from source: String, to destination: String) async throws {
        let rsyncPaths = ["/usr/bin/rsync", "/opt/homebrew/bin/rsync"]
        let rsyncPath = rsyncPaths.first { fileManager.fileExists(atPath: $0) }
        var copySucceeded = false

        if let rsyncPath = rsyncPath {
            if await runCommand(rsyncPath, arguments: ["-av", "--progress", source + "/", destination + "/"]) != nil {
                copySucceeded = true
            }
        }

        if !copySucceeded {
            let parentDir = (destination as NSString).deletingLastPathComponent
            if await runCommand("/bin/cp", arguments: ["-r", source, parentDir]) != nil {
                copySucceeded = true
            }
        }

        if !copySucceeded {
            do {
                if fileManager.fileExists(atPath: destination) {
                    try fileManager.removeItem(atPath: destination)
                }
                try fileManager.copyItem(atPath: source, toPath: destination)
            } catch {
                throw SymlinkError.copyFailed(error.localizedDescription)
            }
        }
    }

    // MARK: - Remove Operations

    private func removeDirectory(at path: String) async throws {
        try validatePathNotRootOrEmpty(path)
        do {
            try fileManager.removeItem(atPath: path)
        } catch {
            throw SymlinkError.removeFailed(error.localizedDescription)
        }
    }

    private func removeSymlink(at path: String) async throws {
        try validatePathNotRootOrEmpty(path)
        do {
            try fileManager.removeItem(atPath: path)
        } catch {
            throw SymlinkError.removeFailed(error.localizedDescription)
        }
    }

    // MARK: - Symlink Operations

    private func createSymlink(from symlinkPath: String, to targetPath: String) throws {
        let parentDir = (symlinkPath as NSString).deletingLastPathComponent
        if !fileManager.fileExists(atPath: parentDir) {
            try fileManager.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
        }
        do {
            try fileManager.createSymbolicLink(atPath: symlinkPath, withDestinationPath: targetPath)
        } catch {
            throw SymlinkError.symlinkFailed(error.localizedDescription)
        }
    }

    // MARK: - Volume Mount/Unmount Handling

    public func handleVolumeMount(
        volumeUUID: String,
        modelsSymlinkPath: String,
        hubSymlinkPath: String
    ) async throws {
        guard let volumePath = await driveProvider.getVolumePath(for: volumeUUID) else {
            throw SymlinkError.volumeNotMounted
        }

        let sourceModelsPath = volumePath + "/models"
        let sourceHubPath = volumePath + "/hub"

        await removeOldSymlinkIfNeeded(at: modelsSymlinkPath, expectedTarget: sourceModelsPath)
        await removeOldSymlinkIfNeeded(at: hubSymlinkPath, expectedTarget: sourceHubPath)

        if fileManager.fileExists(atPath: sourceModelsPath) {
            try? createSymlink(from: modelsSymlinkPath, to: sourceModelsPath)
        }
        if fileManager.fileExists(atPath: sourceHubPath) {
            try? createSymlink(from: hubSymlinkPath, to: sourceHubPath)
        }
    }

    public func handleVolumeUnmount(
        modelsSymlinkPath: String,
        hubSymlinkPath: String
    ) async {
        await handleBrokenSymlink(at: modelsSymlinkPath)
        await handleBrokenSymlink(at: hubSymlinkPath)
    }

    private func removeOldSymlinkIfNeeded(at path: String, expectedTarget: String) async {
        let pathType = await driveProvider.getPathType(for: path)
        switch pathType {
        case .symlink(let target):
            if target != expectedTarget {
                try? fileManager.removeItem(atPath: path)
            }
        case .realDirectory:
            let backupPath = path + ".backup.\(Int(Date().timeIntervalSince1970))"
            try? fileManager.moveItem(atPath: path, toPath: backupPath)
        default:
            break
        }
    }

    private func handleBrokenSymlink(at path: String) async {
        let pathType = await driveProvider.getPathType(for: path)
        if case .symlink = pathType {
            var isDirectory: ObjCBool = false
            if !fileManager.fileExists(atPath: path, isDirectory: &isDirectory) {
                try? fileManager.removeItem(atPath: path)
                try? fileManager.createDirectory(atPath: path, withIntermediateDirectories: true)
            }
        }
    }

    // MARK: - Shell Command Helper

    private func runCommand(_ command: String, arguments: [String]) async -> String? {
        await withCheckedContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = pipe
            var env = ProcessInfo.processInfo.environment
            let pathEnv = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
            if !pathEnv.contains("/usr/bin") {
                env["PATH"] = "/usr/bin:/bin:" + pathEnv
            }
            process.environment = env
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)
                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(returning: nil)
                }
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
}
