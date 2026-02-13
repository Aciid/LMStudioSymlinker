// VolumeMonitoring.swift - Abstract volume mount/unmount notifications

import Foundation

/// Notifies observers when volumes are mounted or unmounted.
///
/// Implementations should call the callbacks on the main actor.
/// Both `onVolumeMount` and `onVolumeUnmount` receive the filesystem path
/// of the affected volume (e.g. `/Volumes/MyDrive`).
@MainActor
public protocol VolumeMonitoring: AnyObject {
    /// Called when a volume is mounted. The parameter is the mount path.
    var onVolumeMount: (@Sendable (String) -> Void)? { get set }

    /// Called when a volume is unmounted. The parameter is the former mount path.
    var onVolumeUnmount: (@Sendable (String) -> Void)? { get set }

    /// Begin observing mount/unmount events.
    func startMonitoring()

    /// Stop observing and release any system resources.
    func stopMonitoring()
}
