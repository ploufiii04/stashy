//
//  ServerDetailView.swift
//  stashy
//
//  Created by Daniel Goletz on 06.02.26.
//

#if !os(tvOS)
import SwiftUI

struct ServerDetailView: View {
    let server: ServerConfig
    @ObservedObject var configManager = ServerConfigManager.shared
    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @EnvironmentObject var coordinator: NavigationCoordinator

    @State private var showingEditSheet = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var runningTask: String? = nil

    @Environment(\.presentationMode) var presentationMode

    var isActive: Bool {
        configManager.activeConfig?.id == server.id
    }

    var body: some View {
        Form {
            Section("Server Information") {
                LabeledContent("Name", value: server.name)
                LabeledContent("URL", value: server.baseURL)
                LabeledContent("Protocol", value: server.serverProtocol.displayName)
                if isActive {
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(viewModel.serverStatus)
                            .foregroundColor(viewModel.isServerConnected ? .green : .red)
                    }
                }
            }
            .listRowBackground(Color.secondaryAppBackground)

            if !isActive {
                Section {
                    taskRow(label: "Connect to Server", icon: "power", taskId: "connect") {
                        connectServer()
                    }
                }
                .listRowBackground(Color.secondaryAppBackground)
            }

            Section("Scan & Identify") {
                taskRow(label: "Scan Library", icon: "arrow.triangle.2.circlepath", taskId: "scan") {
                    viewModel.triggerLibraryScan { success, message in
                        showResult(title: "Scan Library", message: message)
                    }
                }
                taskRow(label: "Identify", icon: "person.crop.square.filled.and.at.rectangle", taskId: "identify") {
                    viewModel.triggerIdentify { success, message in
                        showResult(title: "Identify", message: message)
                    }
                }
            }
            .listRowBackground(Color.secondaryAppBackground)

            Section("Generate") {
                taskRow(label: "Scene covers", icon: "photo.fill", taskId: "gen_covers") {
                    viewModel.triggerGenerate(covers: true) { success, message in
                        showResult(title: "Scene covers", message: message)
                    }
                }
                taskRow(label: "Previews", icon: "play.rectangle.fill", taskId: "gen_previews") {
                    viewModel.triggerGenerate(previews: true) { success, message in
                        showResult(title: "Previews", message: message)
                    }
                }
                taskRow(label: "Animated image previews", icon: "photo.on.rectangle.angled", taskId: "gen_imagePreviews") {
                    viewModel.triggerGenerate(imagePreviews: true) { success, message in
                        showResult(title: "Animated image previews", message: message)
                    }
                }
                taskRow(label: "Scene scrubber sprites", icon: "square.grid.3x3.fill", taskId: "gen_sprites") {
                    viewModel.triggerGenerate(sprites: true) { success, message in
                        showResult(title: "Scene scrubber sprites", message: message)
                    }
                }
                taskRow(label: "Marker previews", icon: "mappin.and.ellipse", taskId: "gen_markers") {
                    viewModel.triggerGenerate(markers: true) { success, message in
                        showResult(title: "Marker previews", message: message)
                    }
                }
                taskRow(label: "Marker animated image previews", icon: "mappin.and.ellipse.circle.fill", taskId: "gen_markerImagePreviews") {
                    viewModel.triggerGenerate(markerImagePreviews: true) { success, message in
                        showResult(title: "Marker animated image previews", message: message)
                    }
                }
                taskRow(label: "Marker screenshots", icon: "camera.fill", taskId: "gen_markerScreenshots") {
                    viewModel.triggerGenerate(markerScreenshots: true) { success, message in
                        showResult(title: "Marker screenshots", message: message)
                    }
                }
                taskRow(label: "Transcodes", icon: "film.stack", taskId: "gen_transcodes") {
                    viewModel.triggerGenerate(transcodes: true) { success, message in
                        showResult(title: "Transcodes", message: message)
                    }
                }
                taskRow(label: "Video perceptual hashes", icon: "number.square.fill", taskId: "gen_phashes") {
                    viewModel.triggerGenerate(phashes: true) { success, message in
                        showResult(title: "Video perceptual hashes", message: message)
                    }
                }
                taskRow(label: "Generate heatmaps and speeds for interactive scenes", icon: "waveform.path.ecg", taskId: "gen_heatmaps") {
                    viewModel.triggerGenerate(interactiveHeatmapsSpeeds: true) { success, message in
                        showResult(title: "Generate heatmaps and speeds", message: message)
                    }
                }
                taskRow(label: "Image clip previews", icon: "play.rectangle.on.rectangle.fill", taskId: "gen_clipPreviews") {
                    viewModel.triggerGenerate(clipPreviews: true) { success, message in
                        showResult(title: "Image clip previews", message: message)
                    }
                }
                taskRow(label: "Image thumbnails", icon: "photo.on.rectangle", taskId: "gen_imageThumbnails") {
                    viewModel.triggerGenerate(imageThumbnails: true) { success, message in
                        showResult(title: "Image thumbnails", message: message)
                    }
                }
                taskRow(label: "Image perceptual hashes", icon: "number.circle.fill", taskId: "gen_imagePhashes") {
                    viewModel.triggerGenerate(imagePhashes: true) { success, message in
                        showResult(title: "Image perceptual hashes", message: message)
                    }
                }
            }
            .listRowBackground(Color.secondaryAppBackground)

            Section("Cache") {
                taskRow(label: "Clear Image Cache", icon: "internaldrive", taskId: "cache_clear") {
                    ImageCache.shared.clearCurrentServerCache()
                    showResult(title: "Cache Cleared", message: "Images will be reloaded from the server.")
                }
            }
            .listRowBackground(Color.secondaryAppBackground)

            Section("Server Configuration") {
                Button(action: { showingEditSheet = true }) {
                    Label("Edit Configuration", systemImage: "pencil")
                        .foregroundColor(.primary)
                }
                Button(role: .destructive, action: {
                    configManager.deleteServer(id: server.id)
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Label("Delete Server", systemImage: "trash")
                        .foregroundColor(appearanceManager.tintColor)
                }
            }
            .listRowBackground(Color.secondaryAppBackground)
        }
        .navigationTitle(server.name)
        .applyAppBackground()
        .scrollContentBackground(.hidden)
        .alert(alertTitle, isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .sheet(isPresented: $showingEditSheet) {
            NavigationView {
                ServerFormViewNew(configToEdit: server) { updatedConfig in
                    configManager.addOrUpdateServer(updatedConfig)
                    if configManager.activeConfig?.id == updatedConfig.id {
                        configManager.saveConfig(updatedConfig)
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .toolbar {
            if isActive && viewModel.isServerConnected {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Image(systemName: "circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }
        }
    }

    @ViewBuilder
    private func taskRow(label: String, icon: String, taskId: String, action: @escaping () -> Void) -> some View {
        HStack {
            Label {
                Text(label)
            } icon: {
                Image(systemName: icon)
                    .frame(width: 24, alignment: .center)
            }
            .foregroundColor(.primary)
            Spacer()
            if runningTask == taskId {
                ProgressView()
                    .padding(.trailing, 4)
            } else {
                Button(action: {
                    if !isActive { connectServer() }
                    runningTask = taskId
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        action()
                    }
                }) {
                    Image(systemName: "play.circle.fill")
                        .foregroundColor(appearanceManager.tintColor)
                        .font(.title2)
                }
                .buttonStyle(.borderless)
                .disabled(runningTask != nil)
            }
        }
    }

    private func showResult(title: String, message: String) {
        DispatchQueue.main.async {
            runningTask = nil
            alertTitle = title
            alertMessage = message
            showAlert = true
        }
    }

    private func connectServer() {
        configManager.saveConfig(server)
        viewModel.resetData()
        viewModel.testConnection()
        viewModel.fetchStatistics()
        coordinator.resetAllStacks()
    }
}
#endif
