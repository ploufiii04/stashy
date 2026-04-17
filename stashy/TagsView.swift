//
//  TagsView.swift
//  stashy
//
//  Created by Daniel Goletz on 13.01.26.
//

#if !os(tvOS)
import SwiftUI

struct TagsView: View {
    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @ObservedObject var configManager = ServerConfigManager.shared
    @EnvironmentObject var coordinator: NavigationCoordinator
    @State private var selectedSortOption: StashDBViewModel.TagSortOption = StashDBViewModel.TagSortOption(rawValue: TabManager.shared.getSortOption(for: .tags) ?? "") ?? .sceneCountDesc
    @State private var selectedFilter: StashDBViewModel.SavedFilter? = nil
    @State private var isChangingSort = false
    @State private var searchText = ""
    @State private var isSearchVisible = false
    var hideTitle: Bool = false
    
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var columns: [GridItem] {
        if horizontalSizeClass == .regular {
            return Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
        } else {
            return [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        }
    }

    // Search function
    private func performSearch(isInitialLoad: Bool = true) {
        viewModel.fetchTags(sortBy: selectedSortOption, searchQuery: searchText, isInitialLoad: isInitialLoad, filter: selectedFilter)
    }

    var body: some View {
        Group {
            if configManager.activeConfig == nil {
                ConnectionErrorView { performSearch() }
            } else if (viewModel.isLoading && viewModel.tags.isEmpty) || (viewModel.isLoadingSavedFilters && viewModel.savedFilters.isEmpty) {
                VStack {
                    Spacer()
                    ProgressView("Loading tags...")
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if viewModel.tags.isEmpty && viewModel.errorMessage != nil {
                ConnectionErrorView { performSearch() }
            } else if viewModel.tags.isEmpty {
                emptyStateView
            } else {
                tagsList
            }
        }
        .navigationTitle(hideTitle ? "" : "Tags")
        .navigationBarTitleDisplayMode(.inline)
        .conditionalSearchable(isVisible: isSearchVisible, text: $searchText, prompt: "Search tags...")
        .onChange(of: searchText) { oldValue, newValue in
            // Debounce
            NSObject.cancelPreviousPerformRequests(withTarget: self)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if newValue == self.searchText {
                    self.performSearch()
                }
            }
        }
        .toolbar {
            if !searchText.isEmpty {
                ToolbarItem(placement: .principal) {
                    Button(action: {
                        searchText = ""
                        performSearch()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                            Text(searchText)
                                .font(.system(size: 12, weight: .bold))
                                .lineLimit(1)
                        }
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(DesignTokens.Opacity.badge))
                        .clipShape(Capsule())
                    }
                }
            }
            
        }
        .floatingActionBar {
            HStack(spacing: 0) {
                // Sort Menu with grouped options
                Menu {
                        // Random
                        Button(action: {
                            if selectedSortOption == .random {
                                viewModel.refreshRandomSeed()
                            }
                            selectedSortOption = .random
                            TabManager.shared.setSortOption(for: .tags, option: StashDBViewModel.TagSortOption.random.rawValue)
                            performSearch()
                        }) {
                            HStack {
                                Text("Random")
                                if selectedSortOption == .random { Image(systemName: "checkmark") }
                            }
                        }
                        
                        Divider()
                        
                        // Name
                        Menu {
                            Button(action: {
                                selectedSortOption = .nameAsc
                                TabManager.shared.setSortOption(for: .tags, option: StashDBViewModel.TagSortOption.nameAsc.rawValue)
                                performSearch()
                            }) {
                                HStack {
                                    Text("A → Z")
                                    if selectedSortOption == .nameAsc { Image(systemName: "checkmark") }
                                }
                            }
                            Button(action: {
                                selectedSortOption = .nameDesc
                                TabManager.shared.setSortOption(for: .tags, option: StashDBViewModel.TagSortOption.nameDesc.rawValue)
                                performSearch()
                            }) {
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
                        
                        // Scene Count
                        Menu {
                            Button(action: {
                                selectedSortOption = .sceneCountDesc
                                TabManager.shared.setSortOption(for: .tags, option: StashDBViewModel.TagSortOption.sceneCountDesc.rawValue)
                                performSearch()
                            }) {
                                HStack {
                                    Text("High → Low")
                                    if selectedSortOption == .sceneCountDesc { Image(systemName: "checkmark") }
                                }
                            }
                            Button(action: {
                                selectedSortOption = .sceneCountAsc
                                TabManager.shared.setSortOption(for: .tags, option: StashDBViewModel.TagSortOption.sceneCountAsc.rawValue)
                                performSearch()
                            }) {
                                HStack {
                                    Text("Low → High")
                                    if selectedSortOption == .sceneCountAsc { Image(systemName: "checkmark") }
                                }
                            }
                        } label: {
                            HStack {
                                Text("Scene Count")
                                if selectedSortOption == .sceneCountAsc || selectedSortOption == .sceneCountDesc { Image(systemName: "checkmark") }
                            }
                        }
                        
                        // Updated
                        Menu {
                            Button(action: {
                                selectedSortOption = .updatedAtDesc
                                TabManager.shared.setSortOption(for: .tags, option: StashDBViewModel.TagSortOption.updatedAtDesc.rawValue)
                                performSearch()
                            }) {
                                HStack {
                                    Text("Newest First")
                                    if selectedSortOption == .updatedAtDesc { Image(systemName: "checkmark") }
                                }
                            }
                            Button(action: {
                                selectedSortOption = .updatedAtAsc
                                TabManager.shared.setSortOption(for: .tags, option: StashDBViewModel.TagSortOption.updatedAtAsc.rawValue)
                                performSearch()
                            }) {
                                HStack {
                                    Text("Oldest First")
                                    if selectedSortOption == .updatedAtAsc { Image(systemName: "checkmark") }
                                }
                            }
                        } label: {
                            HStack {
                                Text("Updated")
                                if selectedSortOption == .updatedAtAsc || selectedSortOption == .updatedAtDesc { Image(systemName: "checkmark") }
                            }
                        }
                        
                        // Created
                        Menu {
                            Button(action: {
                                selectedSortOption = .createdAtDesc
                                TabManager.shared.setSortOption(for: .tags, option: StashDBViewModel.TagSortOption.createdAtDesc.rawValue)
                                performSearch()
                            }) {
                                HStack {
                                    Text("Newest First")
                                    if selectedSortOption == .createdAtDesc { Image(systemName: "checkmark") }
                                }
                            }
                            Button(action: {
                                selectedSortOption = .createdAtAsc
                                TabManager.shared.setSortOption(for: .tags, option: StashDBViewModel.TagSortOption.createdAtAsc.rawValue)
                                performSearch()
                            }) {
                                HStack {
                                    Text("Oldest First")
                                    if selectedSortOption == .createdAtAsc { Image(systemName: "checkmark") }
                                }
                            }
                        } label: {
                            HStack {
                                Text("Created")
                                if selectedSortOption == .createdAtAsc || selectedSortOption == .createdAtDesc { Image(systemName: "checkmark") }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
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
                                if selectedFilter == nil {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        
                        let tagFilters = viewModel.savedFilters.values
                            .filter { $0.mode == .tags }
                            .sorted { $0.name < $1.name }
                        
                        ForEach(tagFilters) { filter in
                            Button(action: {
                                selectedFilter = filter
                                performSearch()
                            }) {
                                HStack {
                                    Text(filter.name)
                                    if selectedFilter?.id == filter.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: selectedFilter != nil ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .foregroundColor(selectedFilter != nil ? appearanceManager.tintColor : .primary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        .onAppear {
            // Check for search text from navigation
            if !coordinator.activeSearchText.isEmpty {
                searchText = coordinator.activeSearchText
                isSearchVisible = true
                coordinator.activeSearchText = ""
                performSearch()
                viewModel.fetchSavedFilters()
                return
            }
            
            if TabManager.shared.getDefaultFilterId(for: .tags) == nil || !viewModel.savedFilters.isEmpty {
                if viewModel.tags.isEmpty {
                    performSearch()
                }
            }
            viewModel.fetchSavedFilters()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DefaultFilterChanged"))) { notification in
            if let tabId = notification.userInfo?["tab"] as? String, tabId == AppTab.tags.rawValue {
                if let defaultId = TabManager.shared.getDefaultFilterId(for: .tags),
                   let newFilter = viewModel.savedFilters[defaultId] {
                    selectedFilter = newFilter
                } else {
                    selectedFilter = nil
                }
                performSearch()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DefaultSortChanged"))) { notification in
            if let tabId = notification.userInfo?["tab"] as? String, tabId == AppTab.tags.rawValue {
                let newSort = StashDBViewModel.TagSortOption(rawValue: TabManager.shared.getPersistentSortOption(for: .tags) ?? "") ?? .sceneCountDesc
                selectedSortOption = newSort
                performSearch()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
            selectedFilter = nil
            performSearch()
        }
        .onChange(of: viewModel.savedFilters) { oldValue, newValue in
            // Apply default filter if set and none selected yet
            if selectedFilter == nil {
                if let defaultId = TabManager.shared.getDefaultFilterId(for: .tags),
                   let filter = newValue[defaultId] {
                    selectedFilter = filter
                    performSearch()
                } else if !viewModel.isLoadingSavedFilters {
                    // Default filter was set but not found, or filters finished loading and none match
                    performSearch()
                }
            }
        }
        .onChange(of: viewModel.isLoadingSavedFilters) { oldValue, isLoading in
            if oldValue == true && isLoading == false {
                if viewModel.tags.isEmpty && !viewModel.isLoading && selectedFilter == nil {
                    performSearch()
                }
            }
        }
    }

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView("Loading tags...")
            Spacer()
        }
    }

    private var emptyStateView: some View {
        SharedEmptyStateView(
            icon: "tag.fill",
            title: "No tags found",
            buttonText: "Load Tags",
            onRetry: { performSearch() }
        )
    }

    private var tagsList: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(viewModel.tags) { tag in
                    NavigationLink(destination: TagDetailView(selectedTag: tag)) {
                        TagCardView(tag: tag)
                    }
                    .buttonStyle(.plain)
                }
                
                // Loading indicator for pagination
                if viewModel.isLoadingMoreTags {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                } else if viewModel.hasMoreTags && !viewModel.tags.isEmpty {
                    Color.clear
                        .frame(height: 1)
                        .onAppear {
                            viewModel.loadMoreTags()
                        }
                }
            }
            .padding(16)
            .padding(.bottom, 70) // Leave space for floating bar
        }
        .refreshable { performSearch() }
    }
}

struct TagCardView: View {
    let tag: Tag
    @ObservedObject var appearanceManager = AppearanceManager.shared

    private var hasCustomImage: Bool {
        tag.imagePath != nil && tag.imagePath?.contains("default") != true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Image Block (Top)
            Color.studioHeaderGray
                .aspectRatio(2.2, contentMode: .fit)
                .overlay(
                    Group {
                        if hasCustomImage {
                            TagImageView(tag: tag)
                        } else {
                            Image(systemName: "number")
                                .font(.system(size: 32, weight: .bold))
                                .foregroundColor(appearanceManager.tintColor)
                        }
                    }
                )
                .clipped()

            // Name & Count Area (Below)
            HStack(spacing: 8) {
                Text(tag.name)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()

                HStack(spacing: 8) {
                    if let sceneCount = tag.sceneCount, sceneCount > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "film")
                                .font(.system(size: 10))
                            Text("\(sceneCount)")
                                .font(.system(size: 11, weight: .medium))
                        }
                    }
                    if let galleryCount = tag.galleryCount, galleryCount > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "photo.stack")
                                .font(.system(size: 10))
                            Text("\(galleryCount)")
                                .font(.system(size: 11, weight: .medium))
                        }
                    }
                }
                .foregroundColor(.secondary)
                .layoutPriority(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .cardShadow()
    }
}

struct TagDetailView: View {
    let selectedTag: Tag
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @ObservedObject var configManager = ServerConfigManager.shared
    @ObservedObject var tabManager = TabManager.shared
    @StateObject private var viewModel = StashDBViewModel()
    @EnvironmentObject var coordinator: NavigationCoordinator
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedSortOption: StashDBViewModel.SceneSortOption = StashDBViewModel.SceneSortOption(rawValue: TabManager.shared.getDetailSortOption(for: "tag_detail") ?? "") ?? .dateDesc
    @State private var isChangingSort = false
    @State private var isFavorite: Bool = false
    @State private var isUpdatingFavorite: Bool = false
    @State private var isHeaderExpanded = false
    
    enum DetailTab: String, CaseIterable {
        case scenes = "Scenes"
        case galleries = "Galleries"
    }
    @State private var selectedDetailTab: DetailTab = .scenes

    // Safe sort change function
    private func changeSortOption(to newOption: StashDBViewModel.SceneSortOption) {
        if newOption == .random && selectedSortOption == .random {
            viewModel.refreshRandomSeed()
        }
        guard !isChangingSort else { return }

        isChangingSort = true
        selectedSortOption = newOption

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            TabManager.shared.setDetailSortOption(for: "tag_detail", option: newOption.rawValue)
            
            // Use existing filter if we have one loaded in viewModel, but we can't access it easily outside.
            // However, fetchTagScenes will use the internal `currentTagDetailFilter` if isInitialLoad is false?
            // No, fetchTagScenes takes `filter` arg. Only if isInitialLoad is TRUE does it store it.
            // If isInitialLoad is TRUE, I MUST pass the filter again if I want to persist it?
            // Yes, my implementation overwrite `currentTagDetailFilter = filter` on initial load.
            
            // But wait, here I am calling with isInitialLoad: true to reset pagination/sort.
            // So I need to retrieve the filter again.
            
            self.viewModel.fetchTagScenes(tagId: self.selectedTag.id, sortBy: newOption, isInitialLoad: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.isChangingSort = false
            }
        }
    }
    
    private var columns: [GridItem] {
        if verticalSizeClass == .compact {
             return [
                 GridItem(.flexible(), spacing: 12),
                 GridItem(.flexible(), spacing: 12)
             ]
        } else if horizontalSizeClass == .regular {
            // iPad: 4 columns
            return Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
        } else {
            // iPhone: 1 column
            return [
                GridItem(.flexible(), spacing: 12)
            ]
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
    
    private var effectiveScenes: Int {
        max(viewModel.totalTagScenes, selectedTag.sceneCount ?? 0)
    }
    
    private var effectiveGalleries: Int {
        max(viewModel.totalTagGalleries, selectedTag.galleryCount ?? 0)
    }
    
    private var showTabSwitcher: Bool {
        effectiveScenes > 0 && effectiveGalleries > 0
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                tagHeaderView
                
                if selectedDetailTab == .scenes {
                    if !viewModel.tagScenes.isEmpty {
                        sceneGrid
                    } else if viewModel.isLoadingTagScenes {
                        VStack {
                            ProgressView()
                            Text("Loading scenes...").font(.caption).foregroundColor(.secondary)
                        }.padding(.top, 40)
                    } else {
                        Text("No scenes found").foregroundColor(.secondary).padding(.top, 40)
                    }
                } else {
                    if !viewModel.tagGalleries.isEmpty {
                        galleryGrid
                    } else if viewModel.isLoadingTagGalleries {
                        VStack {
                            ProgressView()
                            Text("Loading galleries...").font(.caption).foregroundColor(.secondary)
                        }.padding(.top, 40)
                    } else {
                        Text("No galleries found").foregroundColor(.secondary).padding(.top, 40)
                    }
                }
            }
            .padding(16)
        }
        .applyAppBackground()
        .onAppear {
            loadDetailData()
            isFavorite = selectedTag.favorite ?? false
        }
        .onChange(of: viewModel.totalTagGalleries) { oldValue, newValue in
            if !viewModel.isLoadingTagScenes && viewModel.totalTagScenes == 0 && newValue > 0 {
                withAnimation(DesignTokens.Animation.quick) { selectedDetailTab = .galleries }
            }
        }
        .onChange(of: viewModel.totalTagScenes) { oldValue, newValue in
            if newValue > 0 {
                withAnimation(DesignTokens.Animation.quick) { selectedDetailTab = .scenes }
            } else if newValue == 0 && viewModel.totalTagGalleries > 0 {
                withAnimation(DesignTokens.Animation.quick) { selectedDetailTab = .galleries }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if showTabSwitcher {
                    Picker("View", selection: $selectedDetailTab) {
                        Text("Scenes").tag(DetailTab.scenes)
                        Text("Galleries").tag(DetailTab.galleries)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                } else {
                    Text(selectedTag.name)
                        .font(.headline)
                        .lineLimit(1)
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

                    viewModel.toggleTagFavorite(tagId: selectedTag.id, favorite: newState) { success in
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
                }
            }
        }
    }
    
    // MARK: - Subviews & Logic
    
    private func loadDetailData() {
        if viewModel.tagScenes.isEmpty && !viewModel.isLoadingTagScenes {
            viewModel.fetchTagScenes(tagId: selectedTag.id, sortBy: selectedSortOption, isInitialLoad: true)
        }
        if viewModel.tagGalleries.isEmpty && !viewModel.isLoadingTagGalleries {
            viewModel.fetchTagGalleries(tagId: selectedTag.id, isInitialLoad: true)
        }
        
        // Update favorite status from server
        viewModel.fetchTag(tagId: selectedTag.id) { updatedTag in
            if let tag = updatedTag {
                self.isFavorite = tag.favorite ?? false
            }
        }
    }
    
    private var tagHeaderView: some View {
        let collapsedHeight: CGFloat = 115
        let imageWidth: CGFloat = 72
        
        return HStack(alignment: .top, spacing: 0) {
            // Thumbnail: 9:16 portrait style strip, flush to edges
            ZStack(alignment: .bottom) {
                TagImageView(tag: selectedTag)
                    .frame(width: imageWidth)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
            .frame(width: imageWidth)
            .frame(minHeight: collapsedHeight)
            .frame(maxHeight: isHeaderExpanded ? .infinity : collapsedHeight)
            .background(Color.gray.opacity(DesignTokens.Opacity.placeholder))
            
            // Details Section
            VStack(alignment: .leading, spacing: 4) {
                // Header: Name and Stats
                HStack(alignment: .top, spacing: 8) {
                    Text(selectedTag.name)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .lineLimit(isHeaderExpanded ? nil : 1)
                    
                    Spacer()
                    
                    // StashTok Button (Top Right)
                    if tabManager.tabs.first(where: { $0.id == .reels })?.isVisible ?? true {
                        Button(action: {
                            coordinator.navigateToReels(tags: [selectedTag])
                        }) {
                            Image(systemName: "play.rectangle.on.rectangle")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Color.pillAccent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(appearanceManager.tintColor.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                }
                
                // Grid for Tag Info
                let allDetails = getTagDetails(selectedTag)
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
                
                if let desc = selectedTag.description, !desc.isEmpty, isHeaderExpanded {
                    Text(desc)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
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
                let allDetails = getTagDetails(selectedTag)
                if allDetails.count > 4 || (selectedTag.description?.count ?? 0) > 0 {
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
    
    private func getTagDetails(_ t: Tag) -> [(label: String, value: String)] {
        var list: [(label: String, value: String)] = []
        
        list.append((label: "SCENES", value: "\(effectiveScenes)"))
        if effectiveGalleries > 0 {
            list.append((label: "GALLERIES", value: "\(effectiveGalleries)"))
        }
        
        if let val = t.performerCount, val > 0 {
            list.append((label: "PERFORMERS", value: "\(val)"))
        }
        
        if let val = t.sceneMarkerCount, val > 0 {
            list.append((label: "MARKERS", value: "\(val)"))
        }
        
        if let created = t.createdAt, !created.isEmpty {
            let date = created.prefix(10)
            list.append((label: "CREATED", value: String(date)))
        }
        
        if let updated = t.updatedAt, !updated.isEmpty {
            let date = updated.prefix(10)
            list.append((label: "UPDATED", value: String(date)))
        }
        
        return list
    }
    
    private var sceneGrid: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(viewModel.tagScenes) { scene in
                NavigationLink(destination: SceneDetailView(scene: scene)) {
                    SceneCardView(scene: scene)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            
            if viewModel.isLoadingTagScenes {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if viewModel.hasMoreTagScenes {
                Color.clear
                    .frame(height: 1)
                    .onAppear {
                        viewModel.loadMoreTagScenes(tagId: selectedTag.id)
                    }
            }
        }
    }
    
    private var galleryGrid: some View {
        LazyVGrid(columns: galleryColumns, spacing: 12) {
            ForEach(viewModel.tagGalleries) { gallery in
                NavigationLink(destination: ImagesView(gallery: gallery)) {
                    GalleryCardView(gallery: gallery)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            
            if viewModel.isLoadingMoreTagGalleries {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if viewModel.hasMoreTagGalleries {
                Color.clear
                    .frame(height: 1)
                    .onAppear {
                        viewModel.loadMoreTagGalleries(tagId: selectedTag.id)
                    }
            }
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
                // ... (existing menu items)
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
                .foregroundColor(appearanceManager.tintColor)
        }
    }
}

struct TagImageView: View {
    let tag: Tag
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @State private var imageLoadState: ImageLoadState = .loading

    enum ImageLoadState {
        case loading
        case success(Image)
        case successSVG(Data, String)
        case failure
    }

    private var imageURL: URL? {
        guard let config = ServerConfigManager.shared.loadConfig() else { return nil }
        return URL(string: "\(config.baseURL)/tag/\(tag.id)/image")
    }

    var body: some View {
        CustomAsyncImage(url: tag.thumbnailURL) { loader in
            if loader.isLoading {
                Rectangle()
                    .fill(appearanceManager.tintColor)
                    .overlay(ProgressView().tint(.white))
            } else if let image = loader.image {
                image
                    .resizable()
                    .scaledToFill()
            } else if let data = loader.imageData, isSVG(data) {
                let dataString = String(data: data, encoding: .utf8) ?? ""
                ZStack {
                    SVGWebView(svgData: data, svgString: dataString)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Color.clear.contentShape(Rectangle())
                }
            } else {
                Rectangle()
                    .fill(appearanceManager.tintColor)
                    .overlay(
                        Image(systemName: "number")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.white)
                    )
            }
        }
    }

    private func isSVG(_ data: Data) -> Bool {
        let str = String(data: data.prefix(100), encoding: .utf8) ?? ""
        return str.lowercased().contains("<svg")
    }
}
#endif

