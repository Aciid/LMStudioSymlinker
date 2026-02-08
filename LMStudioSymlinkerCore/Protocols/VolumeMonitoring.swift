// VolumeMonitoring.swift - Abstract volume mount/unmount notifications

import Foundation

@MainActor
public protocol VolumeMonitoring: AnyObject {
    var onVolumeMount: ((String) -> Void)? { get set }
    var onVolumeUnmount: ((String) -> Void)? { get set }

    func startMonitoring()
    func stopMonitoring()
}
