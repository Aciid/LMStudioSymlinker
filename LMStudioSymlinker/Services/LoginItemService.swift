// LoginItemService.swift

import Foundation
import ServiceManagement

@MainActor
final class LoginItemService {
    static let shared = LoginItemService()

    private init() {}

    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    func toggle() throws {
        try setEnabled(!isEnabled)
    }
}
