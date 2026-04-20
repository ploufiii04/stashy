//
//  PerformerDetailView.swift
//  stashy
//
//  Created by Daniel Goletz on 29.09.25.
//

#if !os(tvOS)
import SwiftUI


struct PerformerDetailView: View {
    @State var performer: Performer
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @ObservedObject var tabManager = TabManager.shared
    @StateObject private var viewModel = StashDBViewModel()
    @EnvironmentObject var coordinator: NavigationCoordinator
    @State private var refreshTrigger = UUID()
    @State private var isHeaderExpanded = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var fullPerformer: Performer?
    @State private var selectedSortOption: StashDBViewModel.SceneSortOption = StashDBViewModel.SceneSortOption(rawValue: TabManager.shared.getDetailSortOption(for: "performer_detail") ?? "") ?? .dateDesc
    @State private var selectedGallerySortOption: StashDBViewModel.GallerySortOption = .dateDesc
    @State private var selectedImageSortOption: StashDBViewModel.ImageSortOption = .dateDesc
    @State private var isChangingSort = false
    @State private var isFavorite: Bool = false
    @State private var isUpdatingFavorite: Bool = false
    
    enum DetailTab: String, CaseIterable {
        case scenes = "Scenes"
        case galleries = "Galleries"
        case studios = "Studios"
        case tags = "Tags"
        case groups = "Groups"
        case images = "Images"
    }
    @State private var selectedDetailTab: DetailTab = .scenes

    init(performer: Performer) {
        _performer = State(initialValue: performer)
    }

    // Safe sort change function
    private func changeSortOption(to newOption: StashDBViewModel.SceneSortOption) {
        if newOption == .random && selectedSortOption == .random {
            viewModel.refreshRandomSeed()
        }
        selectedSortOption = newOption
        TabManager.shared.setDetailSortOption(for: "performer_detail", option: newOption.rawValue)
        refreshTrigger = UUID()
        viewModel.fetchPerformerScenes(performerId: performer.id, sortBy: newOption, isInitialLoad: true)
    }

    private func changeGallerySortOption(to newOption: StashDBViewModel.GallerySortOption) {
        if newOption == .random && selectedGallerySortOption == .random {
            viewModel.refreshRandomSeed()
        }
        selectedGallerySortOption = newOption
        viewModel.fetchPerformerGalleries(performerId: performer.id, sortBy: newOption, isInitialLoad: true)
    }

    private func changeImageSortOption(to newOption: StashDBViewModel.ImageSortOption) {
        if newOption == .random && selectedImageSortOption == .random {
            viewModel.refreshRandomSeed()
        }
        selectedImageSortOption = newOption
        viewModel.fetchDetailImages(performerId: performer.id, sortBy: newOption, isInitialLoad: true)
    }
    
    @Environment(\.verticalSizeClass) var verticalSizeClass
    
    private var columns: [GridItem] {
        if verticalSizeClass == .compact {
             return [
                 GridItem(.flexible(), spacing: 12),
                 GridItem(.flexible(), spacing: 12)
             ]
        } else if horizontalSizeClass == .regular {
            return Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
        } else {
            return [GridItem(.flexible(), spacing: 12)]
        }
    }
    
    private var galleryColumns: [GridItem] {
        if horizontalSizeClass == .regular {
             return Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
        } else {
             return [
                 GridItem(.flexible(), spacing: 12),
                 GridItem(.flexible(), spacing: 12)
             ]
        }
    }

    private var displayPerformer: Performer {
        fullPerformer ?? performer
    }
    
    private var effectiveScenes: Int {
        max(viewModel.totalPerformerScenes, displayPerformer.sceneCount)
    }
    
    private var effectiveGalleries: Int {
        max(viewModel.totalPerformerGalleries, displayPerformer.galleryCount ?? 0)
    }
    
    private var availableTabs: [DetailTab] {
        var tabs: [DetailTab] = []
        if effectiveScenes > 0 { tabs.append(.scenes) }
        if effectiveGalleries > 0 { tabs.append(.galleries) }
        if viewModel.totalDetailStudios > 0 { tabs.append(.studios) }
        if viewModel.totalDetailTags > 0 { tabs.append(.tags) }
        if viewModel.totalDetailGroups > 0 { tabs.append(.groups) }
        if viewModel.totalDetailImages > 0 { tabs.append(.images) }
        return tabs
    }

    private var showTabSwitcher: Bool {
        availableTabs.count > 1
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                headerView(displayPerformer: displayPerformer)

                if selectedDetailTab == .scenes {
                    if !viewModel.performerScenes.isEmpty {
                        sceneGrid
                    } else if viewModel.isLoadingPerformerScenes {
                        VStack {
                            ProgressView()
                            Text("Loading scenes...").font(.caption).foregroundColor(.secondary)
                        }.padding(.top, 40)
                    } else {
                        Text("No scenes found").foregroundColor(.secondary).padding(.top, 40)
                    }
                } else if selectedDetailTab == .galleries {
                    if !viewModel.performerGalleries.isEmpty {
                        galleryGrid
                    } else if viewModel.isLoadingPerformerGalleries {
                        VStack {
                            ProgressView()
                            Text("Loading galleries...").font(.caption).foregroundColor(.secondary)
                        }.padding(.top, 40)
                    } else {
                        Text("No galleries found").foregroundColor(.secondary).padding(.top, 40)
                    }
                } else if selectedDetailTab == .studios {
                    studioGrid
                } else if selectedDetailTab == .tags {
                    tagGrid
                } else if selectedDetailTab == .groups {
                    groupGrid
                } else if selectedDetailTab == .images {
                    imageGrid
                }
            }
            .padding(16)
        }
        .applyAppBackground()
        .onAppear {
            loadData()
            isFavorite = performer.favorite ?? false
        }
        .onChange(of: viewModel.totalPerformerGalleries) { oldValue, newValue in
            // Switch to galleries only if no scenes exist and galleries are found
            if !viewModel.isLoadingPerformerScenes && viewModel.totalPerformerScenes == 0 && newValue > 0 {
                withAnimation(DesignTokens.Animation.quick) { selectedDetailTab = .galleries }
            }
        }
        .onChange(of: viewModel.totalPerformerScenes) { oldValue, newValue in
            if newValue > 0 {
                // If scenes are found, always favor scenes tab (as requested)
                withAnimation(DesignTokens.Animation.quick) { selectedDetailTab = .scenes }
            } else if newValue == 0 && viewModel.totalPerformerGalleries > 0 {
                // If scenes explicitly become 0 (or are 0 after load), switch to galleries
                withAnimation(DesignTokens.Animation.quick) { selectedDetailTab = .galleries }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SceneDeleted"))) { _ in
            print("🔄 SceneDeleted - Re-loading performer data")
            viewModel.fetchPerformerScenes(performerId: performer.id, sortBy: selectedSortOption, isInitialLoad: true)
            loadPerformerMetadata()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PerformerImageUpdated"))) { notification in
            if let targetId = notification.userInfo?["performerId"] as? String,
               let newPath = notification.userInfo?["newImagePath"] as? String {
                if performer.id == targetId {
                    performer.imagePath = newPath
                }
                if fullPerformer?.id == targetId {
                    fullPerformer?.imagePath = newPath
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(displayPerformer.name)
                    .font(.headline)
                    .lineLimit(1)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if showTabSwitcher {
                    Menu {
                        ForEach(availableTabs, id: \.self) { tab in
                            Button(action: { 
                                withAnimation(DesignTokens.Animation.quick) {
                                    selectedDetailTab = tab 
                                }
                            }) {
                                HStack {
                                    Text(tab.rawValue)
                                    if selectedDetailTab == tab {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(selectedDetailTab.rawValue)
                                .font(.system(size: 14, weight: .semibold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundColor(appearanceManager.tintColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(appearanceManager.tintColor.opacity(0.1))
                        .clipShape(Capsule())
                    }
                }
            }
        }
        .floatingActionBar {
            HStack(spacing: 0) {
                Button {
                    guard !isUpdatingFavorite else { return }
                    HapticManager.light()
                    isUpdatingFavorite = true
                    let newState = !isFavorite
                    withAnimation(DesignTokens.Animation.quick) { isFavorite = newState }

                    viewModel.togglePerformerFavorite(performerId: performer.id, favorite: newState) { success in
                        DispatchQueue.main.async {
                            if !success {
                                isFavorite = !newState
                                ToastManager.shared.show("Failed to update favorite", icon: "exclamationmark.triangle", style: .error)
                            }
                            isUpdatingFavorite = false
                        }
                    }
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .foregroundColor(isFavorite ? .red : appearanceManager.tintColor)
                }
                .frame(maxWidth: .infinity)

                if selectedDetailTab == .scenes {
                    sceneSortMenu
                        .frame(maxWidth: .infinity)
                } else if selectedDetailTab == .galleries {
                    gallerySortMenu
                        .frame(maxWidth: .infinity)
                } else if selectedDetailTab == .images {
                    imageSortMenu
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
    
    // MARK: - Helper Views & Methods
    
    private func loadData() {
        if viewModel.performerScenes.isEmpty && !viewModel.isLoadingPerformerScenes {
            viewModel.fetchPerformerScenes(performerId: performer.id, sortBy: selectedSortOption, isInitialLoad: true)
        }
        if viewModel.performerGalleries.isEmpty && !viewModel.isLoadingPerformerGalleries {
            viewModel.fetchPerformerGalleries(performerId: performer.id, sortBy: selectedGallerySortOption, isInitialLoad: true)
        }
        
        // Fetch extended content reliably
        if viewModel.detailImages.isEmpty && !viewModel.isLoadingDetailImages {
            viewModel.fetchDetailImages(performerId: performer.id, sortBy: selectedImageSortOption, isInitialLoad: true)
        }
        if viewModel.detailStudios.isEmpty && !viewModel.isLoadingDetailStudios {
            viewModel.fetchDetailStudios(performerId: performer.id)
        }
        if viewModel.detailTags.isEmpty && !viewModel.isLoadingDetailTags {
            viewModel.fetchDetailTags(performerId: performer.id)
        }
        if viewModel.detailGroups.isEmpty && !viewModel.isLoadingDetailGroups {
            viewModel.fetchDetailGroups(performerId: performer.id)
        }
        
        // Always load full metadata to ensure we have counts and details
        loadPerformerMetadata()
    }
    
    private func loadPerformerMetadata() {
        viewModel.fetchPerformer(performerId: performer.id) { fetchedPerformer in
             if let p = fetchedPerformer {
                 self.fullPerformer = p
                 self.isFavorite = p.favorite ?? false
             }
        }
    }
    
    private var sceneGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(viewModel.performerScenes) { scene in
                NavigationLink(destination: SceneDetailView(scene: scene)) {
                    SceneCardView(scene: scene)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            
            if viewModel.isLoadingPerformerScenes {
                 VStack(spacing: 8) {
                    ProgressView()
                    Text("Loading more scenes...").font(.caption).foregroundColor(.secondary)
                }.padding(.vertical, 20)
            } else if viewModel.hasMorePerformerScenes {
                Color.clear.frame(height: 1).onAppear { viewModel.loadMorePerformerScenes(performerId: performer.id) }
            }
        }
        .id(refreshTrigger)
    }
    
    private var galleryGrid: some View {
        LazyVGrid(columns: galleryColumns, spacing: 12) {
             ForEach(viewModel.performerGalleries) { gallery in
                 NavigationLink(destination: ImagesView(gallery: gallery)) {
                     GalleryCardView(gallery: gallery)
                 }
                 .buttonStyle(.plain)
             }
             if viewModel.isLoadingPerformerGalleries {
                 VStack(spacing: 8) {
                    ProgressView()
                    Text("Loading more galleries...").font(.caption).foregroundColor(.secondary)
                }.padding(.vertical, 20)
             } else if viewModel.hasMorePerformerGalleries {
                 Color.clear.frame(height: 1).onAppear { viewModel.loadMorePerformerGalleries(performerId: performer.id) }
             }
        }
    }
    
    private var studioGrid: some View {
        LazyVGrid(columns: galleryColumns, spacing: 12) {
            ForEach(viewModel.detailStudios) { studio in
                NavigationLink(destination: StudioDetailView(studio: studio)) {
                    StudioCardView(studio: studio)
                }
                .buttonStyle(.plain)
            }
            if viewModel.isLoadingDetailStudios { ProgressView().padding() }
            else if viewModel.hasMoreDetailStudios {
                Color.clear.onAppear { viewModel.fetchDetailStudios(performerId: performer.id, isInitialLoad: false) }
            }
        }
    }
    
    private var tagGrid: some View {
        LazyVGrid(columns: galleryColumns, spacing: 12) {
            ForEach(viewModel.detailTags) { tag in
                NavigationLink(destination: TagsView()) {
                    TagCardView(tag: tag)
                }
                .buttonStyle(.plain)
            }
            if viewModel.isLoadingDetailTags { ProgressView().padding() }
            else if viewModel.hasMoreDetailTags {
                Color.clear.onAppear { viewModel.fetchDetailTags(performerId: performer.id, isInitialLoad: false) }
            }
        }
    }
    
    private var groupGrid: some View {
        LazyVGrid(columns: galleryColumns, spacing: 12) {
            ForEach(viewModel.detailGroups) { group in
                NavigationLink(destination: GroupDetailView(selectedGroup: group)) {
                    GroupCardView(group: group)
                }
                .buttonStyle(.plain)
            }
            if viewModel.isLoadingDetailGroups { ProgressView().padding() }
            else if viewModel.hasMoreDetailGroups {
                Color.clear.onAppear { viewModel.fetchDetailGroups(performerId: performer.id, isInitialLoad: false) }
            }
        }
    }
    
    private var imageGrid: some View {
        LazyVGrid(columns: galleryColumns, spacing: 12) {
            ForEach(viewModel.detailImages) { image in
                NavigationLink(destination: FullScreenImageView(images: .constant(viewModel.detailImages), selectedImageId: image.id)) {
                    ImageThumbnailCard(image: image)
                }
                .buttonStyle(.plain)
            }
            if viewModel.isLoadingDetailImages { ProgressView().padding() }
            else if viewModel.hasMoreDetailImages {
                Color.clear.onAppear { viewModel.fetchDetailImages(performerId: performer.id, isInitialLoad: false) }
            }
        }
    }
    
    private var gallerySortMenu: some View {
        Menu {
            // Random
            Button(action: { changeGallerySortOption(to: .random) }) {
                HStack {
                    Text("Random")
                    if selectedGallerySortOption == .random { Image(systemName: "checkmark") }
                }
            }
            
            Divider()

            // Name
            Menu {
                Button(action: { changeGallerySortOption(to: .titleAsc) }) {
                    HStack {
                        Text("A → Z")
                        if selectedGallerySortOption == .titleAsc { Image(systemName: "checkmark") }
                    }
                }
                Button(action: { changeGallerySortOption(to: .titleDesc) }) {
                    HStack {
                        Text("Z → A")
                        if selectedGallerySortOption == .titleDesc { Image(systemName: "checkmark") }
                    }
                }
            } label: {
                HStack {
                    Text("Name")
                    if selectedGallerySortOption == .titleAsc || selectedGallerySortOption == .titleDesc { Image(systemName: "checkmark") }
                }
            }

            // Date
            Menu {
                Button(action: { changeGallerySortOption(to: .dateDesc) }) {
                    HStack {
                        Text("Newest First")
                        if selectedGallerySortOption == .dateDesc { Image(systemName: "checkmark") }
                    }
                }
                Button(action: { changeGallerySortOption(to: .dateAsc) }) {
                    HStack {
                        Text("Oldest First")
                        if selectedGallerySortOption == .dateAsc { Image(systemName: "checkmark") }
                    }
                }
            } label: {
                HStack {
                    Text("Date")
                    if selectedGallerySortOption == .dateDesc || selectedGallerySortOption == .dateAsc { Image(systemName: "checkmark") }
                }
            }

            // Rating
            Menu {
                Button(action: { changeGallerySortOption(to: .ratingDesc) }) {
                    HStack {
                        Text("High → Low")
                        if selectedGallerySortOption == .ratingDesc { Image(systemName: "checkmark") }
                    }
                }
                Button(action: { changeGallerySortOption(to: .ratingAsc) }) {
                    HStack {
                        Text("Low → High")
                        if selectedGallerySortOption == .ratingAsc { Image(systemName: "checkmark") }
                    }
                }
            } label: {
                HStack {
                    Text("Rating")
                    if selectedGallerySortOption == .ratingDesc || selectedGallerySortOption == .ratingAsc { Image(systemName: "checkmark") }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(appearanceManager.tintColor)
        }
    }
    
    private var imageSortMenu: some View {
        Menu {
            // Random
            Button(action: { changeImageSortOption(to: .random) }) {
                HStack {
                    Text("Random")
                    if selectedImageSortOption == .random { Image(systemName: "checkmark") }
                }
            }
            
            Divider()

            // Title
            Menu {
                Button(action: { changeImageSortOption(to: .titleAsc) }) {
                    HStack {
                        Text("A → Z")
                        if selectedImageSortOption == .titleAsc { Image(systemName: "checkmark") }
                    }
                }
                Button(action: { changeImageSortOption(to: .titleDesc) }) {
                    HStack {
                        Text("Z → A")
                        if selectedImageSortOption == .titleDesc { Image(systemName: "checkmark") }
                    }
                }
            } label: {
                HStack {
                    Text("Title")
                    if selectedImageSortOption == .titleAsc || selectedImageSortOption == .titleDesc { Image(systemName: "checkmark") }
                }
            }

            // Date
            Menu {
                Button(action: { changeImageSortOption(to: .dateDesc) }) {
                    HStack {
                        Text("Newest First")
                        if selectedImageSortOption == .dateDesc { Image(systemName: "checkmark") }
                    }
                }
                Button(action: { changeImageSortOption(to: .dateAsc) }) {
                    HStack {
                        Text("Oldest First")
                        if selectedImageSortOption == .dateAsc { Image(systemName: "checkmark") }
                    }
                }
            } label: {
                HStack {
                    Text("Date")
                    if selectedImageSortOption == .dateDesc || selectedImageSortOption == .dateAsc { Image(systemName: "checkmark") }
                }
            }

            // Rating
            Menu {
                Button(action: { changeImageSortOption(to: .ratingDesc) }) {
                    HStack {
                        Text("High → Low")
                        if selectedImageSortOption == .ratingDesc { Image(systemName: "checkmark") }
                    }
                }
                Button(action: { changeImageSortOption(to: .ratingAsc) }) {
                    HStack {
                        Text("Low → High")
                        if selectedImageSortOption == .ratingAsc { Image(systemName: "checkmark") }
                    }
                }
            } label: {
                HStack {
                    Text("Rating")
                    if selectedImageSortOption == .ratingDesc || selectedImageSortOption == .ratingAsc { Image(systemName: "checkmark") }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(appearanceManager.tintColor)
        }
    }
    
    private var sceneSortMenu: some View {
        Menu {
            // Random
            Button(action: { changeSortOption(to: .random) }) {
                HStack {
                    Text("Random")
                    if selectedSortOption == .random { Image(systemName: "checkmark") }
                }
            }
            
            Divider()
            
            // Date
            Menu {
                Button(action: { changeSortOption(to: .dateDesc) }) {
                    HStack {
                        Text("Newest First")
                        if selectedSortOption == .dateDesc { Image(systemName: "checkmark") }
                    }
                }
                Button(action: { changeSortOption(to: .dateAsc) }) {
                    HStack {
                        Text("Oldest First")
                        if selectedSortOption == .dateAsc { Image(systemName: "checkmark") }
                    }
                }
            } label: {
                HStack {
                    Text("Date")
                    if selectedSortOption == .dateAsc || selectedSortOption == .dateDesc { Image(systemName: "checkmark") }
                }
            }
            
            // Title
            Menu {
                Button(action: { changeSortOption(to: .titleAsc) }) {
                    HStack {
                        Text("A → Z")
                        if selectedSortOption == .titleAsc { Image(systemName: "checkmark") }
                    }
                }
                Button(action: { changeSortOption(to: .titleDesc) }) {
                    HStack {
                        Text("Z → A")
                        if selectedSortOption == .titleDesc { Image(systemName: "checkmark") }
                    }
                }
            } label: {
                HStack {
                    Text("Title")
                    if selectedSortOption == .titleAsc || selectedSortOption == .titleDesc { Image(systemName: "checkmark") }
                }
            }
            
            // Duration
            Menu {
                Button(action: { changeSortOption(to: .durationDesc) }) {
                    HStack {
                        Text("Longest First")
                        if selectedSortOption == .durationDesc { Image(systemName: "checkmark") }
                    }
                }
                Button(action: { changeSortOption(to: .durationAsc) }) {
                    HStack {
                        Text("Shortest First")
                        if selectedSortOption == .durationAsc { Image(systemName: "checkmark") }
                    }
                }
            } label: {
                HStack {
                    Text("Duration")
                    if selectedSortOption == .durationAsc || selectedSortOption == .durationDesc { Image(systemName: "checkmark") }
                }
            }
            
            // Rating
            Menu {
                Button(action: { changeSortOption(to: .ratingDesc) }) {
                    HStack {
                        Text("High → Low")
                        if selectedSortOption == .ratingDesc { Image(systemName: "checkmark") }
                    }
                }
                Button(action: { changeSortOption(to: .ratingAsc) }) {
                    HStack {
                        Text("Low → High")
                        if selectedSortOption == .ratingAsc { Image(systemName: "checkmark") }
                    }
                }
            } label: {
                HStack {
                    Text("Rating")
                    if selectedSortOption == .ratingAsc || selectedSortOption == .ratingDesc { Image(systemName: "checkmark") }
                }
            }
            
            // Counter
            Menu {
                Button(action: { changeSortOption(to: .oCounterDesc) }) {
                    HStack {
                        Text("High → Low")
                        if selectedSortOption == .oCounterDesc { Image(systemName: "checkmark") }
                    }
                }
                Button(action: { changeSortOption(to: .oCounterAsc) }) {
                    HStack {
                        Text("Low → High")
                        if selectedSortOption == .oCounterAsc { Image(systemName: "checkmark") }
                    }
                }
            } label: {
                HStack {
                    Text("Counter")
                    if selectedSortOption == .oCounterAsc || selectedSortOption == .oCounterDesc { Image(systemName: "checkmark") }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(appearanceManager.tintColor)
        }
    }

    private func headerView(displayPerformer: Performer) -> some View {
        let collapsedHeight: CGFloat = 115
        let imageWidth: CGFloat = 72
        
        return HStack(alignment: .top, spacing: 0) {
            // Thumbnail: 9:16 portrait, flush to edges, cropped from top
            ZStack(alignment: .bottom) {
                if let thumbnailURL = displayPerformer.thumbnailURL {
                    CustomAsyncImage(url: thumbnailURL) { loader in
                        if loader.isLoading {
                            Rectangle().fill(Color.gray.opacity(DesignTokens.Opacity.placeholder))
                                .overlay(ProgressView().scaleEffect(0.6))
                        } else if let image = loader.image {
                            image.resizable()
                                .scaledToFill()
                                .frame(width: imageWidth)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .clipped()
                        } else {
                            defaultThumbnailContent(width: imageWidth)
                        }
                    }
                } else {
                    defaultThumbnailContent(width: imageWidth)
                }
            }
            .frame(width: imageWidth)
            .frame(minHeight: collapsedHeight)
            .frame(maxHeight: isHeaderExpanded ? .infinity : collapsedHeight)
            .background(Color.gray.opacity(DesignTokens.Opacity.placeholder))
            
            // Details Section
            VStack(alignment: .leading, spacing: 4) {
                // Header: Name and Stats
                HStack(alignment: .top, spacing: 8) {
                    Text(displayPerformer.name)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .lineLimit(isHeaderExpanded ? nil : 1)
                    
                    Spacer()
                    
                    // Social Button (Top Right)
                    if tabManager.tabs.first(where: { $0.id == .reels })?.isVisible ?? true {
                        Button(action: {
                            let sp = ScenePerformer(id: displayPerformer.id, name: displayPerformer.name, birthdate: displayPerformer.birthdate, sceneCount: displayPerformer.sceneCount, galleryCount: displayPerformer.galleryCount, oCounter: displayPerformer.oCounter, updatedAt: nil)
                            coordinator.navigateToReels(performer: sp, mode: nil)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles.tv")
                                    .font(.system(size: 12, weight: .bold))
                                Text("Social")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundColor(Color.pillAccent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(appearanceManager.tintColor.opacity(0.15))
                            .clipShape(Capsule())
                        }
                    }
                }
                
                // Grid for Performer Info
                let allDetails = getPerformerDetails(displayPerformer)
                let visibleDetails = isHeaderExpanded ? allDetails : Array(allDetails.prefix(4))
                
                if !visibleDetails.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                        ForEach(visibleDetails, id: \.label) { detail in
                            VStack(alignment: .leading, spacing: 0) {
                                Text(detail.label)
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary)
                                    .textCase(.uppercase)
                                Text(detail.value)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: collapsedHeight, alignment: .topLeading)
        }
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .cardShadow()
        .overlay(
            Group {
                let allDetails = getPerformerDetails(displayPerformer)
                if allDetails.count > 4 {
                    Button(action: {
                        withAnimation(.spring()) {
                            isHeaderExpanded.toggle()
                        }
                    }) {
                        Image(systemName: isHeaderExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(Color.pillAccent)
                            .padding(6)
                            .background(appearanceManager.tintColor.opacity(0.15))
                            .clipShape(Circle())
                    }
                    .padding(8)
                }
            },
            alignment: .bottomTrailing
        )
    }

    private func cardBadge(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 10))
            Text(text).font(.system(size: 10, weight: .bold))
        }
        .foregroundColor(Color.pillAccent)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(appearanceManager.tintColor.opacity(0.15))
        .clipShape(Capsule())
    }

    private func defaultThumbnailContent(width: CGFloat) -> some View {
        Rectangle().fill(Color.gray.opacity(DesignTokens.Opacity.placeholder))
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .overlay(Image(systemName: "person.fill").font(.system(size: 32)).foregroundColor(.appAccent.opacity(0.5)))
    }

    private func thumbnailBadge(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 10))
            Text(text).font(.system(size: 10, weight: .bold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.black.opacity(DesignTokens.Opacity.badge))
        .clipShape(Capsule())
    }

    private func detailStat(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption).foregroundColor(Color.pillAccent)
            Text(text).font(.caption).fontWeight(.bold).foregroundColor(.primary)
        }
    }

    private func getPerformerDetails(_ p: Performer) -> [(label: String, value: String)] {
        var list: [(label: String, value: String)] = []
        
        // Add Scenes and Galleries as the first row
        list.append((label: "SCENES", value: "\(p.sceneCount)"))
        if let gCount = p.galleryCount ?? viewModel.totalPerformerGalleries as Int?, gCount > 0 {
            list.append((label: "GALLERIES", value: "\(gCount)"))
        } else {
            // Add a placeholder to keep the grid aligned if galleries are 0
            // Or just leave it if there's only 1 item in the first row. 
            // Usually it looks better if the first row is full.
            // But if there are no galleries, maybe just leave it.
        }
        
        if let val = p.gender, !val.isEmpty { list.append((label: "GENDER", value: val)) }
        
        let gender = p.gender?.uppercased() ?? ""
        if gender.contains("FEMALE") {
            if let val = p.fakeTits, !val.isEmpty { list.append((label: "Tits", value: val)) }
        } else if gender.contains("MALE") || gender == "MAN" {
            if let val = p.penis_length, val > 0 { list.append((label: "Penis", value: "\(val) cm")) }
        } else {
            // For other genders (Non-binary, etc.), show whatever data is available
            if let val = p.fakeTits, !val.isEmpty { list.append((label: "Tits", value: val)) }
            if let val = p.penis_length, val > 0 { list.append((label: "Penis", value: "\(val) cm")) }
        }
        if let val = p.birthdate, !val.isEmpty { list.append((label: "BORN", value: val)) }
        if let val = p.country, !val.isEmpty { list.append((label: "COUNTRY", value: val)) }
        if let val = p.ethnicity, !val.isEmpty { list.append((label: "ETHNICITY", value: val)) }
        if let val = p.height, val > 0 { list.append((label: "HEIGHT", value: "\(val) cm")) }
        if let val = p.weight, val > 0 { list.append((label: "WEIGHT", value: "\(val) kg")) }
        if let val = p.measurements, !val.isEmpty { list.append((label: "MEASUREMENTS", value: val)) }
        if let val = p.careerLength, !val.isEmpty { list.append((label: "CAREER", value: val)) }
        if let val = p.tattoos, !val.isEmpty { list.append((label: "TATTOOS", value: val)) }
        if let val = p.piercings, !val.isEmpty { list.append((label: "PIERCINGS", value: val)) }
        
        return list
    }

    private func detailRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#Preview {
    let samplePerformer = Performer(
        id: "1",
        name: "Sample Performer",
        disambiguation: "Test",
        birthdate: "1990-01-01",
        country: "Germany",
        imagePath: nil,
        sceneCount: 5,
        galleryCount: 1,
        gender: "Female",
        ethnicity: "Caucasian",
        height: 165,
        weight: 55,
        measurements: "34-24-34",
        fakeTits: "No",
        penis_length: nil,
        careerLength: "5 years",
        tattoos: "None",
        piercings: "Navel",
        aliasList: ["Jane Doe", "J.D."],
        favorite: false,
        rating100: nil,
        createdAt: nil,
        updatedAt: nil,
        oCounter: 0
    )
    PerformerDetailView(performer: samplePerformer)
}
#endif
