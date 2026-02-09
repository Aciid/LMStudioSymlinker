// OfflineModelsViewModel.swift

import Foundation
import SwiftUI
import Combine
import LMStudioSymlinkerCore

@MainActor
@Observable
final class OfflineModelsViewModel {
    // MARK: - State
    
    var models: [OfflineModelService.OfflineModelItem] = []
    var isLoading = false
    var errorMessage: String?
    
    // MARK: - Services
    
    private let offlineService: OfflineModelService
    private let drivePath: String
    
    // MARK: - Initialization
    
    init(driveProvider: DriveProviding, drivePath: String) {
        self.offlineService = OfflineModelService(driveProvider: driveProvider)
        self.drivePath = drivePath
        
        Task {
            await loadModels()
        }
    }
    
    // MARK: - Actions
    
    func loadModels() async {
        isLoading = true
        errorMessage = nil
        do {
            models = try await offlineService.listModels(externalDrivePath: drivePath)
        } catch {
            errorMessage = "Failed to load models: \(error.localizedDescription)"
        }
        isLoading = false
    }
    
    func toggleSync(for model: OfflineModelService.OfflineModelItem) async {
        // Optimistic update
        if let index = models.firstIndex(where: { $0.id == model.id }) {
            let updated = models[index]
            // We can't mutate 'let' properties, so we rely on the service to do the work and then refresh
            // But we want to show a spinner. 
            // Let's create a temporary modified item just for UI state if needed, or simply set a global syncing state?
            // For simplicity, let's just make the item "syncing" in the list if we could, 
            // but the struct is immutable. We'd need to replace it in the array.
            
            let syncingItem = OfflineModelService.OfflineModelItem(
                name: updated.name,
                publisher: updated.publisher,
                relativePath: updated.relativePath,
                size: updated.size,
                isSynced: updated.isSynced,
                isSyncing: true
            )
            models[index] = syncingItem
        }
        
        do {
            try await offlineService.syncModel(
                model: model,
                externalDrivePath: drivePath,
                progressHandler: { _ in } // We could expose this if we want granular progress
            )
            // Reload to get fresh state
            await loadModels()
        } catch {
            errorMessage = "Sync failed: \(error.localizedDescription)"
            await loadModels() // Revert state
        }
    }
}
