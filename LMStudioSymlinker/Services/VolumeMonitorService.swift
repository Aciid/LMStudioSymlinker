// VolumeMonitorService.swift

import Foundation
import DiskArbitration

@MainActor
final class VolumeMonitorService {
    static let shared = VolumeMonitorService()

    private var session: DASession?
    private var isMonitoring = false

    var onVolumeMount: ((String) -> Void)?
    var onVolumeUnmount: ((String) -> Void)?

    private init() {}

    func startMonitoring() {
        guard !isMonitoring else { return }

        session = DASessionCreate(kCFAllocatorDefault)

        guard let session else {
            print("Failed to create DiskArbitration session")
            return
        }

        DASessionSetDispatchQueue(session, DispatchQueue.main)

        // Register for mount notifications
        DARegisterDiskAppearedCallback(
            session,
            nil,
            { disk, context in
                guard let context else { return }
                let service = Unmanaged<VolumeMonitorService>.fromOpaque(context).takeUnretainedValue()
                service.handleDiskAppeared(disk)
            },
            Unmanaged.passUnretained(self).toOpaque()
        )

        // Register for unmount notifications
        DARegisterDiskDisappearedCallback(
            session,
            nil,
            { disk, context in
                guard let context else { return }
                let service = Unmanaged<VolumeMonitorService>.fromOpaque(context).takeUnretainedValue()
                service.handleDiskDisappeared(disk)
            },
            Unmanaged.passUnretained(self).toOpaque()
        )

        isMonitoring = true
    }

    func stopMonitoring() {
        guard isMonitoring, let session else { return }

        DAUnregisterCallback(session, Unmanaged.passUnretained(self).toOpaque(), nil)
        self.session = nil
        isMonitoring = false
    }

    private func handleDiskAppeared(_ disk: DADisk) {
        guard let description = DADiskCopyDescription(disk) as? [String: Any],
              let volumePath = description[kDADiskDescriptionVolumePathKey as String] as? URL else {
            return
        }

        let path = volumePath.path
        print("Volume mounted: \(path)")
        onVolumeMount?(path)
    }

    private func handleDiskDisappeared(_ disk: DADisk) {
        guard let description = DADiskCopyDescription(disk) as? [String: Any],
              let volumePath = description[kDADiskDescriptionVolumePathKey as String] as? URL else {
            return
        }

        let path = volumePath.path
        print("Volume unmounted: \(path)")
        onVolumeUnmount?(path)
    }
}
