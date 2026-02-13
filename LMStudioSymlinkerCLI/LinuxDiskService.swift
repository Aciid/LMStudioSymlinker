#if os(Linux)
import Foundation
import LMStudioSymlinkerCore

/// DriveProviding implementation for Linux: parses /proc/mounts and lists mounts under /media, /run/media, /mnt.
public actor LinuxDiskService: DriveProviding {
    private let fileManager = FileManager.default

    public init() {}

    nonisolated public var lmStudioBasePath: String { PathHelper.lmStudioBasePath }
    nonisolated public var modelsSymlinkPath: String { PathHelper.modelsSymlinkPath }
    nonisolated public var hubSymlinkPath: String { PathHelper.hubSymlinkPath }

    public func getExternalDrives() async throws -> [DriveInfo] {
        let mounts = parseProcMounts()
        let mediaPaths = ["/media", "/run/media", "/mnt"]
        var drives: [DriveInfo] = []
        let home = PathHelper.homeDirectory
        let user = (home as NSString).lastPathComponent

        for mount in mounts {
            let path = mount.path
            guard mediaPaths.contains(where: { path.hasPrefix($0 + "/") }) || path == "/mnt" else { continue }
            if path == "/" || path.hasPrefix("/boot") || path.hasPrefix("/home") { continue }
            if path.hasPrefix("/media/") || path.hasPrefix("/run/media/") {
                let name = (path as NSString).lastPathComponent
                let uuid = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
                drives.append(DriveInfo(
                    path: path,
                    name: name,
                    uuid: uuid,
                    isExternal: true,
                    isRemovable: true
                ))
            } else if path.hasPrefix("/mnt/") {
                let name = (path as NSString).lastPathComponent
                drives.append(DriveInfo(
                    path: path,
                    name: name,
                    uuid: path,
                    isExternal: true,
                    isRemovable: true
                ))
            }
        }

        return drives
    }

    public func getDriveInfo(for volumePath: String) async -> DriveInfo? {
        guard fileManager.fileExists(atPath: volumePath) else { return nil }
        let name = (volumePath as NSString).lastPathComponent
        return DriveInfo(
            path: volumePath,
            name: name,
            uuid: volumePath,
            isExternal: true,
            isRemovable: true
        )
    }

    public func getStorageUsage(for path: String) async -> String? {
        await runCommand("/usr/bin/du", arguments: ["-sh", path]).flatMap { output in
            let parts = output.components(separatedBy: "\t")
            return parts.first?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    public func getVolumeStorageInfo(for volumePath: String) async -> StorageInfo? {
        var stat = statvfs()
        guard statvfs(volumePath, &stat) == 0 else { return nil }
        let blockSize = Int64(stat.f_frsize)
        let total = Int64(stat.f_blocks) * blockSize
        let free = Int64(stat.f_bavail) * blockSize
        let used = total - free
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return StorageInfo(
            totalSize: formatter.string(fromByteCount: total),
            usedSize: formatter.string(fromByteCount: used),
            availableSize: formatter.string(fromByteCount: free)
        )
    }

    public func getPathType(for path: String) async -> PathType {
        var isDirectory: ObjCBool = false
        if let attrs = try? fileManager.attributesOfItem(atPath: path),
           let type = attrs[.type] as? FileAttributeType,
           type == .typeSymbolicLink {
            if let target = try? fileManager.destinationOfSymbolicLink(atPath: path) {
                return .symlink(target: target)
            }
            return .symlink(target: "unknown")
        }
        if fileManager.fileExists(atPath: path, isDirectory: &isDirectory) {
            return isDirectory.boolValue ? .realDirectory : .file
        }
        return .doesNotExist
    }

    public func getVolumePath(for uuid: String) async -> String? {
        if fileManager.fileExists(atPath: uuid) {
            return uuid
        }
        return uuid.removingPercentEncoding
    }

    public func getSymlinkStatus() async -> SymlinkStatus {
        let models = await getPathType(for: modelsSymlinkPath)
        let hub = await getPathType(for: hubSymlinkPath)
        return SymlinkStatus(modelsPathType: models, hubPathType: hub)
    }

    public func lmStudioModelsExist() async -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: modelsSymlinkPath, isDirectory: &isDir) && isDir.boolValue
    }

    public func lmStudioHubExists() async -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: hubSymlinkPath, isDirectory: &isDir) && isDir.boolValue
    }

    private struct MountEntry {
        let path: String
    }

    private func parseProcMounts() -> [MountEntry] {
        guard let content = try? String(contentsOfFile: "/proc/mounts", encoding: .utf8) else { return [] }
        return content.components(separatedBy: "\n").compactMap { line in
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 2 else { return nil }
            let path = String(parts[1])
            return MountEntry(path: path)
        }
    }

    private func runCommand(_ command: String, arguments: [String]) async -> String? {
        await withCheckedContinuation { cont in
            let process = Process()
            let outPipe = Pipe()
            let errPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = arguments
            process.standardOutput = outPipe
            process.standardError = errPipe
            do {
                try process.run()
                process.waitUntilExit()
                let data = outPipe.fileHandleForReading.readDataToEndOfFile()
                cont.resume(returning: String(data: data, encoding: .utf8))
            } catch {
                cont.resume(returning: nil)
            }
        }
    }
}

/// SystemServiceInstalling for Linux: systemd user unit that runs a script to sync symlinks on startup and on mount.
public actor SystemdUserService: SystemServiceInstalling {
    private let fileManager = FileManager.default
    private let unitName = "lmstudio-symlinker.service"
    private let scriptName = "lmstudio-symlinker-sync.sh"

    private var configDir: URL {
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            return URL(fileURLWithPath: xdg)
        }
        return URL(fileURLWithPath: PathHelper.homeDirectory).appendingPathComponent(".config", isDirectory: true)
    }

    private var systemdUserDir: URL {
        configDir.appendingPathComponent("systemd/user", isDirectory: true)
    }

    private var stateDir: URL {
        if let xdg = ProcessInfo.processInfo.environment["XDG_STATE_HOME"], !xdg.isEmpty {
            return URL(fileURLWithPath: xdg).appendingPathComponent("lmstudio-symlinker", isDirectory: true)
        }
        return URL(fileURLWithPath: PathHelper.homeDirectory).appendingPathComponent(".local/state/lmstudio-symlinker", isDirectory: true)
    }

    private var scriptPath: String {
        stateDir.appendingPathComponent(scriptName).path
    }

    public init() {}

    public func install(volumeUUID: String, volumePath: String) async throws {
        try fileManager.createDirectory(at: systemdUserDir, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: stateDir, withIntermediateDirectories: true)

        let modelsPath = PathHelper.modelsSymlinkPath
        let hubPath = PathHelper.hubSymlinkPath
        let scriptContent = """
        #!/bin/bash
        # LM Studio Symlinker - sync symlinks when volume is mounted
        VOLUME="\(volumePath)"
        MODELS="\(modelsPath)"
        HUB="\(hubPath)"
        LOG="\(stateDir.path)/sync.log"
        if [ -d "$VOLUME" ]; then
          mkdir -p "$VOLUME/models" "$VOLUME/hub"
          rm -f "$MODELS" "$HUB"
          ln -sf "$VOLUME/models" "$MODELS"
          ln -sf "$VOLUME/hub" "$HUB"
          echo "$(date): Symlinks updated for $VOLUME" >> "$LOG"
        fi
        """
        try scriptContent.write(toFile: scriptPath, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath)

        let unitContent = """
        [Unit]
        Description=LM Studio Symlinker - keep symlinks in sync
        After=local-fs.target

        [Service]
        Type=oneshot
        ExecStart=\(scriptPath)
        RemainAfterExit=yes

        [Install]
        WantedBy=default.target
        """
        let unitURL = systemdUserDir.appendingPathComponent(unitName)
        try unitContent.write(to: unitURL, atomically: true, encoding: .utf8)

        _ = await runCommand("systemctl", arguments: ["--user", "daemon-reload"])
        _ = await runCommand("systemctl", arguments: ["--user", "enable", unitName])
        _ = await runCommand("systemctl", arguments: ["--user", "start", unitName])
    }

    public func uninstall() async throws {
        _ = await runCommand("systemctl", arguments: ["--user", "stop", unitName])
        _ = await runCommand("systemctl", arguments: ["--user", "disable", unitName])
        try? fileManager.removeItem(at: systemdUserDir.appendingPathComponent(unitName))
        try? fileManager.removeItem(atPath: scriptPath)
    }

    public func isInstalled() async -> Bool {
        fileManager.fileExists(atPath: systemdUserDir.appendingPathComponent(unitName).path)
    }

    public func getStatus() async -> [String: Bool] {
        let installed = await isInstalled()
        var status: [String: Bool] = ["Installed": installed]
        if installed {
            let active = await runCommand("systemctl", arguments: ["--user", "is-active", unitName])
            status["Active"] = active?.trimmingCharacters(in: .whitespacesAndNewlines) == "active"
        }
        return status
    }

    private func runCommand(_ command: String, arguments: [String]) async -> String? {
        await withCheckedContinuation { cont in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command] + arguments
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                cont.resume(returning: String(data: data, encoding: .utf8))
            } catch {
                cont.resume(returning: nil)
            }
        }
    }
}
#endif
