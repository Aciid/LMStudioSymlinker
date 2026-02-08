// DiskService.swift

import Foundation
import DiskArbitration

actor DiskService {
    static let shared = DiskService()

    private let fileManager = FileManager.default

    // MARK: - LM Studio Paths

    nonisolated var lmStudioBasePath: String {
        NSHomeDirectory() + "/.lmstudio"
    }

    nonisolated var modelsSymlinkPath: String {
        lmStudioBasePath + "/models"
    }

    nonisolated var hubSymlinkPath: String {
        lmStudioBasePath + "/hub"
    }

    // MARK: - Volume Detection

    func getExternalDrives() async throws -> [DriveInfo] {
        var drives: [DriveInfo] = []
        let volumesPath = "/Volumes"

        guard let contents = try? fileManager.contentsOfDirectory(atPath: volumesPath) else {
            return drives
        }

        for volumeName in contents {
            let volumePath = "\(volumesPath)/\(volumeName)"

            // Skip system volumes
            if isSystemVolume(volumeName: volumeName, volumePath: volumePath) {
                continue
            }

            // Check if it's an external/removable drive
            guard let driveInfo = await getDriveInfo(for: volumePath) else {
                continue
            }

            if driveInfo.isExternal || driveInfo.isRemovable {
                drives.append(driveInfo)
            }
        }

        return drives
    }

    private func isSystemVolume(volumeName: String, volumePath: String) -> Bool {
        // Skip Macintosh HD and system volumes
        let systemVolumeNames = [
            "Macintosh HD",
            "Macintosh HD - Data",
            "macintosh hd",
            "macintosh hd - data"
        ]

        if systemVolumeNames.contains(volumeName.lowercased()) ||
           systemVolumeNames.contains(volumeName) {
            return true
        }

        // Check if it's the boot volume
        if volumePath == "/" {
            return true
        }

        // Get the boot volume path and compare
        let bootVolumePath = getBootVolumePath()
        if volumePath == bootVolumePath {
            return true
        }

        return false
    }

    private func getBootVolumePath() -> String {
        // The root filesystem on macOS
        var statfsResult = statfs()
        if statfs("/", &statfsResult) == 0 {
            let mountPoint = withUnsafePointer(to: &statfsResult.f_mntonname) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                    String(cString: $0)
                }
            }
            return mountPoint
        }
        return "/System/Volumes/Data"
    }

    func getDriveInfo(for volumePath: String) async -> DriveInfo? {
        // Get disk info using diskutil
        let output = await runCommand("/usr/sbin/diskutil", arguments: ["info", volumePath])
        guard let output else { return nil }

        var uuid = ""
        var volumeName = ""
        var isExternal = false
        var isRemovable = false
        var isDMG = false

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("Volume UUID:") {
                uuid = trimmed.replacingOccurrences(of: "Volume UUID:", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("Volume Name:") {
                volumeName = trimmed.replacingOccurrences(of: "Volume Name:", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("Removable Media:") {
                isRemovable = trimmed.lowercased().contains("removable")
            } else if trimmed.hasPrefix("Protocol:") {
                let protocol_ = trimmed.lowercased()
                isExternal = protocol_.contains("usb") ||
                             protocol_.contains("thunderbolt") ||
                             protocol_.contains("firewire") ||
                             protocol_.contains("sata") && !protocol_.contains("internal")
            } else if trimmed.hasPrefix("Virtual:") {
                isDMG = trimmed.lowercased().contains("yes")
            } else if trimmed.hasPrefix("Disk Image:") {
                isDMG = trimmed.lowercased().contains("yes")
            }
        }

        // Skip DMG files
        if isDMG {
            return nil
        }

        // Additional check: verify it's not a disk image by checking mount point
        if volumePath.contains(".dmg") || volumePath.contains(".sparseimage") {
            return nil
        }

        // If we couldn't determine external status from protocol, check device location
        if !isExternal {
            isExternal = await checkIfExternalByDeviceInfo(volumePath: volumePath, diskutilOutput: output)
        }

        if volumeName.isEmpty {
            volumeName = (volumePath as NSString).lastPathComponent
        }

        return DriveInfo(
            path: volumePath,
            name: volumeName,
            uuid: uuid,
            isExternal: isExternal,
            isRemovable: isRemovable
        )
    }

    private func checkIfExternalByDeviceInfo(volumePath: String, diskutilOutput: String) async -> Bool {
        // Check for external indicators in diskutil output
        let lowerOutput = diskutilOutput.lowercased()

        // Check device location and bus
        if lowerOutput.contains("external") {
            return true
        }

        // Check if it's USB or Thunderbolt connected
        if lowerOutput.contains("usb") || lowerOutput.contains("thunderbolt") {
            return true
        }

        // Check ejectable status as a hint
        if lowerOutput.contains("ejectable: yes") {
            return true
        }

        return false
    }

    func getVolumeUUID(for volumePath: String) async -> String? {
        let output = await runCommand("/usr/sbin/diskutil", arguments: ["info", volumePath])
        guard let output else { return nil }

        for line in output.components(separatedBy: "\n") {
            if line.contains("Volume UUID:") {
                let parts = line.components(separatedBy: ":")
                if parts.count >= 2 {
                    return parts[1].trimmingCharacters(in: .whitespaces)
                }
            }
        }

        return nil
    }

    func isVolumeMounted(uuid: String) async -> Bool {
        let output = await runCommand("/usr/sbin/diskutil", arguments: ["info", uuid])
        return output != nil
    }

    func getVolumePath(for uuid: String) async -> String? {
        let output = await runCommand("/usr/sbin/diskutil", arguments: ["info", uuid])
        guard let output else { return nil }

        for line in output.components(separatedBy: "\n") {
            if line.contains("Mount Point:") {
                let parts = line.components(separatedBy: ":")
                if parts.count >= 2 {
                    let path = parts[1].trimmingCharacters(in: .whitespaces)
                    if !path.isEmpty && path != "(not mounted)" {
                        return path
                    }
                }
            }
        }

        return nil
    }

    // MARK: - Storage Information

    func getStorageUsage(for path: String) async -> String? {
        let output = await runCommand("/usr/bin/du", arguments: ["-shL", path])
        guard let output else { return nil }

        let parts = output.components(separatedBy: "\t")
        if let size = parts.first {
            return size.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }

    func getVolumeStorageInfo(for volumePath: String) async -> StorageInfo? {
        do {
            let attrs = try fileManager.attributesOfFileSystem(forPath: volumePath)
            let totalSize = attrs[.systemSize] as? Int64 ?? 0
            let freeSize = attrs[.systemFreeSize] as? Int64 ?? 0
            let usedSize = totalSize - freeSize

            return StorageInfo(
                totalSize: formatBytes(totalSize),
                usedSize: formatBytes(usedSize),
                availableSize: formatBytes(freeSize)
            )
        } catch {
            return nil
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - Path Type Detection

    func getPathType(for path: String) -> PathType {
        var isDirectory: ObjCBool = false

        // Check if it's a symlink first
        if let attrs = try? fileManager.attributesOfItem(atPath: path),
           let type = attrs[.type] as? FileAttributeType,
           type == .typeSymbolicLink {
            if let target = try? fileManager.destinationOfSymbolicLink(atPath: path) {
                return .symlink(target: target)
            }
            return .symlink(target: "unknown")
        }

        // Check if path exists
        if fileManager.fileExists(atPath: path, isDirectory: &isDirectory) {
            return isDirectory.boolValue ? .realDirectory : .file
        }

        return .doesNotExist
    }

    func getSymlinkStatus() -> SymlinkStatus {
        SymlinkStatus(
            modelsPathType: getPathType(for: modelsSymlinkPath),
            hubPathType: getPathType(for: hubSymlinkPath)
        )
    }

    // MARK: - LM Studio Models Path Check

    func lmStudioModelsExist() -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: modelsSymlinkPath, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    func lmStudioHubExists() -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: hubSymlinkPath, isDirectory: &isDirectory) && isDirectory.boolValue
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

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)
                continuation.resume(returning: output)
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
}
