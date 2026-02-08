#if os(Linux)
import Foundation
import LMStudioSymlinkerCore

/// SystemServiceInstalling for Linux: systemd user unit that runs a script to sync symlinks on startup and on mount.
public final class SystemdUserService: SystemServiceInstalling, @unchecked Sendable {
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
