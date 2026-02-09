// OfflineModelsView.swift

import SwiftUI
import LMStudioSymlinkerCore

struct OfflineModelsView: View {
    @State private var viewModel: OfflineModelsViewModel
    @Environment(\.dismiss) private var dismiss
    
    init(driveProvider: DriveProviding, drivePath: String) {
        _viewModel = State(initialValue: OfflineModelsViewModel(
            driveProvider: driveProvider,
            drivePath: drivePath
        ))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Offline Models")
                    .font(.headline)
                Spacer()
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
                Button("Done") {
                    dismiss()
                }
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // List
            if let error = viewModel.errorMessage {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.red)
                        .padding(.bottom, 8)
                    Text(error)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        Task { await viewModel.loadModels() }
                    }
                    .padding(.top)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.models.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "No Models Found",
                    systemImage: "cube.box",
                    description: Text("No models found in the external drive's models directory.")
                )
            } else {
                List {
                    Section {
                        ForEach(viewModel.models) { model in
                            OfflineModelRow(model: model) {
                                Task {
                                    await viewModel.toggleSync(for: model)
                                }
                            }
                        }
                    } header: {
                        Text("Select models to keep available offline")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 4)
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(width: 500, height: 600)
    }
}

struct OfflineModelRow: View {
    let model: OfflineModelService.OfflineModelItem
    let onToggle: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.publisher)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(model.name)
                    .fontWeight(.medium)
                Text(model.size)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if model.isSyncing {
                ProgressView()
                    .scaleEffect(0.5)
            } else {
                Toggle("", isOn: Binding(
                    get: { model.isSynced },
                    set: { _ in onToggle() }
                ))
                .toggleStyle(.switch)
            }
        }
        .padding(.vertical, 4)
    }
}
