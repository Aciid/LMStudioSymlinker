#if os(Linux)
import Foundation
import Glibc
import LMStudioSymlinkerCore

/// DriveProviding implementation for Linux: parses /proc/mounts and lists mounts under /media, /run/media, /mnt.
public final class LinuxDiskService: DriveProviding, @unchecked Sendable {
    private let fileManager = FileManager.default

    public init() {}

    public var lmStudioBasePath: String { PathHelper.lmStudioBasePath }
    public var modelsSymlinkPath: String { PathHelper.modelsSymlinkPath }
    public var hubSymlinkPath: String { PathHelper.hubSymlinkPath }

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
#endif
