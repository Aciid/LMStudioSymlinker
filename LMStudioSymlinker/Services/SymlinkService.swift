// SymlinkService.swift

import Foundation

actor SymlinkService {
    static let shared = SymlinkService()

    private let fileManager = FileManager.default
    private let diskService = DiskService.shared

    enum SymlinkError: LocalizedError, Sendable {
        case volumeNotMounted
        case sourceDoesNotExist(String)
        case pathIsRootOrEmpty(String)
        case copyFailed(String)
        case removeFailed(String)
        case symlinkFailed(String)
        case backupFailed(String)

        var errorDescription: String? {
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

    func initialize(
        volumePath: String,
        modelsSymlinkPath: String,
        hubSymlinkPath: String,
        progressHandler: @escaping @Sendable (String) -> Void
    ) async throws {
        print("[SymlinkService] initialize() called")
        print("[SymlinkService]   volumePath: \(volumePath)")
        print("[SymlinkService]   modelsSymlinkPath: \(modelsSymlinkPath)")
        print("[SymlinkService]   hubSymlinkPath: \(hubSymlinkPath)")

        // Validate paths
        try validatePathNotRootOrEmpty(modelsSymlinkPath)
        try validatePathNotRootOrEmpty(hubSymlinkPath)
        try validatePathNotRootOrEmpty(volumePath)

        let sourceModelsPath = volumePath + "/models"
        let sourceHubPath = volumePath + "/hub"

        // Check if volume is accessible
        guard fileManager.fileExists(atPath: volumePath) else {
            print("[SymlinkService] initialize() ERROR: volume not mounted at \(volumePath)")
            throw SymlinkError.volumeNotMounted
        }

        progressHandler("Checking existing paths...")

        // Check current path types
        let modelsPathType = await diskService.getPathType(for: modelsSymlinkPath)
        let hubPathType = await diskService.getPathType(for: hubSymlinkPath)
        print("[SymlinkService]   modelsPathType: \(modelsPathType)")
        print("[SymlinkService]   hubPathType: \(hubPathType)")

        // Handle models path
        try await handlePath(
            currentPathType: modelsPathType,
            symlinkPath: modelsSymlinkPath,
            sourcePath: sourceModelsPath,
            name: "models",
            progressHandler: progressHandler
        )

        // Handle hub path
        try await handlePath(
            currentPathType: hubPathType,
            symlinkPath: hubSymlinkPath,
            sourcePath: sourceHubPath,
            name: "hub",
            progressHandler: progressHandler
        )

        print("[SymlinkService] initialize() completed successfully")
        progressHandler("Initialization complete!")
    }

    private func handlePath(
        currentPathType: PathType,
        symlinkPath: String,
        sourcePath: String,
        name: String,
        progressHandler: @escaping @Sendable (String) -> Void
    ) async throws {
        print("[SymlinkService] handlePath() called for '\(name)'")
        print("[SymlinkService]   currentPathType: \(currentPathType)")
        print("[SymlinkService]   symlinkPath: \(symlinkPath)")
        print("[SymlinkService]   sourcePath: \(sourcePath)")

        switch currentPathType {
        case .realDirectory:
            // Copy to external drive, then remove and create symlink
            print("[SymlinkService] handlePath(\(name)): real directory found, copying to external drive")
            progressHandler("Copying \(name) to external drive...")
            try await copyDirectory(from: symlinkPath, to: sourcePath)

            print("[SymlinkService] handlePath(\(name)): removing original directory")
            progressHandler("Removing original \(name) directory...")
            try await removeDirectory(at: symlinkPath)

            print("[SymlinkService] handlePath(\(name)): creating symlink")
            progressHandler("Creating symlink for \(name)...")
            try createSymlink(from: symlinkPath, to: sourcePath)

        case .symlink(let target):
            // Already a symlink, check if it points to the right place
            if target == sourcePath {
                print("[SymlinkService] handlePath(\(name)): symlink already points to correct target")
                progressHandler("\(name) already linked to correct location")
            } else {
                print("[SymlinkService] handlePath(\(name)): symlink points to '\(target)', updating to '\(sourcePath)'")
                progressHandler("Updating \(name) symlink...")
                try await removeSymlink(at: symlinkPath)
                try createSymlink(from: symlinkPath, to: sourcePath)
            }

        case .doesNotExist:
            print("[SymlinkService] handlePath(\(name)): path does not exist")
            // Create source directory on external drive if needed
            if !fileManager.fileExists(atPath: sourcePath) {
                print("[SymlinkService] handlePath(\(name)): creating source directory on external drive")
                progressHandler("Creating \(name) directory on external drive...")
                try fileManager.createDirectory(atPath: sourcePath, withIntermediateDirectories: true)
            }

            print("[SymlinkService] handlePath(\(name)): creating symlink")
            progressHandler("Creating symlink for \(name)...")
            try createSymlink(from: symlinkPath, to: sourcePath)

        case .file:
            // Unexpected: it's a file, not a directory
            print("[SymlinkService] handlePath(\(name)): WARNING - path is a file, backing up")
            progressHandler("Warning: \(name) path is a file, backing up...")
            let backupPath = symlinkPath + ".backup.\(Int(Date().timeIntervalSince1970))"
            print("[SymlinkService] handlePath(\(name)): backing up to \(backupPath)")
            try fileManager.moveItem(atPath: symlinkPath, toPath: backupPath)

            if !fileManager.fileExists(atPath: sourcePath) {
                try fileManager.createDirectory(atPath: sourcePath, withIntermediateDirectories: true)
            }
            try createSymlink(from: symlinkPath, to: sourcePath)
        }

        print("[SymlinkService] handlePath(\(name)): completed")
    }

    // MARK: - Copy Directory

    private func copyDirectory(from source: String, to destination: String) async throws {
        print("[SymlinkService] copyDirectory() called")
        print("[SymlinkService]   from: \(source)")
        print("[SymlinkService]   to: \(destination)")

        // Try rsync only if the binary exists (Apple removed /usr/bin/rsync on recent macOS)
        let rsyncPaths = ["/usr/bin/rsync", "/opt/homebrew/bin/rsync"]
        let rsyncPath = rsyncPaths.first { fileManager.fileExists(atPath: $0) }
        var copySucceeded = false

        if let rsyncPath = rsyncPath {
            print("[SymlinkService] copyDirectory(): attempting rsync at \(rsyncPath)")
            if await runCommand(rsyncPath, arguments: ["-av", "--progress", source + "/", destination + "/"]) != nil {
                copySucceeded = true
                print("[SymlinkService] copyDirectory(): rsync succeeded")
            } else {
                print("[SymlinkService] copyDirectory(): rsync failed, falling back to cp")
            }
        } else {
            print("[SymlinkService] copyDirectory(): rsync not found, using cp")
        }

        if !copySucceeded {
            let cpResult = await runCommand("/bin/cp", arguments: ["-r", source, (destination as NSString).deletingLastPathComponent])
            if cpResult != nil {
                copySucceeded = true
                print("[SymlinkService] copyDirectory(): cp succeeded")
            } else {
                print("[SymlinkService] copyDirectory(): cp failed, falling back to FileManager")
            }
        }

        if !copySucceeded {
            do {
                if fileManager.fileExists(atPath: destination) {
                    print("[SymlinkService] copyDirectory(): removing existing destination before copy")
                    try fileManager.removeItem(atPath: destination)
                }
                try fileManager.copyItem(atPath: source, toPath: destination)
                print("[SymlinkService] copyDirectory(): FileManager copy succeeded")
            } catch {
                print("[SymlinkService] copyDirectory() ERROR: \(error.localizedDescription)")
                throw SymlinkError.copyFailed(error.localizedDescription)
            }
        }
    }

    // MARK: - Remove Operations

    private func removeDirectory(at path: String) async throws {
        print("[SymlinkService] removeDirectory() called: \(path)")
        try validatePathNotRootOrEmpty(path)

        do {
            try fileManager.removeItem(atPath: path)
            print("[SymlinkService] removeDirectory(): successfully removed \(path)")
        } catch {
            print("[SymlinkService] removeDirectory() ERROR: \(error.localizedDescription)")
            throw SymlinkError.removeFailed(error.localizedDescription)
        }
    }

    private func removeSymlink(at path: String) async throws {
        print("[SymlinkService] removeSymlink() called: \(path)")
        try validatePathNotRootOrEmpty(path)

        do {
            try fileManager.removeItem(atPath: path)
            print("[SymlinkService] removeSymlink(): successfully removed \(path)")
        } catch {
            print("[SymlinkService] removeSymlink() ERROR: \(error.localizedDescription)")
            throw SymlinkError.removeFailed(error.localizedDescription)
        }
    }

    // MARK: - Symlink Operations

    private func createSymlink(from symlinkPath: String, to targetPath: String) throws {
        print("[SymlinkService] createSymlink() called")
        print("[SymlinkService]   symlinkPath: \(symlinkPath)")
        print("[SymlinkService]   targetPath: \(targetPath)")

        // Ensure parent directory exists
        let parentDir = (symlinkPath as NSString).deletingLastPathComponent
        if !fileManager.fileExists(atPath: parentDir) {
            print("[SymlinkService] createSymlink(): creating parent directory \(parentDir)")
            try fileManager.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
        }

        do {
            try fileManager.createSymbolicLink(atPath: symlinkPath, withDestinationPath: targetPath)
            print("[SymlinkService] createSymlink(): successfully created symlink \(symlinkPath) -> \(targetPath)")
        } catch {
            print("[SymlinkService] createSymlink() ERROR: \(error.localizedDescription)")
            throw SymlinkError.symlinkFailed(error.localizedDescription)
        }
    }

    // MARK: - Volume Mount/Unmount Handling

    func handleVolumeMount(
        volumeUUID: String,
        modelsSymlinkPath: String,
        hubSymlinkPath: String
    ) async throws {
        print("[SymlinkService] handleVolumeMount() called")
        print("[SymlinkService]   volumeUUID: \(volumeUUID)")
        print("[SymlinkService]   modelsSymlinkPath: \(modelsSymlinkPath)")
        print("[SymlinkService]   hubSymlinkPath: \(hubSymlinkPath)")

        guard let volumePath = await diskService.getVolumePath(for: volumeUUID) else {
            print("[SymlinkService] handleVolumeMount() ERROR: volume not mounted for UUID \(volumeUUID)")
            throw SymlinkError.volumeNotMounted
        }

        print("[SymlinkService] handleVolumeMount(): resolved volume path: \(volumePath)")

        let sourceModelsPath = volumePath + "/models"
        let sourceHubPath = volumePath + "/hub"

        // Remove old symlinks if they exist and point elsewhere
        await removeOldSymlinkIfNeeded(at: modelsSymlinkPath, expectedTarget: sourceModelsPath)
        await removeOldSymlinkIfNeeded(at: hubSymlinkPath, expectedTarget: sourceHubPath)

        // Create symlinks
        if fileManager.fileExists(atPath: sourceModelsPath) {
            print("[SymlinkService] handleVolumeMount(): creating models symlink")
            try? createSymlink(from: modelsSymlinkPath, to: sourceModelsPath)
        } else {
            print("[SymlinkService] handleVolumeMount(): models source path does not exist, skipping")
        }

        if fileManager.fileExists(atPath: sourceHubPath) {
            print("[SymlinkService] handleVolumeMount(): creating hub symlink")
            try? createSymlink(from: hubSymlinkPath, to: sourceHubPath)
        } else {
            print("[SymlinkService] handleVolumeMount(): hub source path does not exist, skipping")
        }

        print("[SymlinkService] handleVolumeMount() completed")
    }

    func handleVolumeUnmount(
        modelsSymlinkPath: String,
        hubSymlinkPath: String
    ) async {
        print("[SymlinkService] handleVolumeUnmount() called")
        print("[SymlinkService]   modelsSymlinkPath: \(modelsSymlinkPath)")
        print("[SymlinkService]   hubSymlinkPath: \(hubSymlinkPath)")

        // Remove broken symlinks and optionally create placeholder directories
        await handleBrokenSymlink(at: modelsSymlinkPath)
        await handleBrokenSymlink(at: hubSymlinkPath)

        print("[SymlinkService] handleVolumeUnmount() completed")
    }

    private func removeOldSymlinkIfNeeded(at path: String, expectedTarget: String) async {
        print("[SymlinkService] removeOldSymlinkIfNeeded() called: \(path), expectedTarget: \(expectedTarget)")
        let pathType = await diskService.getPathType(for: path)
        print("[SymlinkService] removeOldSymlinkIfNeeded(): pathType = \(pathType)")

        switch pathType {
        case .symlink(let target):
            if target != expectedTarget {
                print("[SymlinkService] removeOldSymlinkIfNeeded(): symlink points to '\(target)', removing")
                try? fileManager.removeItem(atPath: path)
            } else {
                print("[SymlinkService] removeOldSymlinkIfNeeded(): symlink already correct, no action needed")
            }
        case .realDirectory:
            // Backup existing directory
            let backupPath = path + ".backup.\(Int(Date().timeIntervalSince1970))"
            print("[SymlinkService] removeOldSymlinkIfNeeded(): real directory found, backing up to \(backupPath)")
            try? fileManager.moveItem(atPath: path, toPath: backupPath)
        default:
            print("[SymlinkService] removeOldSymlinkIfNeeded(): no action needed (pathType: \(pathType))")
            break
        }
    }

    private func handleBrokenSymlink(at path: String) async {
        print("[SymlinkService] handleBrokenSymlink() called: \(path)")
        let pathType = await diskService.getPathType(for: path)
        print("[SymlinkService] handleBrokenSymlink(): pathType = \(pathType)")

        if case .symlink = pathType {
            // Check if symlink target is accessible
            var isDirectory: ObjCBool = false
            if !fileManager.fileExists(atPath: path, isDirectory: &isDirectory) {
                // Symlink is broken, remove it and create placeholder
                print("[SymlinkService] handleBrokenSymlink(): symlink is broken, removing and creating placeholder directory")
                try? fileManager.removeItem(atPath: path)
                try? fileManager.createDirectory(atPath: path, withIntermediateDirectories: true)
            } else {
                print("[SymlinkService] handleBrokenSymlink(): symlink target is accessible, no action needed")
            }
        } else {
            print("[SymlinkService] handleBrokenSymlink(): not a symlink, no action needed")
        }
    }

    // MARK: - Shell Command Helper

    private func runCommand(_ command: String, arguments: [String]) async -> String? {
        print("[SymlinkService] runCommand() called: \(command) \(arguments.joined(separator: " "))")

        return await withCheckedContinuation { continuation in
            let process = Process()
            let pipe = Pipe()

            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = pipe
            // Ensure PATH includes /usr/bin and /bin so subprocesses (e.g. rsync exec) can find binaries
            var env = ProcessInfo.processInfo.environment
            let path = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
            if !path.contains("/usr/bin") {
                env["PATH"] = "/usr/bin:/bin:" + path
            }
            process.environment = env

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)

                if process.terminationStatus == 0 {
                    print("[SymlinkService] runCommand(): succeeded (exit code 0)")
                    continuation.resume(returning: output)
                } else {
                    print("[SymlinkService] runCommand(): failed (exit code \(process.terminationStatus))")
                    if let output = output {
                        print("[SymlinkService] runCommand(): output: \(output)")
                    }
                    continuation.resume(returning: nil)
                }
            } catch {
                print("[SymlinkService] runCommand() ERROR: \(error.localizedDescription)")
                continuation.resume(returning: nil)
            }
        }
    }
}
