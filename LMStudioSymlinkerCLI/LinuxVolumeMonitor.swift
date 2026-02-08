#if os(Linux)
import Foundation
import LMStudioSymlinkerCore

/// VolumeMonitoring for Linux: polls /proc/mounts and invokes callbacks when selected path appears/disappears.
@MainActor
public final class LinuxVolumeMonitor: VolumeMonitoring {
    public var onVolumeMount: ((String) -> Void)?
    public var onVolumeUnmount: ((String) -> Void)?

    private var pollTask: Task<Void, Never>?
    private var lastMounts: Set<String> = []
    private let pollInterval: TimeInterval = 2.0

    public init() {}

    public func startMonitoring() {
        guard pollTask == nil else { return }
        lastMounts = currentMountPaths()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64((self?.pollInterval ?? 2) * 1_000_000_000))
                await self?.poll()
            }
        }
    }

    public func stopMonitoring() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func currentMountPaths() -> Set<String> {
        guard let content = try? String(contentsOfFile: "/proc/mounts", encoding: .utf8) else { return [] }
        var paths: Set<String> = []
        for line in content.components(separatedBy: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count >= 2 {
                paths.insert(String(parts[1]))
            }
        }
        return paths
    }

    private func poll() async {
        let current = currentMountPaths()
        let added = current.subtracting(lastMounts)
        let removed = lastMounts.subtracting(current)
        lastMounts = current
        for path in added {
            onVolumeMount?(path)
        }
        for path in removed {
            onVolumeUnmount?(path)
        }
    }
}
#endif
