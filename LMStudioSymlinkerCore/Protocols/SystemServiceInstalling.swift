// SystemServiceInstalling.swift - Abstract system service install (LaunchAgents vs systemd)

import Foundation

public protocol SystemServiceInstalling: Sendable {
    func install(volumeUUID: String, volumePath: String) async throws
    func uninstall() async throws
    func isInstalled() async -> Bool
    func getStatus() async -> [String: Bool]
}
