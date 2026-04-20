//
//  PerformersView.swift
//  stashy
//
//  Created by Daniel Goletz on 29.09.25.
//

#if !os(tvOS)
import SwiftUI


struct PerformersView: View {
    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject var configManager = ServerConfigManager.shared
    @ObservedObject private var appearance = AppearanceManager.shared
    @State private var scrollPosition: String? = nil
    @State private var shouldRestoreScroll = false
    @State private var selectedSortOption: StashDBViewModel.PerformerSortOption
    @State private var isChangingSort = false
    @State private var searchText = ""
    @State private var selectedFilter: StashDBViewModel.SavedFilter? = nil
    @State private var navigationPath = [Performer]()
    @State private var isSearchVisible = false
    @EnvironmentObject var coordinator: NavigationCoordinator
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // Live filter state
    @State private var showLiveFilterSheet = false
    @State private var liveFilterAgeRange: String? = nil   // "18-21" / "22-26" / "26-30" / "30+"
    @State private var liveFilterHairColor: String? = nil  // "BLONDE" / "BRUNETTE" / "RED" / "BLACK"
    @State private var liveFilterGender: String? = nil     // "FEMALE" / "MALE" / "TRANSGENDER_FEMALE" / "TRANSGENDER_MALE" / "NON_BINARY"
    @State private var liveFilterCountry: String? = nil    // "US" / "NOT_US"
    @State private var liveFilterImplants: Bool? = nil     // nil=any, true=has, false=none
    @State private var liveFilterFavorite: Bool? = nil     // nil=any, true=yes, false=no
    @State private var liveFilterMissingField: String? = nil // nil=any, "image" / "gender" / "hair_color"

    private var isLiveFilterActive: Bool {
        liveFilterAgeRange != nil || liveFilterHairColor != nil || liveFilterGender != nil
        || liveFilterCountry != nil || liveFilterImplants != nil || liveFilterFavorite != nil
        || liveFilterMissingField != nil
    }

    private var activeLiveFilterDict: [String: Any] {
        var dict: [String: Any] = [:]
        if let age = liveFilterAgeRange {
            let cal = Calendar.current
            let now = Date()
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            switch age {
            case "18-21":
                let lo = fmt.string(from: cal.date(byAdding: .year, value: -21, to: now)!)
                let hi = fmt.string(from: cal.date(byAdding: .year, value: -18, to: now)!)
                dict["birthdate"] = ["value": lo, "value2": hi, "modifier": "BETWEEN"]
            case "22-26":
                let lo = fmt.string(from: cal.date(byAdding: .year, value: -26, to: now)!)
                let hi = fmt.string(from: cal.date(byAdding: .year, value: -22, to: now)!)
                dict["birthdate"] = ["value": lo, "value2": hi, "modifier": "BETWEEN"]
            case "26-30":
                let lo = fmt.string(from: cal.date(byAdding: .year, value: -30, to: now)!)
                let hi = fmt.string(from: cal.date(byAdding: .year, value: -26, to: now)!)
                dict["birthdate"] = ["value": lo, "value2": hi, "modifier": "BETWEEN"]
            case "30+":
                let lo = fmt.string(from: cal.date(byAdding: .year, value: -30, to: now)!)
                dict["birthdate"] = ["value": lo, "modifier": "LESS_THAN"]
            default: break
            }
        }
        if let hair = liveFilterHairColor {
            dict["hair_color"] = ["value": hair, "modifier": "EQUALS"]
        }
        if let gender = liveFilterGender {
            dict["gender"] = ["value": gender, "modifier": "EQUALS"]
        }
        if let country = liveFilterCountry {
            if country == "NOT_US" {
                dict["country"] = ["value": "US", "modifier": "NOT_EQUALS"]
            } else {
                dict["country"] = ["value": country, "modifier": "EQUALS"]
            }
        }
        if let implants = liveFilterImplants {
            dict["fake_tits"] = ["value": implants ? "FAKE" : "NATURAL", "modifier": "EQUALS"]
        }
        if let favorite = liveFilterFavorite {
            dict["filter_favorites"] = favorite
        }
        // Missing-field filter uses Stash's `is_missing: "<field>"` convention.
        // If explicitly set, it wins over `has_image` to avoid contradictory filters.
        if let missingField = liveFilterMissingField, !missingField.isEmpty {
            dict.removeValue(forKey: "has_image")
            dict["is_missing"] = missingField
        }
        return dict
    }

    private func applyLiveFilter() {
        viewModel.currentPerformerLiveFilter = activeLiveFilterDict
        viewModel.fetchPerformers(sortBy: selectedSortOption, searchQuery: searchText, filter: selectedFilter, liveFilter: activeLiveFilterDict)
    }

    init(initialSort: StashDBViewModel.PerformerSortOption? = nil) {
        let savedSort = StashDBViewModel.PerformerSortOption(rawValue: TabManager.shared.getSortOption(for: .performers) ?? "")
        _selectedSortOption = State(initialValue: initialSort ?? savedSort ?? .sceneCountDesc)
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

    // Safe sort change function
    private func changeSortOption(to newOption: StashDBViewModel.PerformerSortOption) {
        if newOption == .random && selectedSortOption == .random {
            viewModel.refreshRandomSeed()
        }
        selectedSortOption = newOption
        scrollPosition = nil
        shouldRestoreScroll = false
        
        // Save to TabManager
        TabManager.shared.setSortOption(for: .performers, option: newOption.rawValue)

        // Fetch new data immediately
        viewModel.fetchPerformers(sortBy: newOption, searchQuery: searchText, filter: selectedFilter, liveFilter: isLiveFilterActive ? activeLiveFilterDict : nil)
    }
    
    // Search function with debouncing
    private func performSearch() {
        scrollPosition = nil
        shouldRestoreScroll = false
        viewModel.fetchPerformers(sortBy: selectedSortOption, searchQuery: searchText, filter: selectedFilter, liveFilter: isLiveFilterActive ? activeLiveFilterDict : nil)
    }

    var body: some View {
        Group {
            if configManager.activeConfig == nil {
                ConnectionErrorView { performSearch() }
            } else if viewModel.isLoading && viewModel.performers.isEmpty {
                VStack {
                    Spacer()
                    ProgressView("Loading performers...")
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if viewModel.performers.isEmpty && viewModel.errorMessage != nil {
                ConnectionErrorView { performSearch() }
            } else if viewModel.performers.isEmpty {
                emptyStateView
            } else {
                performersGrid
            }
        }
        .navigationTitle("Performers")
        .navigationBarTitleDisplayMode(.inline)
        .applyAppBackground()

        .onChange(of: searchText) { oldValue, newValue in
            // Debounce: Nur suchen wenn Nutzer aufhört zu tippen (0.5s Delay)
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
                        // Random (standalone)
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
                                if selectedSortOption == .nameAsc || selectedSortOption == .nameDesc {
                                    Image(systemName: "checkmark")
                                }
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
                                if selectedSortOption == .sceneCountAsc || selectedSortOption == .sceneCountDesc {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }

                        // Counter
                        Menu {
                            Button(action: { changeSortOption(to: .oCountDesc) }) {
                                HStack {
                                    Text("High → Low")
                                    if selectedSortOption == .oCountDesc { Image(systemName: "checkmark") }
                                }
                            }
                            Button(action: { changeSortOption(to: .oCountAsc) }) {
                                HStack {
                                    Text("Low → High")
                                    if selectedSortOption == .oCountAsc { Image(systemName: "checkmark") }
                                }
                            }
                        } label: {
                            HStack {
                                Text("Counter")
                                if selectedSortOption == .oCountAsc || selectedSortOption == .oCountDesc {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        
                        // Birthday
                        Menu {
                            Button(action: { changeSortOption(to: .birthdateDesc) }) {
                                HStack {
                                    Text("Youngest First")
                                    if selectedSortOption == .birthdateDesc { Image(systemName: "checkmark") }
                                }
                            }
                            Button(action: { changeSortOption(to: .birthdateAsc) }) {
                                HStack {
                                    Text("Oldest First")
                                    if selectedSortOption == .birthdateAsc { Image(systemName: "checkmark") }
                                }
                            }
                        } label: {
                            HStack {
                                Text("Birthday")
                                if selectedSortOption == .birthdateAsc || selectedSortOption == .birthdateDesc {
                                    Image(systemName: "checkmark")
                                }
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
                                if selectedSortOption == .updatedAtAsc || selectedSortOption == .updatedAtDesc {
                                    Image(systemName: "checkmark")
                                }
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
                                if selectedSortOption == .createdAtAsc || selectedSortOption == .createdAtDesc {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
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
                        
                        let performerFilters = viewModel.savedFilters.values
                            .filter { $0.mode == .performers }
                            .sorted { $0.name < $1.name }
                        
                        ForEach(performerFilters) { filter in
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
            PerformerLiveFilterSheet(
                ageRange: $liveFilterAgeRange,
                hairColor: $liveFilterHairColor,
                gender: $liveFilterGender,
                country: $liveFilterCountry,
                implants: $liveFilterImplants,
                favorite: $liveFilterFavorite,
                missingField: $liveFilterMissingField,
                onApply: { applyLiveFilter() },
                onReset: {
                    liveFilterAgeRange = nil
                    liveFilterHairColor = nil
                    liveFilterGender = nil
                    liveFilterCountry = nil
                    liveFilterImplants = nil
                    liveFilterFavorite = nil
                    liveFilterMissingField = nil
                    applyLiveFilter()
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color.appBackground)
        }
        .onAppear {
            // Check for search text from navigation
            if !coordinator.activeSearchText.isEmpty {
                searchText = coordinator.activeSearchText
                isSearchVisible = true
                coordinator.activeSearchText = ""
                viewModel.fetchPerformers(sortBy: selectedSortOption, searchQuery: searchText, filter: selectedFilter)
                viewModel.fetchSavedFilters()
                return
            }
            
            // Only search if we don't have a default filter to wait for, or if filters are already loaded
            if TabManager.shared.getDefaultFilterId(for: .performers) == nil || !viewModel.savedFilters.isEmpty {
                if viewModel.performers.isEmpty {
                    performSearch()
                }
            }
            viewModel.fetchSavedFilters()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
            selectedFilter = nil
            performSearch()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DefaultFilterChanged"))) { notification in
            if let tabId = notification.userInfo?["tab"] as? String, tabId == AppTab.performers.rawValue {
                if let defaultId = TabManager.shared.getDefaultFilterId(for: .performers),
                   let newFilter = viewModel.savedFilters[defaultId] {
                    selectedFilter = newFilter
                } else {
                    selectedFilter = nil
                }
                performSearch()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DefaultSortChanged"))) { notification in
            if let tabId = notification.userInfo?["tab"] as? String, tabId == AppTab.performers.rawValue {
                let newSort = StashDBViewModel.PerformerSortOption(rawValue: TabManager.shared.getPersistentSortOption(for: .performers) ?? "") ?? .sceneCountDesc
                changeSortOption(to: newSort)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PerformerImageUpdated"))) { notification in
            if let targetId = notification.userInfo?["performerId"] as? String,
               let newPath = notification.userInfo?["newImagePath"] as? String {
                if let index = viewModel.performers.firstIndex(where: { $0.id == targetId }) {
                    viewModel.performers[index].imagePath = newPath
                }
            }
        }
        .onChange(of: viewModel.savedFilters) { oldValue, newValue in
            // Apply default filter if set and none selected yet
            if selectedFilter == nil {
                if let defaultId = TabManager.shared.getDefaultFilterId(for: .performers),
                   let filter = newValue[defaultId] {
                    selectedFilter = filter
                    // Only fetch if empty to avoid resetting scroll
                    if viewModel.performers.isEmpty {
                        viewModel.fetchPerformers(sortBy: selectedSortOption, searchQuery: searchText, filter: filter)
                    }
                } else if !viewModel.isLoadingSavedFilters {
                    // Default filter was set but not found, or filters finished loading and none match
                    // Only fetch if empty
                    if viewModel.performers.isEmpty {
                        viewModel.fetchPerformers(sortBy: selectedSortOption, searchQuery: searchText, filter: nil)
                    }
                }
            }
        }
        .onChange(of: viewModel.isLoadingSavedFilters) { oldValue, isLoading in
            if oldValue == true && isLoading == false {
                if viewModel.performers.isEmpty && !viewModel.isLoadingPerformers && selectedFilter == nil {
                    viewModel.fetchPerformers(sortBy: selectedSortOption, searchQuery: searchText, filter: nil)
                }
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { coordinator.performerToOpen != nil },
            set: { if !$0 { coordinator.performerToOpen = nil } }
        )) {
            if let performer = coordinator.performerToOpen {
                PerformerDetailView(performer: performer)
            }
        }
    }

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView("Loading performers...")
            Spacer()
        }
    }

    private var emptyStateView: some View {
         SharedEmptyStateView(
             icon: "person.3",
             title: "No performers found",
             buttonText: "Load Performers",
             onRetry: { performSearch() }
         )
    }

    private var performersGrid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(viewModel.performers) { performer in
                        NavigationLink(destination: PerformerDetailView(performer: performer)) {
                            PerformerCardView(performer: performer, badgeType: (selectedSortOption == .oCountDesc || selectedSortOption == .oCountAsc) ? .oCount : .sceneCount)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .id(performer.id)
                    }

                    // Loading indicator for pagination
                    if viewModel.isLoadingMorePerformers {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else if viewModel.hasMorePerformers && !viewModel.performers.isEmpty {
                        // Invisible element to trigger loading more performers
                        Color.clear
                            .frame(height: 1)
                            .onAppear {
                                // Save scroll position before loading - use element around 3/4 of current list
                                let currentCount = viewModel.performers.count
                                if currentCount > 4 {
                                    let targetIndex = currentCount * 3 / 4
                                    if targetIndex < currentCount {
                                        scrollPosition = viewModel.performers[targetIndex].id
                                        shouldRestoreScroll = true
                                    }
                                } else if let lastPerformer = viewModel.performers.last {
                                    scrollPosition = lastPerformer.id
                                    shouldRestoreScroll = true
                                }
                                viewModel.loadMorePerformers()
                            }
                            .id("pagination-trigger")
                    }
                }
                .padding(16)
            }
            .refreshable { performSearch() }
            .onChange(of: viewModel.isLoadingMorePerformers) { oldValue, isLoading in
                if !isLoading && shouldRestoreScroll {
                    // Loading completed, restore scroll position
                    if let scrollPosition = scrollPosition {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo(scrollPosition, anchor: .top)
                            }
                            shouldRestoreScroll = false
                        }
                    }
                }
            }
        }
    }
}


struct PerformerCardView: View {
    let performer: Performer
    var badgeType: PerformerBadgeType = .sceneCount
    @ObservedObject var appearanceManager = AppearanceManager.shared

    var body: some View {

        ZStack(alignment: .bottomLeading) {
            // Image
            GeometryReader { geometry in
                ZStack {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))

                    if let thumbnailURL = performer.thumbnailURL {
                        CustomAsyncImage(url: thumbnailURL) { loader in
                            if loader.isLoading {
                                ProgressView()
                            } else if let image = loader.image {
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                                    .clipped()
                            } else {
                                Image(systemName: "person.fill")
                                    .font(.largeTitle)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Image(systemName: "person.fill")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
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
            .frame(height: 120)
            
            // Top Badge (Single value Top Right)
            VStack {
                HStack {
                    Spacer()
                    
                    // Single Badge (Top Right)
                    HStack(spacing: 3) {
                        Image(systemName: badgeType == .oCount ? appearanceManager.oCounterIcon : "film")
                            .font(.system(size: 10, weight: .bold))
                        Text("\(badgeType == .oCount ? (performer.oCounter ?? 0) : performer.sceneCount)")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(DesignTokens.Opacity.badge))
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.2), radius: 2)
                }
                .padding(8)
                Spacer()
            }
            
            // Info Section (Bottom Name)
            VStack(alignment: .leading, spacing: 4) {
                 HStack(alignment: .bottom, spacing: 6) {
                    Text(performer.name)
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
}

// Keep old row view for compatibility
struct PerformerRowView: View {
    let performer: Performer

    var body: some View {
        PerformerCardView(performer: performer)
    }
}

#Preview {
    PerformersView()
}

// MARK: - Performer Live Filter Sheet

struct PerformerLiveFilterSheet: View {
    @Binding var ageRange: String?
    @Binding var hairColor: String?
    @Binding var gender: String?
    @Binding var country: String?
    @Binding var implants: Bool?
    @Binding var favorite: Bool?
    @Binding var missingField: String?
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
                    filterRow(label: "Missing") {
                        filterChip("Any",    isActive: missingField == nil)            { missingField = nil;          onApply() }
                        filterChip("Image",  isActive: missingField == "image")        { missingField = "image";      onApply() }
                        filterChip("Gender", isActive: missingField == "gender")       { missingField = "gender";     onApply() }
                        filterChip("Hair",   isActive: missingField == "hair_color")   { missingField = "hair_color"; onApply() }
                    }
                    Divider().padding(.leading, 16)
                    filterRow(label: "Gender") {
                        filterChip("Any",    isActive: gender == nil)      { gender = nil;      onApply() }
                        filterChip("Female", isActive: gender == "FEMALE") { gender = "FEMALE"; onApply() }
                        filterChip("Male",   isActive: gender == "MALE")   { gender = "MALE";   onApply() }
                        filterChip("Trans (M)", isActive: gender == "TRANSGENDER_MALE") { gender = "TRANSGENDER_MALE"; onApply() }
                        filterChip("Trans (F)", isActive: gender == "TRANSGENDER_FEMALE") { gender = "TRANSGENDER_FEMALE"; onApply() }
                        filterChip("Intersex", isActive: gender == "INTERSEX") { gender = "INTERSEX"; onApply() }
                        filterChip("Non-binary", isActive: gender == "NON_BINARY") { gender = "NON_BINARY"; onApply() }
                    }
                    Divider().padding(.leading, 16)
                    filterRow(label: "Age") {
                        filterChip("Any",   isActive: ageRange == nil)    { ageRange = nil;    onApply() }
                        filterChip("18–21", isActive: ageRange == "18-21") { ageRange = "18-21"; onApply() }
                        filterChip("22–26", isActive: ageRange == "22-26") { ageRange = "22-26"; onApply() }
                        filterChip("26–30", isActive: ageRange == "26-30") { ageRange = "26-30"; onApply() }
                        filterChip("30+",   isActive: ageRange == "30+")  { ageRange = "30+";  onApply() }
                    }
                    Divider().padding(.leading, 16)
                    filterRow(label: "Hair") {
                        filterChip("Any",      isActive: hairColor == nil)         { hairColor = nil;         onApply() }
                        filterChip("Blonde",   isActive: hairColor == "BLONDE")    { hairColor = "BLONDE";    onApply() }
                        filterChip("Brunette", isActive: hairColor == "BRUNETTE")  { hairColor = "BRUNETTE";  onApply() }
                        filterChip("Red",      isActive: hairColor == "RED")       { hairColor = "RED";       onApply() }
                        filterChip("Black",    isActive: hairColor == "BLACK")     { hairColor = "BLACK";     onApply() }
                    }
                    Divider().padding(.leading, 16)
                    filterRow(label: "Country") {
                        filterChip("Any",    isActive: country == nil)       { country = nil;      onApply() }
                        filterChip("US",     isActive: country == "US")      { country = "US";     onApply() }
                        filterChip("Non-US", isActive: country == "NOT_US")  { country = "NOT_US"; onApply() }
                    }
                    Divider().padding(.leading, 16)
                    filterRow(label: "Tits") {
                        filterChip("Any",     isActive: implants == nil)   { implants = nil;   onApply() }
                        filterChip("Fake",    isActive: implants == true)  { implants = true;  onApply() }
                        filterChip("Natural", isActive: implants == false) { implants = false; onApply() }
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
                    Button("Reset", role: .destructive) { onReset() }
                        .foregroundColor(.red)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    @ViewBuilder
    private func filterRow<Chips: View>(label: String, @ViewBuilder chips: () -> Chips) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 15))
                .frame(width: 80, alignment: .leading)
                .foregroundColor(.primary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) { chips() }
                    .padding(.vertical, 12)
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func filterChip(_ label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isActive ? appearance.tintColor : Color.secondary.opacity(0.15))
                .foregroundColor(isActive ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
#endif
