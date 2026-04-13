
#if !os(tvOS)
import SwiftUI

struct ScenePerformersCard: View {
    let sceneId: String
    let performers: [ScenePerformer]
    var onPerformersUpdated: (([ScenePerformer]) -> Void)?
    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @State private var showingAddSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Performers")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(appearanceManager.tintColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if performers.isEmpty {
                Text("No performers assigned")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            } else {
                VStack(spacing: 12) {
                    ForEach(performers.sorted { $0.name < $1.name }) { scenePerformer in
                        NavigationLink(destination: PerformerDetailView(performer: scenePerformer.toPerformer())) {
                            ZStack(alignment: .bottom) {
                                ZStack {
                                    if let url = scenePerformer.thumbnailURL {
                                        CustomAsyncImage(url: url) { loader in
                                            if let image = loader.image {
                                                image
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 80, height: 80, alignment: .top)
                                                    .clipShape(Circle())
                                            } else {
                                                Circle()
                                                    .fill(Color.gray.opacity(DesignTokens.Opacity.placeholder))
                                                    .frame(width: 80, height: 80)
                                                    .skeleton()
                                            }
                                        }
                                    } else {
                                        Image(systemName: "person.circle.fill")
                                            .resizable()
                                            .frame(width: 80, height: 80)
                                            .foregroundColor(appearanceManager.tintColor.opacity(0.4))
                                    }
                                }
                                .padding(4)
                                .background(appearanceManager.tintColor)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(appearanceManager.tintColor.opacity(0.1), lineWidth: 0.2))

                                Text(scenePerformer.name)
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        ZStack {
                                            Color.secondaryAppBackground
                                            appearanceManager.tintColor.opacity(0.1)
                                        }
                                    )
                                    .foregroundColor(Color.pillAccent)
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(appearanceManager.tintColor.opacity(0.4), lineWidth: 0.5))
                                    .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                                    .offset(y: 8)
                            }
                            .padding(.bottom, 8)
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .cardShadow()
        .sheet(isPresented: $showingAddSheet) {
            AddPerformerToSceneSheet(
                sceneId: sceneId,
                currentPerformers: performers,
                viewModel: viewModel
            ) { updated in
                onPerformersUpdated?(updated)
            }
        }
    }
}

struct AddPerformerToSceneSheet: View {
    let sceneId: String
    let currentPerformers: [ScenePerformer]
    @ObservedObject var viewModel: StashDBViewModel
    var onComplete: ([ScenePerformer]) -> Void

    @Environment(\.dismiss) var dismiss
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @State private var performers: [Performer] = []
    @State private var isLoading = false
    @State private var searchText = ""
    @State private var selectedIds: Set<String> = []
    @State private var isSaving = false

    var filtered: [Performer] {
        if searchText.isEmpty { return performers }
        return performers.filter { $0.name.lowercased().contains(searchText.lowercased()) }
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Search Performers")) {
                    TextField("Search...", text: $searchText)
                    if isLoading {
                        HStack { Spacer(); ProgressView("Loading..."); Spacer() }.padding()
                    } else if performers.isEmpty {
                        Text("No performers found").foregroundColor(.secondary).padding()
                    } else {
                        ForEach(filtered.prefix(30)) { performer in
                            HStack {
                                Text(performer.name)
                                Spacer()
                                Text("\(performer.sceneCount) scenes").font(.caption).foregroundColor(.secondary)
                                if selectedIds.contains(performer.id) {
                                    Spacer()
                                    Image(systemName: "checkmark").foregroundColor(appearanceManager.tintColor)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectedIds.contains(performer.id) {
                                    selectedIds.remove(performer.id)
                                } else {
                                    selectedIds.insert(performer.id)
                                }
                            }
                        }
                        if filtered.count > 30 {
                            Text("Type more to refine...").font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                .listRowBackground(Color.secondaryAppBackground)
            }
            .navigationTitle("Add Performer")
            .navigationBarTitleDisplayMode(.inline)
            .applyAppBackground()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { save() }
                        .disabled(selectedIds.isEmpty || isSaving)
                }
            }
            .onAppear {
                selectedIds = Set(currentPerformers.map { $0.id })
                isLoading = true
                viewModel.fetchAllPerformers { fetched in
                    DispatchQueue.main.async {
                        self.performers = fetched
                        self.isLoading = false
                    }
                }
            }
        }
    }

    private func save() {
        isSaving = true
        let ids = Array(selectedIds)
        viewModel.updateScenePerformers(sceneId: sceneId, performerIds: ids) { success in
            DispatchQueue.main.async {
                isSaving = false
                if success {
                    let updated = performers.filter { selectedIds.contains($0.id) }.map {
                        ScenePerformer(id: $0.id, name: $0.name, sceneCount: $0.sceneCount, galleryCount: $0.galleryCount, oCounter: nil, updatedAt: $0.updatedAt)
                    }
                    onComplete(updated)
                    dismiss()
                } else {
                    ToastManager.shared.show("Failed to update performers", icon: "exclamationmark.triangle", style: .error)
                }
            }
        }
    }
}
#endif
