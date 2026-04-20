//
//  StudiosView.swift
//  stashy
//
//  Created by Daniel Goletz on 29.09.25.
//

#if !os(tvOS)
import SwiftUI
import WebKit

struct StudiosView: View {
    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject var configManager = ServerConfigManager.shared
    @ObservedObject private var appearance = AppearanceManager.shared
    @State private var selectedSortOption: StashDBViewModel.StudioSortOption
    @State private var isChangingSort = false
    @State private var searchText = ""
    @State private var isSearchVisible = false
    @State private var selectedFilter: StashDBViewModel.SavedFilter? = nil
    @State private var lastOpenedStudioId: String?
    var hideTitle: Bool = false
    @EnvironmentObject var coordinator: NavigationCoordinator
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // Live filter
    @State private var showLiveFilterSheet = false
    @State private var liveFilterFavorite: Bool? = nil
    @State private var liveFilterMinRating: Int = 0
    @State private var liveFilterScenes: String? = nil // nil=any, "has"=has scenes, "none"=no scenes

    private var isLiveFilterActive: Bool {
        liveFilterFavorite != nil || liveFilterMinRating > 0 || liveFilterScenes != nil
    }

    private var activeLiveFilterDict: [String: Any] {
        var dict: [String: Any] = [:]
        if let fav = liveFilterFavorite { 
            // For Studios, the filter key appears to be "favorite"
            dict["favorite"] = fav 
        }
        if liveFilterMinRating > 0 {
            // Exact star match (e.g. 1-star means exactly 20)
            dict["rating100"] = ["value": (liveFilterMinRating * 20), "modifier": "EQUALS"]
        }
        if liveFilterScenes == "has"  { dict["scene_count"] = ["value": 0, "modifier": "GREATER_THAN"] }
        if liveFilterScenes == "none" { dict["scene_count"] = ["value": 0, "modifier": "EQUALS"] }
        return dict
    }

    private func applyLiveFilter() {
        viewModel.currentStudioLiveFilter = activeLiveFilterDict
        viewModel.fetchStudios(sortBy: selectedSortOption, searchQuery: searchText, filter: selectedFilter, liveFilter: activeLiveFilterDict)
    }

    init(initialSort: StashDBViewModel.StudioSortOption? = nil, hideTitle: Bool = false) {
        let savedSort = StashDBViewModel.StudioSortOption(rawValue: TabManager.shared.getSortOption(for: .studios) ?? "")
        _selectedSortOption = State(initialValue: initialSort ?? savedSort ?? .nameAsc)
        self.hideTitle = hideTitle
    }

    // Safe sort change function
    private func changeSortOption(to newOption: StashDBViewModel.StudioSortOption) {
        if newOption == .random && selectedSortOption == .random {
            viewModel.refreshRandomSeed()
        }
        selectedSortOption = newOption
        
        // Save to TabManager
        TabManager.shared.setSortOption(for: .studios, option: newOption.rawValue)

        // Fetch new data immediately
        viewModel.fetchStudios(sortBy: newOption, searchQuery: searchText, filter: selectedFilter, liveFilter: isLiveFilterActive ? activeLiveFilterDict : nil)
    }
    
    // Search function with debouncing
    private func performSearch() {
        viewModel.fetchStudios(sortBy: selectedSortOption, searchQuery: searchText, filter: selectedFilter, liveFilter: isLiveFilterActive ? activeLiveFilterDict : nil)
    }

    var body: some View {
        Group {
            if configManager.activeConfig == nil {
                ConnectionErrorView { performSearch() }
            } else if viewModel.isLoading && viewModel.studios.isEmpty {
                VStack {
                    Spacer()
                    ProgressView("Loading studios...")
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if viewModel.studios.isEmpty && viewModel.errorMessage != nil {
                ConnectionErrorView { performSearch() }
            } else if viewModel.studios.isEmpty {
                emptyStateView
            } else {
                studiosList
            }
        }
        .navigationTitle(hideTitle ? "" : "Studios")
        .navigationBarTitleDisplayMode(.inline)
        .applyAppBackground()
        .conditionalSearchable(isVisible: isSearchVisible, text: $searchText, prompt: "Search studios...")
        .toolbar {
            toolbarContent
        }
        .floatingActionBar {
            HStack(spacing: 0) {
                // Sort Menu with grouped options
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
                    
                    // Scene Count
                    Menu {
                        Button(action: { changeSortOption(to: .sceneCountDesc) }) {
                            HStack {
                                Text("High → Low")
                                if selectedSortOption == .sceneCountDesc { Image(systemName: "checkmark") }
                            }
                        }
                        Button(action: { changeSortOption(to: .sceneCountAsc) }) {
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
                        Button(action: { changeSortOption(to: .updatedAtDesc) }) {
                            HStack {
                                Text("Newest First")
                                if selectedSortOption == .updatedAtDesc { Image(systemName: "checkmark") }
                            }
                        }
                        Button(action: { changeSortOption(to: .updatedAtAsc) }) {
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
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)
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
                    
                    let studioFilters = viewModel.savedFilters.values
                        .filter { $0.mode == .studios }
                        .sorted { $0.name < $1.name }
                    
                    ForEach(studioFilters) { filter in
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
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(selectedFilter != nil ? appearance.tintColor : .primary)
                }
                .frame(maxWidth: .infinity)

                // Live Filter button
                Button(action: { showLiveFilterSheet = true }) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 20))
                        .foregroundColor(isLiveFilterActive ? appearance.tintColor : .primary)
                        .overlay(alignment: .topTrailing) {
                            if isLiveFilterActive {
                                Circle()
                                    .fill(appearance.tintColor)
                                    .frame(width: 7, height: 7)
                                    .offset(x: 3, y: -3)
                            }
                        }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .sheet(isPresented: $showLiveFilterSheet) {
            StudioLiveFilterSheet(
                minRating: $liveFilterMinRating,
                favorite: $liveFilterFavorite,
                scenes: $liveFilterScenes,
                onApply: { applyLiveFilter() },
                onReset: {
                    liveFilterMinRating = 0
                    liveFilterFavorite = nil
                    liveFilterScenes = nil
                    applyLiveFilter()
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color.appBackground)
        }
        .onAppear {
            onAppearAction()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DefaultFilterChanged"))) { notification in
            if let tabId = notification.userInfo?["tab"] as? String, tabId == AppTab.studios.rawValue {
                if let defaultId = TabManager.shared.getDefaultFilterId(for: .studios),
                   let newFilter = viewModel.savedFilters[defaultId] {
                    selectedFilter = newFilter
                } else {
                    selectedFilter = nil
                }
                performSearch()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DefaultSortChanged"))) { notification in
            if let tabId = notification.userInfo?["tab"] as? String, tabId == AppTab.studios.rawValue {
                let newSort = StashDBViewModel.StudioSortOption(rawValue: TabManager.shared.getPersistentSortOption(for: .studios) ?? "") ?? .nameAsc
                changeSortOption(to: newSort)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
            selectedFilter = nil
            performSearch()
        }
        .onChange(of: searchText) { oldValue, newValue in
            onSearchTextChange(newValue)
        }
        .onChange(of: viewModel.savedFilters) { oldValue, newValue in
            onSavedFiltersChange(newValue)
        }
        .onChange(of: viewModel.isLoadingSavedFilters) { oldValue, isLoading in
            if oldValue == true && isLoading == false {
                if viewModel.studios.isEmpty && !viewModel.isLoadingStudios && selectedFilter == nil {
                    viewModel.fetchStudios(sortBy: selectedSortOption, searchQuery: searchText, filter: nil)
                }
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { coordinator.studioToOpen != nil },
            set: { if !$0 { coordinator.studioToOpen = nil } }
        )) {
            if let studio = coordinator.studioToOpen {
                StudioDetailView(studio: studio)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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

    private func onSearchTextChange(_ newValue: String) {
        NSObject.cancelPreviousPerformRequests(withTarget: self)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if newValue == self.searchText {
                self.performSearch()
            }
        }
    }

    private func onAppearAction() {
        // Check for search text from navigation
        if !coordinator.activeSearchText.isEmpty {
            searchText = coordinator.activeSearchText
            isSearchVisible = true
            coordinator.activeSearchText = ""
            viewModel.fetchStudios(sortBy: selectedSortOption, searchQuery: searchText, filter: selectedFilter)
            viewModel.fetchSavedFilters()
            return
        }
        
        if TabManager.shared.getDefaultFilterId(for: .studios) == nil || !viewModel.savedFilters.isEmpty {
            if viewModel.studios.isEmpty {
                performSearch()
            }
        }
        viewModel.fetchSavedFilters()
    }

    private func onSavedFiltersChange(_ newValue: [String: StashDBViewModel.SavedFilter]) {
        if selectedFilter == nil {
            if let defaultId = TabManager.shared.getDefaultFilterId(for: .studios),
               let filter = newValue[defaultId] {
                selectedFilter = filter
                // Only fetch if empty to avoid resetting scroll
                if viewModel.studios.isEmpty {
                    viewModel.fetchStudios(sortBy: selectedSortOption, searchQuery: searchText, filter: filter)
                }
            } else if !viewModel.isLoadingSavedFilters {
                // Default filter was set but not found, or filters finished loading and none match
                // Only fetch if empty
                if viewModel.studios.isEmpty {
                    viewModel.fetchStudios(sortBy: selectedSortOption, searchQuery: searchText, filter: nil)
                }
            }
        }
    }

    private var emptyStateView: some View {
        SharedEmptyStateView(
            icon: "building.2",
            title: "No studios found",
            buttonText: "Load Studios",
            onRetry: { performSearch() }
        )
    }

    @Environment(\.verticalSizeClass) var verticalSizeClass

    private var columns: [GridItem] {
        if horizontalSizeClass == .regular {
            return Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
        } else if verticalSizeClass == .compact {
             return [
                 GridItem(.flexible(), spacing: 12),
                 GridItem(.flexible(), spacing: 12)
             ]
        } else {
            return [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ]
        }
    }

    private var studiosList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(viewModel.studios) { studio in
                        NavigationLink(destination: StudioDetailView(studio: studio)) {
                            StudioCardView(studio: studio)
                        }
                        .buttonStyle(.plain)
                        .id(studio.id)
                        .simultaneousGesture(TapGesture().onEnded {
                            lastOpenedStudioId = studio.id
                        })
                    }
                }
                .padding(16)
                .padding(.bottom, 70)
            }
            .refreshable { performSearch() }
            .onAppear {
                if let id = lastOpenedStudioId {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        proxy.scrollTo(id, anchor: .top)
                    }
                }
            }
        }
    }
    
}

// Studio image view with fallback URL support for SVG handling
// Studio image view with hybrid support (PNG/JPG + SVG)
struct StudioImageView: View {
    let studio: Studio
    @State private var imageLoadState: ImageLoadState = .loading

    enum ImageLoadState {
        case loading
        case success(Image)
        case successSVG(Data, String)
        case failure
    }

    private var imageURL: URL? {
        guard let config = ServerConfigManager.shared.loadConfig() else { return nil }
        return URL(string: "\(config.baseURL)/studio/\(studio.id)/image")
    }

    var body: some View {
        Group {
            switch imageLoadState {
            case .loading:
                Rectangle()
                    .fill(Color.gray.opacity(DesignTokens.Opacity.placeholder))
                    .overlay(ProgressView())

            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            case .successSVG(let svgData, let svgString):
                 ZStack {
                    SVGWebView(svgData: svgData, svgString: svgString)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Transparent overlay to catch touches if needed, or let them pass usually
                    Color.clear.contentShape(Rectangle())
                 }

            case .failure:
                placeholderView
            }
        }
        .task {
            await loadImage()
        }
    }
    
    private var placeholderView: some View {
        Rectangle()
            .fill(Color.gray.opacity(DesignTokens.Opacity.placeholder))
            .overlay(
                VStack(spacing: 4) {
                    Image(systemName: "building.2")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text(studio.name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                }
            )
    }

    private func loadImage() async {
        guard let url = imageURL else {
            imageLoadState = .failure
            return
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 30.0
            
            if let config = ServerConfigManager.shared.loadConfig(),
               let apiKey = config.secureApiKey, !apiKey.isEmpty {
                request.setValue(apiKey, forHTTPHeaderField: "ApiKey")
            }
            
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("❌ Studio Image HTTP Error: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                imageLoadState = .failure
                return
            }

            // 1. Try generic Image (PNG, JPG)
            if let uiImage = UIImage(data: data) {
                imageLoadState = .success(Image(uiImage: uiImage))
                return
            }

            // 2. Try SVG
            // Check header or content
            let contentType = httpResponse.allHeaderFields["Content-Type"] as? String
            let isSVGHeader = contentType?.contains("svg") == true
            
            // Also peek at data
            let dataString = String(data: data, encoding: .utf8) ?? ""
            let isSVGContent = dataString.contains("<svg")
            
            if isSVGHeader || isSVGContent {
                if !dataString.isEmpty {
                    imageLoadState = .successSVG(data, dataString)
                    return
                }
            }

            // Fail
            print("❌ Failed to decode studio image for \(studio.name)")
            imageLoadState = .failure
            
        } catch {
            print("❌ Error loading studio image: \(error.localizedDescription)")
            imageLoadState = .failure
        }
    }
}

// Row-based view for list layout
struct StudioRowView: View {
    let studio: Studio

    var body: some View {
        HStack(spacing: 16) {
            // Logo on the left (square with gray background)
            ZStack {
                Color(red: 44/255.0, green: 44/255.0, blue: 46/255.0)
                
                StudioImageView(studio: studio)
                    .frame(width: 50, height: 50)
                    .clipped()
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Studio info
            VStack(alignment: .leading, spacing: 4) {
                Text(studio.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                HStack(spacing: 4) {
                    Image(systemName: "film")
                        .font(.caption2)
                    Text("\(studio.sceneCount) Scenes")
                        .font(.caption)
                }
                .foregroundColor(.appAccent)
            }
            
            Spacer()
            
            // Chevron removed as requested
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.secondaryAppBackground)
        .contentShape(Rectangle())
    }
}

struct StudioCardView: View {
    let studio: Studio

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Logo Block (Top)
            Color.studioHeaderGray
                .aspectRatio(2.2, contentMode: .fit)
                .overlay(
                    StudioImageView(studio: studio)
                )
                .clipped()
            
            // Name & Info Area (Below)
            HStack(spacing: 8) {
                Text(studio.name)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Spacer()
                
                HStack(spacing: 8) {
                    // Scenes
                    HStack(spacing: 3) {
                        Image(systemName: "film")
                            .font(.system(size: 10))
                        Text("\(studio.sceneCount)")
                            .font(.system(size: 11, weight: .medium))
                    }
                    
                    // Galleries
                    if let galleryCount = studio.galleryCount, galleryCount > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "photo.stack")
                                .font(.system(size: 10))
                            Text("\(galleryCount)")
                                .font(.system(size: 11, weight: .medium))
                        }
                    }
                }
                .foregroundColor(.secondary)
                .layoutPriority(1) // Ensure counts get space first
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(Color.secondaryAppBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card))
        .cardShadow()
    }
}

// SVG WebView for displaying SVG images
struct SVGWebView: UIViewRepresentable {
    let svgData: Data
    let svgString: String?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController = WKUserContentController()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bouncesZoom = false
        webView.scrollView.minimumZoomScale = 1.0
        webView.scrollView.maximumZoomScale = 1.0
        webView.isUserInteractionEnabled = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if let svgString = svgString {
            let html = """
            <!DOCTYPE html>
            <html>
            <head>
                <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
                <style>
                    * { box-sizing: border-box; margin: 0; padding: 0; }
                    html, body {
                        width: 100vw;
                        height: 100vh;
                        background: transparent;
                        overflow: hidden;
                        display: flex;
                        justify-content: center;
                        align-items: center;
                    }
                    svg {
                        width: 100vw !important;
                        height: 100vh !important;
                        max-width: 100vw !important;
                        max-height: 100vh !important;
                        display: block;
                        object-fit: contain;
                    }
                </style>
            </head>
            <body>
                \(svgString)
                <script>
                    var svg = document.querySelector('svg');
                    if (svg) {
                        if (!svg.getAttribute('viewBox')) {
                            var w = svg.getAttribute('width') || '100';
                            var h = svg.getAttribute('height') || '100';
                            svg.setAttribute('viewBox', '0 0 ' + parseFloat(w) + ' ' + parseFloat(h));
                        }
                        svg.setAttribute('preserveAspectRatio', 'xMidYMid meet');
                        svg.removeAttribute('width');
                        svg.removeAttribute('height');
                    }
                </script>
            </body>
            </html>
            """
            webView.loadHTMLString(html, baseURL: nil)
        }
    }
}

#Preview {
    StudiosView()
}

// MARK: - Studio Live Filter Sheet

struct StudioLiveFilterSheet: View {
    @Binding var minRating: Int
    @Binding var favorite: Bool?
    @Binding var scenes: String?
    var onApply: () -> Void
    var onReset: () -> Void

    @ObservedObject private var appearance = AppearanceManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 0) {
                    filterRow(label: "Favorite") {
                        filterChip("Any", isActive: favorite == nil)   { favorite = nil;   onApply() }
                        filterChip("Yes", isActive: favorite == true)  { favorite = true;  onApply() }
                        filterChip("No",  isActive: favorite == false) { favorite = false; onApply() }
                    }
                    Divider().padding(.leading, 16)
                    filterRow(label: "Rating") {
                        filterChip("Any", isActive: minRating == 0) { minRating = 0; onApply() }
                        ForEach(1...5, id: \.self) { star in
                            filterChip("\(star)★", isActive: minRating == star) { minRating = star; onApply() }
                        }
                    }
                    Divider().padding(.leading, 16)
                    filterRow(label: "Scenes") {
                        filterChip("Any",        isActive: scenes == nil)     { scenes = nil;    onApply() }
                        filterChip("Has scenes", isActive: scenes == "has")   { scenes = "has";  onApply() }
                        filterChip("None",       isActive: scenes == "none")  { scenes = "none"; onApply() }
                    }
                }
                .background(Color.secondaryAppBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .padding(.top, 16)
                Spacer()
            }
            .background(Color.appBackground)
            .navigationTitle("Live Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Reset", role: .destructive) { onReset() }.foregroundColor(.red)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }

    @ViewBuilder
    private func filterRow<C: View>(label: String, @ViewBuilder chips: () -> C) -> some View {
        HStack(spacing: 12) {
            Text(label).font(.system(size: 15)).frame(width: 80, alignment: .leading).foregroundColor(.primary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { chips() }.padding(.vertical, 12)
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func filterChip(_ label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(isActive ? appearance.tintColor : Color.secondary.opacity(0.15))
                .foregroundColor(isActive ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
#endif
