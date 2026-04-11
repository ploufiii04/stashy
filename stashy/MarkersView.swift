//
//  MarkersView.swift
//  stashy
//

#if !os(tvOS)
import SwiftUI

struct MarkersView: View {
    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @ObservedObject var configManager = ServerConfigManager.shared
    @EnvironmentObject var coordinator: NavigationCoordinator
    
    @State private var selectedSortOption: StashDBViewModel.SceneMarkerSortOption = StashDBViewModel.SceneMarkerSortOption(rawValue: TabManager.shared.getSortOption(for: .markers) ?? "") ?? .createdAtDesc
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

    private func performSearch(isInitialLoad: Bool = true) {
        viewModel.fetchSceneMarkers(sortBy: selectedSortOption, searchQuery: searchText, filter: selectedFilter)
    }

    var body: some View {
        Group {
            if configManager.activeConfig == nil {
                ConnectionErrorView { performSearch() }
            } else if (viewModel.isLoadingMarkers && viewModel.sceneMarkers.isEmpty) || (viewModel.isLoadingSavedFilters && viewModel.savedFilters.isEmpty) {
                VStack {
                    Spacer()
                    ProgressView("Loading markers...")
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if viewModel.sceneMarkers.isEmpty && viewModel.errorMessage != nil {
                ConnectionErrorView { performSearch() }
            } else if viewModel.sceneMarkers.isEmpty {
                emptyStateView
            } else {
                markersList
            }
        }
        .navigationTitle(hideTitle ? "" : "Markers")
        .navigationBarTitleDisplayMode(.inline)
        .conditionalSearchable(isVisible: isSearchVisible, text: $searchText, prompt: "Search markers...")
        .onChange(of: searchText) { oldValue, newValue in
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
            
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
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
                                Text("Name")
                                if selectedSortOption == .titleAsc || selectedSortOption == .titleDesc { Image(systemName: "checkmark") }
                            }
                        }
                        
                        // Created
                        Menu {
                            Button(action: { changeSortOption(to: .createdAtDesc) }) {
                                HStack {
                                    Text("Newest First")
                                    if selectedSortOption == .createdAtDesc { Image(systemName: "checkmark") }
                                }
                            }
                            Button(action: { changeSortOption(to: .createdAtAsc) }) {
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
                        
                        // Updated
                        Menu {
                            Button(action: { changeSortOption(to: .updatedAtDesc) }) {
                                HStack {
                                    Text("Recently Updated")
                                    if selectedSortOption == .updatedAtDesc { Image(systemName: "checkmark") }
                                }
                            }
                            Button(action: { changeSortOption(to: .updatedAtAsc) }) {
                                HStack {
                                    Text("Oldest Updated")
                                    if selectedSortOption == .updatedAtAsc { Image(systemName: "checkmark") }
                                }
                            }
                        } label: {
                            HStack {
                                Text("Updated")
                                if selectedSortOption == .updatedAtAsc || selectedSortOption == .updatedAtDesc { Image(systemName: "checkmark") }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                            .foregroundColor(appearanceManager.tintColor)
                    }

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
                        
                        let markerFilters = viewModel.savedFilters.values
                            .filter { $0.mode == .sceneMarkers }
                            .sorted { $0.name < $1.name }
                        
                        ForEach(markerFilters) { filter in
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
                        Image(systemName: selectedFilter != nil ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .foregroundColor(selectedFilter != nil ? appearanceManager.tintColor : .primary)
                    }
                }
            }
        }
        .onAppear {
            if !coordinator.activeSearchText.isEmpty {
                searchText = coordinator.activeSearchText
                isSearchVisible = true
                coordinator.activeSearchText = ""
                performSearch()
                viewModel.fetchSavedFilters()
                return
            }
            
            if TabManager.shared.getDefaultFilterId(for: .markers) == nil || !viewModel.savedFilters.isEmpty {
                if viewModel.sceneMarkers.isEmpty {
                    performSearch()
                }
            }
            viewModel.fetchSavedFilters()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DefaultFilterChanged"))) { notification in
            if let tabId = notification.userInfo?["tab"] as? String, tabId == AppTab.markers.rawValue {
                if let defaultId = TabManager.shared.getDefaultFilterId(for: .markers),
                   let newFilter = viewModel.savedFilters[defaultId] {
                    selectedFilter = newFilter
                } else {
                    selectedFilter = nil
                }
                performSearch()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DefaultSortChanged"))) { notification in
            if let tabId = notification.userInfo?["tab"] as? String, tabId == AppTab.markers.rawValue {
                let newSort = StashDBViewModel.SceneMarkerSortOption(rawValue: TabManager.shared.getPersistentSortOption(for: .markers) ?? "") ?? .createdAtDesc
                selectedSortOption = newSort
                performSearch()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
            selectedFilter = nil
            performSearch()
        }
        .onChange(of: viewModel.savedFilters) { oldValue, newValue in
            if selectedFilter == nil {
                if let defaultId = TabManager.shared.getDefaultFilterId(for: .markers),
                   let filter = newValue[defaultId] {
                    selectedFilter = filter
                    performSearch()
                } else if !viewModel.isLoadingSavedFilters {
                    performSearch()
                }
            }
        }
        .onChange(of: viewModel.isLoadingSavedFilters) { oldValue, isLoading in
            if oldValue == true && isLoading == false {
                if viewModel.sceneMarkers.isEmpty && !viewModel.isLoadingMarkers && selectedFilter == nil {
                    performSearch()
                }
            }
        }
    }
    
    private func changeSortOption(to newOption: StashDBViewModel.SceneMarkerSortOption) {
        if newOption == .random && selectedSortOption == .random {
            viewModel.refreshRandomSeed()
        }
        selectedSortOption = newOption
        TabManager.shared.setSortOption(for: .markers, option: newOption.rawValue)
        performSearch()
    }

    private var emptyStateView: some View {
        SharedEmptyStateView(
            icon: "bookmark.fill",
            title: "No markers found",
            buttonText: "Load Markers",
            onRetry: { performSearch() }
        )
    }

    private var markersList: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(viewModel.sceneMarkers) { marker in
                    if let markerScene = marker.scene {
                        let mappedScene = markerScene.toScene().withResumeTime(marker.seconds)
                        NavigationLink(destination: SceneDetailView(scene: mappedScene, autoPlay: true)) {
                            MarkerCardView(marker: marker)
                        }
                        .buttonStyle(.plain)
                    } else {
                        MarkerCardView(marker: marker)
                    }
                }
                
                if viewModel.isLoadingMarkers {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                } else if viewModel.hasMoreMarkers && !viewModel.sceneMarkers.isEmpty {
                    Color.clear
                        .frame(height: 1)
                        .onAppear {
                            viewModel.loadMoreMarkers()
                        }
                }
            }
            .padding(16)
        }
        .refreshable { performSearch() }
    }
}

struct MarkerCardView: View {
    let marker: SceneMarker
    @ObservedObject var appearanceManager = AppearanceManager.shared

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Background Image
            ZStack {
                Color.studioHeaderGray
                
                if let thumbURL = marker.thumbnailURL {
                    CustomAsyncImage(url: thumbURL) { loader in
                        if loader.isLoading {
                            ProgressView()
                        } else if let image = loader.image {
                            image
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: "bookmark.fill")
                                .font(.largeTitle)
                                .foregroundColor(appearanceManager.tintColor)
                        }
                    }
                } else {
                    Image(systemName: "bookmark.fill")
                        .font(.largeTitle)
                        .foregroundColor(appearanceManager.tintColor)
                }
            }
            .aspectRatio(16/9, contentMode: .fill)
            .clipped()
            
            // Bottom Gradient for contrast
            LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .bottom, endPoint: .top)
                .frame(height: 60)
            
            // Overlay Info
            VStack {
                HStack(alignment: .top) {
                    // Marker Name (Top Left)
                    Text(marker.title ?? "Marker")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.black.opacity(DesignTokens.Opacity.badge))
                        .clipShape(Capsule())
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // Play count pill (Top Right)
                    if let playCount = marker.playCount, playCount > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 8))
                            Text("\(playCount)")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.black.opacity(DesignTokens.Opacity.badge))
                        .clipShape(Capsule())
                    }
                }
                
                Spacer()
                
                // Scene Name (Bottom Left)
                Text(marker.scene?.title ?? "Unknown Scene")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .bottomLeading)
                    .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
            }
            .padding(8)
        }
        .aspectRatio(16/9, contentMode: .fit)
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .cardShadow()
    }
}
#endif
