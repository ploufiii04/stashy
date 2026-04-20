//
//  StudioDetailView.swift
//  stashy
//
//  Created by Daniel Goletz on 29.09.25.
//

#if !os(tvOS)
import SwiftUI


struct StudioDetailView: View {
    let studio: Studio
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @StateObject private var viewModel = StashDBViewModel()
    @State private var refreshTrigger = UUID()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedSortOption: StashDBViewModel.SceneSortOption = StashDBViewModel.SceneSortOption(rawValue: TabManager.shared.getDetailSortOption(for: "studio_detail") ?? "") ?? .dateDesc
    @State private var selectedGallerySortOption: StashDBViewModel.GallerySortOption = .dateDesc
    @State private var selectedImageSortOption: StashDBViewModel.ImageSortOption = .dateDesc
    @State private var selectedPerformerSortOption: StashDBViewModel.PerformerSortOption = .nameAsc
    @State private var isChangingSort = false
    @State private var isFavorite: Bool = false
    @State private var isUpdatingFavorite: Bool = false
    @State private var isHeaderExpanded = false // Added state for expansion
    
    enum DetailTab: String, CaseIterable {
        case scenes = "Scenes"
        case galleries = "Galleries"
        case studios = "Studios"
        case performers = "Performers"
        case tags = "Tags"
        case groups = "Groups"
        case images = "Images"
    }
    @State private var selectedDetailTab: DetailTab = .scenes
    
    // Computed properties for counts
    private var effectiveScenesCount: Int {
        max(viewModel.totalStudioScenes, studio.sceneCount)
    }
    
    private var effectiveGalleriesCount: Int {
        max(viewModel.totalStudioGalleries, studio.galleryCount ?? 0)
    }
    
    private var availableTabs: [DetailTab] {
        var tabs: [DetailTab] = []
        if effectiveScenesCount > 0 { tabs.append(.scenes) }
        if effectiveGalleriesCount > 0 { tabs.append(.galleries) }
        if viewModel.totalDetailStudios > 0 { tabs.append(.studios) }
        if viewModel.totalDetailPerformers > 0 { tabs.append(.performers) }
        if viewModel.totalDetailTags > 0 { tabs.append(.tags) }
        if viewModel.totalDetailGroups > 0 { tabs.append(.groups) }
        if viewModel.totalDetailImages > 0 { tabs.append(.images) }
        return tabs
    }

    private var showTabSwitcher: Bool {
        availableTabs.count > 1
    }

    // Safe sort change function
    private func changeSortOption(to newOption: StashDBViewModel.SceneSortOption) {
        if newOption == .random && selectedSortOption == .random {
            viewModel.refreshRandomSeed()
        }
        selectedSortOption = newOption
        
        // Save to TabManager (Session)
        TabManager.shared.setDetailSortOption(for: "studio_detail", option: newOption.rawValue)

        // Force view refresh
        refreshTrigger = UUID()

        // Fetch new data immediately
        viewModel.fetchStudioScenes(studioId: studio.id, sortBy: newOption, isInitialLoad: true)
    }

    private func changeGallerySortOption(to newOption: StashDBViewModel.GallerySortOption) {
        if newOption == .random && selectedGallerySortOption == .random {
            viewModel.refreshRandomSeed()
        }
        selectedGallerySortOption = newOption
        viewModel.fetchStudioGalleries(studioId: studio.id, sortBy: newOption, isInitialLoad: true)
    }

    private func changeImageSortOption(to newOption: StashDBViewModel.ImageSortOption) {
        if newOption == .random && selectedImageSortOption == .random {
            viewModel.refreshRandomSeed()
        }
        selectedImageSortOption = newOption
        viewModel.fetchDetailImages(studioId: studio.id, sortBy: newOption, isInitialLoad: true)
    }
    
    private func changePerformerSortOption(to newOption: StashDBViewModel.PerformerSortOption) {
        if newOption == .random && selectedPerformerSortOption == .random {
            viewModel.refreshRandomSeed()
        }
        selectedPerformerSortOption = newOption
        viewModel.fetchDetailPerformers(studioId: studio.id, sortBy: newOption, isInitialLoad: true)
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

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Header Card
                headerCard
                
                if selectedDetailTab == .scenes {
                    if !viewModel.studioScenes.isEmpty {
                        sceneGrid
                    } else if viewModel.isLoadingStudioScenes {
                        loadingView(message: "Loading scenes...")
                    } else {
                        emptyView(message: "No scenes found", icon: "film")
                    }
                } else if selectedDetailTab == .galleries {
                    if !viewModel.studioGalleries.isEmpty {
                        galleryGrid
                    } else if viewModel.isLoadingStudioGalleries {
                        loadingView(message: "Loading galleries...")
                    } else {
                        emptyView(message: "No galleries found", icon: "photo.on.rectangle")
                    }
                } else if selectedDetailTab == .studios {
                    studioGrid
                } else if selectedDetailTab == .performers {
                    performerGrid
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
            // If we know from the passed studio object that there are no scenes but there are galleries,
            // switch immediately so the user sees content.
            if effectiveScenesCount == 0 && effectiveGalleriesCount > 0 {
                withAnimation(DesignTokens.Animation.quick) { selectedDetailTab = .galleries }
            }
            loadData()
            // Fetch updated studio details (like favorite status) which might be missing from list view objects
            viewModel.fetchStudio(studioId: studio.id) { updatedStudio in
                if let updated = updatedStudio {
                    self.isFavorite = updated.favorite ?? false
                } else {
                    self.isFavorite = studio.favorite ?? false
                }
            }
        }
        .onChange(of: viewModel.isLoadingStudioScenes) { oldValue, newValue in
            // If scene loading finished and we found 0 scenes, but we have galleries, switch to galleries
            if !newValue && effectiveScenesCount == 0 && effectiveGalleriesCount > 0 {
                withAnimation(DesignTokens.Animation.quick) { selectedDetailTab = .galleries }
            }
        }
        .onChange(of: effectiveGalleriesCount) { oldValue, newValue in
            if !viewModel.isLoadingStudioScenes && effectiveScenesCount == 0 && newValue > 0 {
                withAnimation(DesignTokens.Animation.quick) { selectedDetailTab = .galleries }
            }
        }
        .onChange(of: effectiveScenesCount) { oldValue, newValue in
            if newValue > 0 {
                withAnimation(DesignTokens.Animation.quick) { selectedDetailTab = .scenes }
            } else if newValue == 0 && effectiveGalleriesCount > 0 {
                withAnimation(DesignTokens.Animation.quick) { selectedDetailTab = .galleries }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SceneDeleted"))) { _ in
            print("🔄 STUDIO DETAIL: Recieved SceneDeleted notification, refreshing...")
            refreshTrigger = UUID()
            viewModel.fetchStudioScenes(studioId: studio.id, sortBy: selectedSortOption, isInitialLoad: true)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(studio.name)
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

                    viewModel.toggleStudioFavorite(studioId: studio.id, favorite: newState) { success in
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
                    sortMenu
                        .frame(maxWidth: .infinity)
                } else if selectedDetailTab == .galleries {
                    gallerySortMenu
                        .frame(maxWidth: .infinity)
                } else if selectedDetailTab == .performers {
                    performerSortMenu
                        .frame(maxWidth: .infinity)
                } else if selectedDetailTab == .images {
                    imageSortMenu
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
    
    // MARK: - Subviews
    
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(studio.name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                Spacer()
            }
            
            // Info List
            let details = getStudioDetails(studio)
            // User wants "hide starting from 3rd line".
            // Line 1: Details 1-2
            // Line 2: Details 3-4 OR URL (if <= 2 details)
            // So we always allow up to 4 details (2 rows) visible if no URL conflict,
            // or if URL exists but we prioritize details 3-4 over URL to maximize info density?
            // User complaint: "You hide the second row [Item 3] already".
            // So we MUST show Item 3+4 if present. This takes 2 rows.
            // If 2 rows taken by details, URL (Row 3) must be hidden.
            let visibleDetails = isHeaderExpanded ? details : Array(details.prefix(4))
            let hasURL = studio.url != nil && !studio.url!.isEmpty
            
            if !visibleDetails.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
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
            
            // URL Link (Always on its own row)
            // Show if expanded OR if we have space (details <= 2, i.e. 1 row used)
            if hasURL && (isHeaderExpanded || details.count <= 2) {
                 VStack(alignment: .leading, spacing: 2) {
                     Text("URL")
                         .font(.system(size: 8))
                         .foregroundColor(.secondary)
                         .textCase(.uppercase)
                     Link(destination: URL(string: studio.url!) ?? URL(string: "https://google.com")!) {
                         Text(studio.url!)
                             .font(.system(size: 11, weight: .bold))
                             .foregroundColor(appearanceManager.tintColor)
                             .lineLimit(1)
                     }
                 }
            }
            
            // Description (Full width if present)
            if let desc = studio.details, !desc.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Divider()
                    Text(desc)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                }
            }
        }
        .padding(.leading, 140 + 12) // Logo width + spacing
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 115, alignment: .topLeading) // Ensure minimum height for logo and top alignment
        .overlay(
            ZStack {
                Color.studioHeaderGray
                StudioImageView(studio: studio)
                    .padding(8)
            }
            .frame(width: 140)
            , alignment: .leading
        )
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .cardShadow()
        .overlay(
            Group {
                let details = getStudioDetails(studio)
                let hasURL = studio.url != nil && !studio.url!.isEmpty
                
                // Button needed if:
                // 1. More details than shown (count > 4)
                // 2. URL exists but is hidden (count > 2)
                if details.count > 4 || (hasURL && details.count > 2) {
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

    private func getStudioDetails(_ s: Studio) -> [(label: String, value: String)] {
        var list: [(label: String, value: String)] = []
        
        // Add Scenes and Galleries as the first row (matching PerformerDetailView)
        list.append((label: "SCENES", value: "\(effectiveScenesCount)"))
        
        if effectiveGalleriesCount > 0 {
            list.append((label: "GALLERIES", value: "\(effectiveGalleriesCount)"))
        } else {
             // Optional: Add placeholder if needed for grid alignment, but usually fine to omit
        }
        
        if let count = s.performerCount, count > 0 {
            list.append((label: "PERFORMERS", value: "\(count)"))
        }
        
        // URL is now handled separately in the view to ensure it gets its own row
        
        return list
    }

    private func miniBadge(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.black.opacity(DesignTokens.Opacity.badge))
        .clipShape(Capsule())
    }
    
    private func labelBadge(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(Color.pillAccent)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var sceneGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(viewModel.studioScenes) { scene in
                NavigationLink(destination: SceneDetailView(scene: scene)) {
                    SceneCardView(scene: scene)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if viewModel.isLoadingStudioScenes {
                loadingIndicator(message: "Loading more scenes...")
            } else if viewModel.hasMoreStudioScenes && !viewModel.studioScenes.isEmpty {
                Color.clear.frame(height: 1).onAppear { viewModel.loadMoreStudioScenes(studioId: studio.id) }
            }
        }
        .id(refreshTrigger)
    }
    
    private var galleryGrid: some View {
        LazyVGrid(columns: galleryColumns, spacing: 12) {
            ForEach(viewModel.studioGalleries) { gallery in
                NavigationLink(destination: ImagesView(gallery: gallery)) {
                    GalleryCardView(gallery: gallery)
                }
                .buttonStyle(.plain)
            }

            if viewModel.isLoadingStudioGalleries {
                loadingIndicator(message: "Loading more galleries...")
            } else if viewModel.hasMoreStudioGalleries && !viewModel.studioGalleries.isEmpty {
                Color.clear.frame(height: 1).onAppear { viewModel.loadMoreStudioGalleries(studioId: studio.id) }
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

    private var performerSortMenu: some View {
        Menu {
            // Random
            Button(action: { changePerformerSortOption(to: .random) }) {
                HStack {
                    Text("Random")
                    if selectedPerformerSortOption == .random { Image(systemName: "checkmark") }
                }
            }
            
            Divider()

            // Name
            Menu {
                Button(action: { changePerformerSortOption(to: .nameAsc) }) {
                    HStack {
                        Text("A → Z")
                        if selectedPerformerSortOption == .nameAsc { Image(systemName: "checkmark") }
                    }
                }
                Button(action: { changePerformerSortOption(to: .nameDesc) }) {
                    HStack {
                        Text("Z → A")
                        if selectedPerformerSortOption == .nameDesc { Image(systemName: "checkmark") }
                    }
                }
            } label: {
                HStack {
                    Text("Name")
                    if selectedPerformerSortOption == .nameAsc || selectedPerformerSortOption == .nameDesc { Image(systemName: "checkmark") }
                }
            }

            // Scene Count
            Menu {
                Button(action: { changePerformerSortOption(to: .sceneCountDesc) }) {
                    HStack {
                        Text("High → Low")
                        if selectedPerformerSortOption == .sceneCountDesc { Image(systemName: "checkmark") }
                    }
                }
                Button(action: { changePerformerSortOption(to: .sceneCountAsc) }) {
                    HStack {
                        Text("Low → High")
                        if selectedPerformerSortOption == .sceneCountAsc { Image(systemName: "checkmark") }
                    }
                }
            } label: {
                HStack {
                    Text("Scenes")
                    if selectedPerformerSortOption == .sceneCountDesc || selectedPerformerSortOption == .sceneCountAsc { Image(systemName: "checkmark") }
                }
            }

            // Birthday
            Menu {
                Button(action: { changePerformerSortOption(to: .birthdateDesc) }) {
                    HStack {
                        Text("Youngest First")
                        if selectedPerformerSortOption == .birthdateDesc { Image(systemName: "checkmark") }
                    }
                }
                Button(action: { changePerformerSortOption(to: .birthdateAsc) }) {
                    HStack {
                        Text("Oldest First")
                        if selectedPerformerSortOption == .birthdateAsc { Image(systemName: "checkmark") }
                    }
                }
            } label: {
                HStack {
                    Text("Birthday")
                    if selectedPerformerSortOption == .birthdateDesc || selectedPerformerSortOption == .birthdateAsc { Image(systemName: "checkmark") }
                }
            }

            // Created/Updated
            Menu {
                Button(action: { changePerformerSortOption(to: .createdAtDesc) }) {
                    HStack {
                        Text("Newest First (Created)")
                        if selectedPerformerSortOption == .createdAtDesc { Image(systemName: "checkmark") }
                    }
                }
                Button(action: { changePerformerSortOption(to: .updatedAtDesc) }) {
                    HStack {
                        Text("Newest First (Updated)")
                        if selectedPerformerSortOption == .updatedAtDesc { Image(systemName: "checkmark") }
                    }
                }
            } label: {
                HStack {
                    Text("Date")
                    if selectedPerformerSortOption == .createdAtDesc || selectedPerformerSortOption == .updatedAtDesc { Image(systemName: "checkmark") }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(appearanceManager.tintColor)
        }
    }
    
    private var sortMenu: some View {
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
    
    private func loadingView(message: String) -> some View {
        VStack {
            Spacer()
            ProgressView(message)
            Spacer()
        }.frame(height: 200)
    }
    
    private func emptyView(message: String, icon: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            Text(message)
                .font(.title3)
                .foregroundColor(.secondary)
        }.padding(.top, 40)
    }
    
    private func loadingIndicator(message: String) -> some View {
        VStack(spacing: 8) {
            ProgressView()
            Text(message).font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
    
    private func loadData() {
        if viewModel.studioGalleries.isEmpty && !viewModel.isLoadingStudioGalleries {
            viewModel.fetchStudioGalleries(studioId: studio.id, sortBy: selectedGallerySortOption, isInitialLoad: true)
        }
        
        if viewModel.studioScenes.isEmpty && !viewModel.isLoadingStudioScenes {
            viewModel.fetchStudioScenes(studioId: studio.id, sortBy: selectedSortOption, isInitialLoad: true)
        }
        
        // Fetch extended content
        viewModel.fetchDetailStudios(parentStudioId: studio.id)
        viewModel.fetchDetailPerformers(studioId: studio.id)
        viewModel.fetchDetailTags(studioId: studio.id)
        viewModel.fetchDetailGroups(studioId: studio.id)
        viewModel.fetchDetailImages(studioId: studio.id, sortBy: selectedImageSortOption)
    }
    
    private var studioGrid: some View {
        LazyVGrid(columns: galleryColumns, spacing: 12) {
            ForEach(viewModel.detailStudios) { subStudio in
                NavigationLink(destination: StudioDetailView(studio: subStudio)) {
                    StudioCardView(studio: subStudio)
                }
                .buttonStyle(.plain)
            }
            if viewModel.isLoadingDetailStudios { ProgressView().padding() }
            else if viewModel.hasMoreDetailStudios {
                Color.clear.onAppear { viewModel.fetchDetailStudios(parentStudioId: studio.id, isInitialLoad: false) }
            }
        }
    }
    
    private var performerGrid: some View {
        LazyVGrid(columns: galleryColumns, spacing: 12) {
            ForEach(viewModel.detailPerformers) { performer in
                NavigationLink(destination: PerformerDetailView(performer: performer)) {
                    PerformerCardView(performer: performer)
                }
                .buttonStyle(.plain)
            }
            if viewModel.isLoadingDetailPerformers {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Loading more performers...").font(.caption).foregroundColor(.secondary)
                }.padding(.vertical, 20)
            } else if viewModel.hasMoreDetailPerformers {
                Color.clear.frame(height: 1).onAppear { 
                    viewModel.fetchDetailPerformers(studioId: studio.id, sortBy: selectedPerformerSortOption, isInitialLoad: false) 
                }
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
                Color.clear.onAppear { viewModel.fetchDetailTags(studioId: studio.id, isInitialLoad: false) }
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
                Color.clear.onAppear { viewModel.fetchDetailGroups(studioId: studio.id, isInitialLoad: false) }
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
                Color.clear.onAppear { viewModel.fetchDetailImages(studioId: studio.id, isInitialLoad: false) }
            }
        }
    }
}

#Preview {
    let sampleStudio = Studio(
        id: "1",
        name: "Sample Studio",
        url: "https://samplestudio.com",
        sceneCount: 25,
        performerCount: 5,
        galleryCount: 10,
        details: "This is a sample studio description that might span multiple lines.",
        imagePath: nil,
        favorite: false,
        rating100: nil,
        createdAt: nil,
        updatedAt: nil
    )
    StudioDetailView(studio: sampleStudio)
}
#endif
