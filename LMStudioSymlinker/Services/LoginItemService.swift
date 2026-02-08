// LoginItemService.swift

import Foundation
import ServiceManagement

@MainActor
final class LoginItemService {
    static let shared = LoginItemService()

    private init() {}

    var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            // Fallback for older macOS versions
            return false
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if #available(macOS 13.0, *) {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        }
    }

    func toggle() throws {
        try setEnabled(!isEnabled)
    }
}
