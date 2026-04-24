//
//  CatalogsView.swift
//  stashy
//
//  Created by Daniel Goletz on 13.01.26.
//

#if !os(tvOS)
import SwiftUI

struct CatalogsView: View {
    @ObservedObject var tabManager = TabManager.shared
    @EnvironmentObject var coordinator: NavigationCoordinator
    
    enum CatalogsTab: String, CaseIterable {
        case dashboard = "Dashboard"
        case scenes = "Scenes"
        case images = "Images"
        case galleries = "Galleries"
        case performers = "Performers"
        case studios = "Studios"
        case tags = "Tags"
        case groups = "Groups"
        case markers = "Markers"
        
        var icon: String {
            switch self {
            case .dashboard: return "chart.bar.fill"
            case .scenes: return "film"
            case .images: return "photo"
            case .galleries: return "photo.stack"
            case .performers: return "person.3"
            case .studios: return "building.2"
            case .tags: return "tag"
            case .groups: return "rectangle.stack.fill"
            case .markers: return "bookmark.fill"
            }
        }
    }
    
    private var sortedVisibleTabs: [CatalogsTab] {
        tabManager.tabs
            .filter { ($0.id == .dashboard || $0.id == .performers || $0.id == .studios || $0.id == .tags || $0.id == .scenes || $0.id == .galleries || $0.id == .images || $0.id == .groups || $0.id == .markers) && $0.isVisible }
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { (config: TabConfig) -> CatalogsTab? in
                switch config.id {
                case .dashboard: return .dashboard
                case .scenes: return .scenes
                case .galleries: return .galleries
                case .images: return .images
                case .performers: return .performers
                case .studios: return .studios
                case .tags: return .tags
                case .groups: return .groups
                case .markers: return .markers
                default: return nil
                }
            }
    }
    
    private var selectedTabBinding: Binding<CatalogsTab> {
        Binding(
            get: { effectiveTab ?? .studios },
            set: { coordinator.catalogueSubTab = $0.rawValue }
        )
    }
    
    private var showTabSwitcher: Bool {
        sortedVisibleTabs.count > 1
    }
    
    private var effectiveTab: CatalogsTab? {
        let visible = sortedVisibleTabs
        
        // If current sub-tab is in visible list, use it
        if let current = CatalogsTab(rawValue: coordinator.catalogueSubTab), visible.contains(current) {
            return current
        }
        
        // Otherwise fallback to the first visible one (respecting sortOrder)
        return visible.first
    }
    
    private var effectiveTabRaw: String {
        coordinator.catalogueSubTab
    }
    
    var body: some View {
        Group {
            if let tab = effectiveTab {
                switch tab {
                case .dashboard:
                    HomeView()
                case .scenes:
                    ScenesView()
                case .images:
                    ImagesView()
                case .galleries:
                    GalleriesView()
                case .performers:
                    PerformersView()
                case .studios:
                    StudiosView(hideTitle: false)
                case .tags:
                    TagsView(hideTitle: false)
                case .groups:
                    GroupsView(hideTitle: false)
                case .markers:
                    MarkersView(hideTitle: false)
                }
            } else {
                VStack {
                    Spacer()
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    Text("Please enable Dashboard, Performers, Studios, Tags, Groups or Markers in Settings")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .navigationBarHidden(true)
        .safeAreaInset(edge: .top, spacing: 0) {
            if showTabSwitcher {
                VStack(spacing: 0) {
                    CatalogCategoryRow(tabs: sortedVisibleTabs, selection: selectedTabBinding)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)

                    Divider().overlay(Color.white.opacity(0.15))
                }
                .background(.bar)
                .colorScheme(.dark)
            }
        }
    }
}
#endif

// MARK: - Groups Support Views

#if !os(tvOS)
struct GroupsView: View {
    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @ObservedObject var configManager = ServerConfigManager.shared
    @EnvironmentObject var coordinator: NavigationCoordinator
    @State private var selectedSortOption: StashDBViewModel.GroupSortOption = StashDBViewModel.GroupSortOption(rawValue: TabManager.shared.getSortOption(for: .groups) ?? "") ?? .nameAsc
    @State private var searchText = ""
    @State private var isSearchVisible = false
    @State private var selectedFilter: StashDBViewModel.SavedFilter?
    @State private var lastOpenedGroupId: String?
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    var hideTitle: Bool = false
    
    // Search function
    private func performSearch(isInitialLoad: Bool = true) {
        viewModel.fetchGroups(sortBy: selectedSortOption, searchQuery: searchText, isInitialLoad: isInitialLoad, filter: selectedFilter)
    }

    var body: some View {
        Group {
            if configManager.activeConfig == nil {
                ConnectionErrorView { performSearch() }
            } else if viewModel.isLoadingGroups && viewModel.groups.isEmpty {
                StandardLoadingView(message: "Loading groups...")
            } else if viewModel.groups.isEmpty && viewModel.errorMessage != nil {
                ConnectionErrorView { performSearch() }
            } else if viewModel.groups.isEmpty {
                emptyStateView
            } else {
                groupsGrid
            }
        }
        .navigationTitle("Groups")
        .navigationBarTitleDisplayMode(.inline)
        .applyAppBackground()
        .floatingActionBar {
            HStack(spacing: 0) {
                // Search Pill (if active)
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        performSearch()
                    }) {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                Text(searchText)
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(DesignTokens.Opacity.badge))
                            .clipShape(Capsule())
                        }
                        .frame(maxWidth: .infinity)
                    }

                    // Sort Menu
                    Menu {
                        // Random
                        Button(action: { changeSortOption(to: .random) }) {
                            HStack {
                                Text("Random")
                                if selectedSortOption == .random { Image(systemName: "checkmark") }
                            }
                        }
                        
                        Divider()
                        
                        // Name
                        Menu {
                            Button(action: { changeSortOption(to: .nameAsc) }) {
                                HStack {
                                    Text("A → Z")
                                    if selectedSortOption == .nameAsc { Image(systemName: "checkmark") }
                                }
                            }
                            Button(action: { changeSortOption(to: .nameDesc) }) {
                                HStack {
                                    Text("Z → A")
                                    if selectedSortOption == .nameDesc { Image(systemName: "checkmark") }
                                }
                            }
                        } label: {
                            HStack {
                                Text("Name")
                                if selectedSortOption == .nameAsc || selectedSortOption == .nameDesc { Image(systemName: "checkmark") }
                            }
                        }

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

                        // Counts
                        Menu {
                            Button(action: { changeSortOption(to: .sceneCountDesc) }) {
                                HStack {
                                    Text("Scenes (High → Low)")
                                    if selectedSortOption == .sceneCountDesc { Image(systemName: "checkmark") }
                                }
                            }
                            Button(action: { changeSortOption(to: .galleryCountDesc) }) {
                                HStack {
                                    Text("Galleries (High → Low)")
                                    if selectedSortOption == .galleryCountDesc { Image(systemName: "checkmark") }
                                }
                            }
                            Button(action: { changeSortOption(to: .performerCountDesc) }) {
                                HStack {
                                    Text("Performers (High → Low)")
                                    if selectedSortOption == .performerCountDesc { Image(systemName: "checkmark") }
                                }
                            }
                        } label: {
                            HStack {
                                Text("Counts")
                                if selectedSortOption == .sceneCountDesc || selectedSortOption == .galleryCountDesc || selectedSortOption == .performerCountDesc { Image(systemName: "checkmark") }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(appearanceManager.tintColor)
                    }
                    .frame(maxWidth: .infinity)

                    // Filter Menu
                    Menu {
                        Button(action: {
                            selectedFilter = nil
                            performSearch()
                        }) {
                            HStack {
                                Text("No Filter")
                                if selectedFilter == nil { Image(systemName: "checkmark") }
                            }
                        }

                        let activeFilters = viewModel.savedFilters.values
                            .filter { $0.mode == .groups }
                            .sorted { $0.name < $1.name }
                        
                        ForEach(activeFilters) { filter in
                            Button(action: {
                                selectedFilter = filter
                                performSearch()
                            }) {
                                HStack {
                                    Text(filter.name)
                                    if selectedFilter?.id == filter.id { Image(systemName: "checkmark") }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(selectedFilter != nil ? appearanceManager.tintColor : .primary)
                    }
                    .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            viewModel.fetchSavedFilters()
            
            // Initial fetch if empty
            if viewModel.groups.isEmpty {
                // If no default filter is set, fetch immediately
                if TabManager.shared.getDefaultFilterId(for: .groups) == nil {
                    performSearch()
                }
            }
        }
        .onChange(of: viewModel.savedFilters) { oldValue, newValue in
            // Apply default filter if set and none selected yet
            if selectedFilter == nil {
                if let defaultId = TabManager.shared.getDefaultFilterId(for: .groups),
                   let filter = newValue[defaultId] {
                    selectedFilter = filter
                    if viewModel.groups.isEmpty {
                        performSearch()
                    }
                } else if !viewModel.isLoadingSavedFilters && viewModel.groups.isEmpty {
                    performSearch()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DefaultSortChanged"))) { notification in
            if let tabId = notification.userInfo?["tab"] as? String, tabId == AppTab.groups.rawValue {
                let newSort = StashDBViewModel.GroupSortOption(rawValue: TabManager.shared.getPersistentSortOption(for: .groups) ?? "") ?? .nameAsc
                changeSortOption(to: newSort)
            }
        }
        .onChange(of: searchText) { oldValue, newValue in
            NSObject.cancelPreviousPerformRequests(withTarget: self)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if newValue == self.searchText {
                    performSearch()
                }
            }
        }
    }

    private func changeSortOption(to newOption: StashDBViewModel.GroupSortOption) {
        if newOption == .random && selectedSortOption == .random {
            viewModel.refreshRandomSeed()
        }
        selectedSortOption = newOption
        TabManager.shared.setSortOption(for: .groups, option: newOption.rawValue)
        performSearch()
    }

    private var emptyStateView: some View {
        SharedEmptyStateView(
            icon: "rectangle.stack.fill",
            title: "No groups found",
            buttonText: "Load Groups",
            onRetry: { performSearch() }
        )
    }

    private var columns: [GridItem] {
        if horizontalSizeClass == .regular {
            // iPad: 4 columns
            return Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
        } else {
            // iPhone: 2 columns
            return [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ]
        }
    }

    private var groupsGrid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(viewModel.groups) { group in
                        NavigationLink(destination: GroupDetailView(selectedGroup: group)) {
                            GroupCardView(group: group)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .id(group.id)
                        .simultaneousGesture(TapGesture().onEnded {
                            lastOpenedGroupId = group.id
                        })
                    }

                    // Loading indicator for pagination
                    if viewModel.isLoadingMoreGroups {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else if viewModel.hasMoreGroups && !viewModel.groups.isEmpty {
                        Color.clear
                            .frame(height: 1)
                            .onAppear {
                                viewModel.loadMoreGroups()
                            }
                            .id("pagination-trigger")
                    }
                }
                .padding(16)
            }
            .refreshable { performSearch() }
            .onAppear {
                if let id = lastOpenedGroupId {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        proxy.scrollTo(id, anchor: .top)
                    }
                }
            }
        }
    }
}

struct GroupCardView: View {
    let group: StashGroup
    @ObservedObject var appearanceManager = AppearanceManager.shared
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Image
            GeometryReader { geometry in
                ZStack {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))

                    if let url = group.thumbnailURL {
                        CustomAsyncImage(url: url) { loader in
                            if loader.isLoading {
                                ProgressView()
                            } else if let image = loader.image {
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                                    .clipped()
                            } else {
                                placeholderImageContent
                            }
                        }
                    } else {
                        placeholderImageContent
                    }
                }
            }
            .aspectRatio(9/12, contentMode: .fit) 
            
            // Gradient Overlay
            LinearGradient(
                gradient: Gradient(colors: [.clear, .black.opacity(0.8)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 100)
            
            // Top Badges
            VStack {
                HStack(spacing: 8) {
                    Spacer()
                    // Gallery Badge (if available)
                    if let galleryCount = group.gallery_count, galleryCount > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "photo.stack")
                                .font(.system(size: 10, weight: .bold))
                            Text("\(galleryCount)")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(DesignTokens.Opacity.badge))
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.2), radius: 2)
                    }

                    // Scenes Badge
                    if let count = group.scene_count {
                        HStack(spacing: 3) {
                            Image(systemName: "film")
                                .font(.system(size: 10, weight: .bold))
                            Text("\(count)")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(DesignTokens.Opacity.badge))
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.2), radius: 2)
                    }
                }
                .padding(8)
                Spacer()
            }
            
            // Info Section (Bottom Name)
            VStack(alignment: .leading, spacing: 4) {
                 HStack(alignment: .bottom, spacing: 6) {
                    Text(group.name)
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
        }
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .cardShadow()
    }
    
    private var placeholderImageContent: some View {
        Image(systemName: "rectangle.stack")
            .font(.largeTitle)
            .foregroundColor(.secondary)
    }
}

struct GroupDetailView: View {
    let selectedGroup: StashGroup
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @ObservedObject var configManager = ServerConfigManager.shared
    @StateObject private var viewModel = StashDBViewModel()
    @EnvironmentObject var coordinator: NavigationCoordinator
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var groupLiveFilterSheetPresented = false
    @State private var selectedGallerySortOption: StashDBViewModel.GallerySortOption = .dateDesc
    @State private var selectedImageSortOption: StashDBViewModel.ImageSortOption = .dateDesc
    
    enum DetailTab: String, CaseIterable {
        case scenes = "Scenes"
        case galleries = "Galleries"
        case performers = "Performers"
        case studios = "Studios"
        case tags = "Tags"
        case images = "Images"
    }
    @State private var selectedDetailTab: DetailTab

    init(selectedGroup: StashGroup) {
        self.selectedGroup = selectedGroup
        let sc = selectedGroup.scene_count ?? 0
        let gal = selectedGroup.gallery_count ?? 0
        _selectedDetailTab = State(initialValue: sc > 0 ? .scenes : (gal > 0 ? .galleries : .scenes))
    }

    private var effectiveScenes: Int {
        max(viewModel.totalGroupScenes, selectedGroup.scene_count ?? 0)
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

    private var effectiveGalleries: Int {
        max(viewModel.totalGroupGalleries, selectedGroup.gallery_count ?? 0)
    }

    private var availableTabs: [DetailTab] {
        var tabs: [DetailTab] = []
        if effectiveScenes > 0 { tabs.append(.scenes) }
        if effectiveGalleries > 0 { tabs.append(.galleries) }
        if viewModel.totalDetailPerformers > 0 { tabs.append(.performers) }
        if viewModel.totalDetailStudios > 0 { tabs.append(.studios) }
        if viewModel.totalDetailTags > 0 { tabs.append(.tags) }
        if viewModel.totalDetailImages > 0 { tabs.append(.images) }
        return tabs
    }

    private var showTabSwitcher: Bool {
        availableTabs.count > 1
    }

    @ViewBuilder
    private var groupScenesStack: some View {
        VStack(spacing: 12) {
            headerView
                .padding(.horizontal, 16)
                .padding(.top, 8)
            ScenesView(
                hideTitle: true,
                scope: .group(groupId: selectedGroup.id),
                sharedViewModel: viewModel,
                externalLiveFilterSheetBinding: $groupLiveFilterSheetPresented,
                showsFloatingFilterButton: false
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var nonScenesGroupScroll: some View {
        ScrollView {
            VStack(spacing: 12) {
                headerView

                if selectedDetailTab == .galleries {
                    if !viewModel.groupGalleries.isEmpty {
                        galleryGrid
                    } else if viewModel.isLoadingGroupGalleries {
                        VStack {
                            ProgressView()
                            Text("Loading galleries...").font(.caption).foregroundColor(.secondary)
                        }.padding(.top, 40)
                    } else {
                        Text("No galleries found").foregroundColor(.secondary).padding(.top, 40)
                    }
                } else if selectedDetailTab == .performers {
                    performerGrid
                } else if selectedDetailTab == .studios {
                    studioGrid
                } else if selectedDetailTab == .tags {
                    tagGrid
                } else if selectedDetailTab == .images {
                    imageGrid
                }
            }
        }
        .background(Color.appBackground)
    }

    var body: some View {
        Group {
            if selectedDetailTab == .scenes {
                groupScenesStack
            } else {
                nonScenesGroupScroll
            }
        }
        .background(Color.appBackground)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(selectedGroup.name)
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
                if selectedDetailTab == .scenes {
                    Button {
                        HapticManager.light()
                        groupLiveFilterSheetPresented = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(appearanceManager.tintColor)
                    }
                    .accessibilityLabel("Filter and sort")
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
        .onAppear {
            if viewModel.groupGalleries.isEmpty {
                viewModel.fetchGroupGalleries(groupId: selectedGroup.id, sortBy: selectedGallerySortOption, isInitialLoad: true)
            }
            
            // Fetch extended content
            viewModel.fetchDetailPerformers(groupId: selectedGroup.id)
            viewModel.fetchDetailStudios(groupId: selectedGroup.id)
            viewModel.fetchDetailTags(groupId: selectedGroup.id)
            viewModel.fetchDetailImages(groupId: selectedGroup.id, sortBy: selectedImageSortOption)
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
            if viewModel.isLoadingDetailPerformers { ProgressView().padding() }
            else if viewModel.hasMoreDetailPerformers {
                Color.clear.onAppear { viewModel.fetchDetailPerformers(groupId: selectedGroup.id, isInitialLoad: false) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
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
                Color.clear.onAppear { viewModel.fetchDetailStudios(groupId: selectedGroup.id, isInitialLoad: false) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
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
                Color.clear.onAppear { viewModel.fetchDetailTags(groupId: selectedGroup.id, isInitialLoad: false) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
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
                Color.clear.onAppear { viewModel.fetchDetailImages(groupId: selectedGroup.id, isInitialLoad: false) }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
    }

    private func changeGallerySortOption(to option: StashDBViewModel.GallerySortOption) {
        if option == .random && selectedGallerySortOption == .random {
            viewModel.refreshRandomSeed()
        }
        selectedGallerySortOption = option
        viewModel.fetchGroupGalleries(groupId: selectedGroup.id, sortBy: option, isInitialLoad: true)
    }

    private func changeImageSortOption(to option: StashDBViewModel.ImageSortOption) {
        if option == .random && selectedImageSortOption == .random {
            viewModel.refreshRandomSeed()
        }
        selectedImageSortOption = option
        viewModel.fetchDetailImages(groupId: selectedGroup.id, sortBy: option, isInitialLoad: true)
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

    private var galleryGrid: some View {
        LazyVGrid(columns: galleryColumns, spacing: 12) {
             ForEach(viewModel.groupGalleries) { gallery in
                 NavigationLink(destination: ImagesView(gallery: gallery)) {
                     GalleryCardView(gallery: gallery)
                 }
                 .buttonStyle(.plain)
             }
             if viewModel.isLoadingGroupGalleries {
                 VStack(spacing: 8) {
                    ProgressView()
                    Text("Loading more galleries...").font(.caption).foregroundColor(.secondary)
                }.padding(.vertical, 20)
             } else if viewModel.hasMoreGroupGalleries {
                 Color.clear.frame(height: 1).onAppear { viewModel.loadMoreGroupGalleries(groupId: selectedGroup.id) }
             }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 32)
    }

    @State private var isHeaderExpanded = false
    
    private var headerView: some View {
        let collapsedHeight: CGFloat = 115
        let imageWidth: CGFloat = 72
        
        return HStack(alignment: .top, spacing: 0) {
            // Thumbnail: 9:16 portrait
            ZStack(alignment: .bottom) {
                if let url = selectedGroup.thumbnailURL {
                    CustomAsyncImage(url: url) { loader in
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
                // Header: Name
                Text(selectedGroup.name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(isHeaderExpanded ? nil : 2)
                
                // Grid for Group Info
                let allDetails = getGroupDetails()
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
                
                if isHeaderExpanded && !(selectedGroup.synopsis ?? "").isEmpty {
                    Text("Synopsis")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .padding(.top, 4)
                    Text(selectedGroup.synopsis ?? "")
                        .font(.system(size: 11))
                        .foregroundColor(.primary)
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
        .padding(.horizontal, 16)
        .overlay(
            Group {
                let allDetails = getGroupDetails()
                if allDetails.count > 4 || !(selectedGroup.synopsis ?? "").isEmpty {
                    Button(action: {
                        withAnimation(.spring()) {
                            isHeaderExpanded.toggle()
                        }
                    }) {
                        Image(systemName: isHeaderExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(appearanceManager.tintColor)
                            .padding(6)
                            .background(appearanceManager.tintColor.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .padding(.trailing, 24)
                    .padding(.bottom, 8)
                }
            },
            alignment: .bottomTrailing
        )
    }

    private func defaultThumbnailContent(width: CGFloat) -> some View {
        Rectangle().fill(Color.gray.opacity(DesignTokens.Opacity.placeholder))
            .frame(width: width)
            .frame(maxHeight: .infinity)
            .overlay(Image(systemName: "rectangle.stack").font(.system(size: 24)).foregroundColor(.appAccent.opacity(0.5)))
    }

    private func getGroupDetails() -> [(label: String, value: String)] {
        var list: [(label: String, value: String)] = []
        list.append((label: "SCENES", value: "\(viewModel.totalGroupScenes)"))
        if effectiveGalleries > 0 {
            list.append((label: "GALLERIES", value: "\(effectiveGalleries)"))
        }
        if let studio = selectedGroup.studio {
            list.append((label: "STUDIO", value: studio.name))
        }
        if let date = selectedGroup.date {
            list.append((label: "DATE", value: date))
        }
        if let rating = selectedGroup.rating100 {
            list.append((label: "RATING", value: "\(rating)%"))
        }
        return list
    }
}
#endif
