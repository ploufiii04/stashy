//
//  StashLineView.swift
//  stashy

#if !os(tvOS)
import SwiftUI

struct StashLineView: View {
    let performerFilter: GalleryPerformer?

    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @ObservedObject var configManager = ServerConfigManager.shared

    @State private var selectedSortOption: StashDBViewModel.ImageSortOption = .dateDesc
    @State private var selectedFilter: StashDBViewModel.SavedFilter? = nil

    init(performerFilter: GalleryPerformer? = nil) {
        self.performerFilter = performerFilter
    }

    private func performSearch() {
        viewModel.fetchImages(
            sortBy: selectedSortOption,
            filter: selectedFilter,
            staticPathFilter: true,
            performerId: performerFilter?.id
        )
    }

    var body: some View {
        Group {
            if configManager.activeConfig == nil {
                ConnectionErrorView { performSearch() }
            } else if viewModel.isLoadingImages && viewModel.allImages.isEmpty {
                VStack {
                    Spacer()
                    ProgressView("Loading StashLine...")
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if viewModel.allImages.isEmpty && viewModel.errorMessage != nil {
                ConnectionErrorView { performSearch() }
            } else if viewModel.allImages.isEmpty {
                SharedEmptyStateView(
                    icon: "camera.fill",
                    title: "No images found",
                    buttonText: "Load Images",
                    onRetry: { performSearch() }
                )
            } else {
                feedContent
            }
        }
        .navigationTitle(performerFilter?.name ?? "StashLine")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    Menu {
                        Button(action: { changeSortOption(to: .random) }) {
                            HStack { Text("Random"); if selectedSortOption == .random { Image(systemName: "checkmark") } }
                        }
                        Divider()
                        Menu {
                            Button(action: { changeSortOption(to: .dateDesc) }) {
                                HStack { Text("Newest First"); if selectedSortOption == .dateDesc { Image(systemName: "checkmark") } }
                            }
                            Button(action: { changeSortOption(to: .dateAsc) }) {
                                HStack { Text("Oldest First"); if selectedSortOption == .dateAsc { Image(systemName: "checkmark") } }
                            }
                        } label: {
                            HStack { Text("Date"); if selectedSortOption == .dateAsc || selectedSortOption == .dateDesc { Image(systemName: "checkmark") } }
                        }
                        Menu {
                            Button(action: { changeSortOption(to: .ratingDesc) }) {
                                HStack { Text("High → Low"); if selectedSortOption == .ratingDesc { Image(systemName: "checkmark") } }
                            }
                            Button(action: { changeSortOption(to: .ratingAsc) }) {
                                HStack { Text("Low → High"); if selectedSortOption == .ratingAsc { Image(systemName: "checkmark") } }
                            }
                        } label: {
                            HStack { Text("Rating"); if selectedSortOption == .ratingAsc || selectedSortOption == .ratingDesc { Image(systemName: "checkmark") } }
                        }
                        Menu {
                            Button(action: { changeSortOption(to: .createdAtDesc) }) {
                                HStack { Text("Newest First"); if selectedSortOption == .createdAtDesc { Image(systemName: "checkmark") } }
                            }
                            Button(action: { changeSortOption(to: .createdAtAsc) }) {
                                HStack { Text("Oldest First"); if selectedSortOption == .createdAtAsc { Image(systemName: "checkmark") } }
                            }
                        } label: {
                            HStack { Text("Created"); if selectedSortOption == .createdAtAsc || selectedSortOption == .createdAtDesc { Image(systemName: "checkmark") } }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                            .foregroundColor(appearanceManager.tintColor)
                    }

                    Menu {
                        Button(action: {
                            selectedFilter = nil
                            performSearch()
                        }) {
                            HStack { Text("No Filter"); if selectedFilter == nil { Image(systemName: "checkmark") } }
                        }
                        let imageFilters = viewModel.savedFilters.values
                            .filter { $0.mode == .images }
                            .sorted { $0.name < $1.name }
                        ForEach(imageFilters) { filter in
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
            let sortStr = TabManager.shared.getSortOption(for: .stashline) ?? "dateDesc"
            if let sort = StashDBViewModel.ImageSortOption(rawValue: sortStr) {
                selectedSortOption = sort
            }
            if TabManager.shared.getDefaultFilterId(for: .stashline) == nil || !viewModel.savedFilters.isEmpty {
                if viewModel.allImages.isEmpty {
                    performSearch()
                }
            }
            viewModel.fetchSavedFilters()
        }
        .onChange(of: viewModel.savedFilters) { _, newValue in
            if selectedFilter == nil {
                if let defaultId = TabManager.shared.getDefaultFilterId(for: .stashline),
                   let filter = newValue[defaultId] {
                    selectedFilter = filter
                    performSearch()
                } else if !viewModel.isLoadingSavedFilters {
                    if viewModel.allImages.isEmpty {
                        performSearch()
                    }
                }
            }
        }
        .onChange(of: viewModel.isLoadingSavedFilters) { oldValue, isLoading in
            if oldValue == true && isLoading == false {
                if viewModel.allImages.isEmpty && !viewModel.isLoadingImages && selectedFilter == nil {
                    performSearch()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
            selectedFilter = nil
            performSearch()
        }
    }

    @ViewBuilder
    private func profileHeader(performer: GalleryPerformer) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                // Avatar
                Group {
                    if let url = performer.thumbnailURL {
                        CustomAsyncImage(url: url) { loader in
                            if loader.isLoading {
                                Circle().fill(Color.gray.opacity(0.3))
                            } else if let img = loader.image {
                                img.resizable().scaledToFill()
                            } else {
                                Circle().fill(Color.gray.opacity(0.3))
                                    .overlay(Text(performer.name.prefix(1)).font(.title2.bold()).foregroundColor(.white))
                            }
                        }
                    } else {
                        Circle().fill(Color.gray.opacity(0.3))
                            .overlay(Text(performer.name.prefix(1)).font(.title2.bold()).foregroundColor(.white))
                    }
                }
                .frame(width: 96, height: 96)
                .clipShape(Circle())
                .overlay(Circle().stroke(appearanceManager.tintColor, lineWidth: 2))

                // Stats
                VStack(alignment: .leading, spacing: 8) {
                    Text(performer.name)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    HStack(spacing: 0) {
                        statColumn(value: viewModel.totalImages, label: "Images")
                        Divider().frame(height: 32).padding(.horizontal, 12)
                        statColumn(value: groupedPosts.count, label: "Sets")
                        Divider().frame(height: 32).padding(.horizontal, 12)
                        statColumn(value: viewModel.allImages.reduce(0) { $0 + ($1.o_counter ?? 0) }, label: "Counter")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)

            Divider()
        }
        .padding(.top, 20)
        .padding(.bottom, 4)
    }

    private func statColumn(value: Int, label: String) -> some View {
        VStack(spacing: 3) {
            Text("\(value)")
                .font(.system(size: 19, weight: .bold))
                .foregroundColor(.primary)
            if label.contains(".") {
                Image(systemName: label)
                    .font(.system(size: 11))
                    .foregroundColor(appearanceManager.tintColor)
            } else {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func changeSortOption(to newOption: StashDBViewModel.ImageSortOption) {
        if newOption == .random && selectedSortOption == .random {
            viewModel.refreshRandomSeed()
        }
        selectedSortOption = newOption
        TabManager.shared.setSortOption(for: .stashline, option: newOption.rawValue)
        performSearch()
    }

    // Group images by (firstPerformerId, date) — last group is tentative while more pages may load
    private var groupedPosts: [StashLinePost] {
        var posts: [StashLinePost] = []
        var current: [StashImage] = []
        var currentKey: String? = nil

        for image in viewModel.allImages {
            let key = StashLinePost.groupKey(for: image)
            if key != nil && key == currentKey {
                current.append(image)
            } else {
                if !current.isEmpty {
                    posts.append(StashLinePost(images: current))
                }
                current = [image]
                currentKey = key
            }
        }

        // Only add last group if loading is done or it has a unique key
        // (prevents incomplete sets at page boundary from rendering prematurely)
        if !current.isEmpty {
            if !viewModel.hasMoreImages || current.count > 1 {
                posts.append(StashLinePost(images: current))
            }
        }

        return posts
    }

    private var feedContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if let performer = performerFilter {
                    profileHeader(performer: performer)
                }
                ForEach(groupedPosts) { post in
                    StashLinePostView(post: post, viewModel: viewModel)
                        .onAppear {
                            if post.id == groupedPosts.last?.id {
                                viewModel.loadMoreImages()
                            }
                        }
                }

                if viewModel.isLoadingImages {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(24)
                } else if viewModel.hasMoreImages && !viewModel.allImages.isEmpty {
                    Color.clear.frame(height: 1)
                        .onAppear { viewModel.loadMoreImages() }
                }
            }
        }
        .refreshable { performSearch() }
    }
}

// MARK: - Post Model

struct StashLinePost: Identifiable {
    let id: String
    let images: [StashImage]

    init(images: [StashImage]) {
        // Sort by numeric suffix ascending so image 1 appears first in carousel
        self.images = images.sorted {
            StashLinePost.sequenceNumber(for: $0) < StashLinePost.sequenceNumber(for: $1)
        }
        self.id = images.map(\.id).sorted().joined(separator: "-")
    }

    static func sequenceNumber(for image: StashImage) -> Int {
        guard let path = image.visual_files?.first?.path ?? image.paths?.image else { return 0 }
        let filename = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        if let range = filename.range(of: #"_-_(\d+)$"#, options: .regularExpression),
           let numStr = filename[range].split(separator: "_").last,
           let n = Int(numStr) { return n }
        if let range = filename.range(of: #"_(\d+)$"#, options: .regularExpression),
           let numStr = filename[range].dropFirst().isEmpty ? nil : String(filename[range].dropFirst()),
           let n = Int(numStr) { return n }
        return 0
    }

    var primaryImage: StashImage { images[0] }
    var isSet: Bool { images.count > 1 }

    static func groupKey(for image: StashImage) -> String? {
        // Use filename prefix stripped of trailing _-_N.ext
        // e.g. "his_and_hers_-_2026-03-08_-_3.jpg" → "his_and_hers_-_2026-03-08"
        guard let path = image.visual_files?.first?.path ?? image.paths?.image else { return nil }
        let filename = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        // Strip trailing _-_<digits> or _<digits>
        let base: String
        if let range = filename.range(of: #"_-_\d+$"#, options: .regularExpression) {
            base = String(filename[..<range.lowerBound])
        } else if let range = filename.range(of: #"_\d+$"#, options: .regularExpression) {
            base = String(filename[..<range.lowerBound])
        } else {
            return nil  // no numbering pattern → not part of a set
        }
        return base
    }
}

// MARK: - Post View

struct StashLinePostView: View {
    let post: StashLinePost
    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject var appearanceManager = AppearanceManager.shared

    @State private var showHeartAnimation = false
    @State private var heartScale: CGFloat = 0
    @State private var heartOpacity: Double = 0
    @State private var localOCounter: Int
    @State private var localRating: Int
    @State private var carouselIndex = 0

    var image: StashImage { post.images[carouselIndex] }

    init(post: StashLinePost, viewModel: StashDBViewModel) {
        self.post = post
        self.viewModel = viewModel
        self._localOCounter = State(initialValue: post.primaryImage.o_counter ?? 0)
        self._localRating = State(initialValue: post.primaryImage.rating100 ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            postHeader

            // Image + overlaid action bar
            imageArea
                .overlay(alignment: .bottom) { actionBar }

            if let title = image.title, !title.isEmpty {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 4)
                Spacer().frame(height: 8)
            } else {
                Spacer().frame(height: 10)
            }

            if let tags = image.tags, !tags.isEmpty {
                tagLine(tags: tags)
            }

            Spacer().frame(height: 12)
            Divider()
        }
    }

    // MARK: - Header

    private var postHeader: some View {
        let performers = image.performers ?? []
        return HStack(spacing: 10) {
            // Performers
            HStack(spacing: 0) {
                ForEach(Array(performers.enumerated()), id: \.element.id) { idx, performer in
                    NavigationLink(destination: StashLineView(performerFilter: performer).applyAppBackground()) {
                        performerAvatar(performer, offset: idx)
                    }
                    .buttonStyle(.plain)
                }
                if performers.isEmpty {
                    Circle()
                        .fill(appearanceManager.tintColor.opacity(0.2))
                        .frame(width: 36, height: 36)
                        .overlay {
                            Image(systemName: "person.fill")
                                .foregroundColor(appearanceManager.tintColor)
                                .font(.system(size: 14))
                        }
                }
            }
            // negative spacing for overlap when multiple
            .padding(.trailing, performers.count > 1 ? CGFloat(performers.count - 1) * -10 : 0)

            // Names
            VStack(alignment: .leading, spacing: 1) {
                if performers.isEmpty {
                    Text("Unknown")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.primary)
                } else if performers.count == 1 {
                    NavigationLink(destination: StashLineView(performerFilter: performers[0]).applyAppBackground()) {
                        Text(performers[0].name)
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack(spacing: 4) {
                        ForEach(Array(performers.enumerated()), id: \.element.id) { idx, performer in
                            NavigationLink(destination: StashLineView(performerFilter: performer).applyAppBackground()) {
                                Text(performer.name)
                                    .font(.subheadline).fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)
                            if idx < performers.count - 1 {
                                Text("&")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                if let studio = image.studio {
                    Text(studio.name)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if let date = image.date {
                Text(date)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func performerAvatar(_ performer: GalleryPerformer, offset: Int) -> some View {
        Circle()
            .fill(appearanceManager.tintColor.opacity(0.2))
            .frame(width: 36, height: 36)
            .overlay {
                if let url = performer.thumbnailURL {
                    CustomAsyncImage(url: url) { loader in
                        if let img = loader.image {
                            img.resizable().scaledToFill()
                        } else {
                            Text(String(performer.name.prefix(1)).uppercased())
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(appearanceManager.tintColor)
                        }
                    }
                } else {
                    Text(String(performer.name.prefix(1)).uppercased())
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(appearanceManager.tintColor)
                }
            }
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.appBackground, lineWidth: 2))
            .offset(x: CGFloat(offset) * -10)
    }

    // MARK: - Image

    private var imageArea: some View {
        ZStack(alignment: .bottom) {
            if post.isSet {
                ZStack(alignment: .topTrailing) {
                    TabView(selection: $carouselIndex) {
                        ForEach(Array(post.images.enumerated()), id: \.offset) { index, img in
                            singleImageView(img).tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .aspectRatio(imageAspectRatio(for: post.images[0]), contentMode: .fit)

                    // Page indicator pill — top right
                    Text("\(carouselIndex + 1)/\(post.images.count)")
                        .font(.caption2).fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(DesignTokens.Opacity.badge))
                        .clipShape(Capsule())
                        .padding(8)
                }
            } else {
                singleImageView(image)
                    .aspectRatio(imageAspectRatio(for: image), contentMode: .fit)
            }

            // Counter burst animation
            if showHeartAnimation {
                Image(systemName: appearanceManager.oCounterIconFilled)
                    .font(.system(size: 80))
                    .foregroundColor(appearanceManager.tintColor.opacity(0.9))
                    .scaleEffect(heartScale)
                    .opacity(heartOpacity)
                    .shadow(color: .black.opacity(0.3), radius: 8)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func imageAspectRatio(for img: StashImage) -> CGFloat {
        if let w = img.visual_files?.first?.width, let h = img.visual_files?.first?.height, h > 0 {
            return CGFloat(w) / CGFloat(h)
        }
        return 1.0
    }

    @ViewBuilder
    private func singleImageView(_ img: StashImage) -> some View {
        ZStack {
            Color.studioHeaderGray
            if let url = img.thumbnailURL {
                CustomAsyncImage(url: url) { loader in
                    if loader.isLoading {
                        ProgressView().frame(maxWidth: .infinity)
                    } else if let loaded = loader.image {
                        loaded.resizable().scaledToFit().frame(maxWidth: .infinity)
                    } else {
                        Image(systemName: "photo").font(.system(size: 40)).foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
            } else {
                Image(systemName: "photo").font(.system(size: 40)).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack {
            // O-counter pill (left)
            Button(action: { incrementOCounter() }) {
                HStack(spacing: 4) {
                    Image(systemName: localOCounter > 0 ? appearanceManager.oCounterIconFilled : appearanceManager.oCounterIcon)
                        .font(.system(size: 16))
                        .foregroundColor(localOCounter > 0 ? appearanceManager.tintColor : .white)
                    Text("\(localOCounter)")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(DesignTokens.Opacity.badge))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            // Rating pill (right)
            StarRatingView(
                rating100: localRating,
                isInteractive: true,
                size: 16,
                spacing: 4,
                isVertical: false
            ) { newRating in
                let originalRating = localRating
                localRating = newRating ?? 0
                viewModel.updateImageRating(imageId: image.id, rating100: newRating) { success in
                    if !success {
                        DispatchQueue.main.async { localRating = originalRating }
                        ToastManager.shared.show("Failed to save rating", icon: "exclamationmark.triangle", style: .error)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.black.opacity(DesignTokens.Opacity.badge))
            .clipShape(Capsule())
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
    }

    // MARK: - Performer Line

    private func performerLine(performers: [GalleryPerformer]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(performers) { performer in
                    Text(performer.name)
                        .font(.caption).fontWeight(.semibold)
                        .foregroundColor(appearanceManager.tintColor)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(appearanceManager.tintColor.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Tag Line

    private func tagLine(tags: [Tag]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags.prefix(8)) { tag in
                    Text("#\(tag.name)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.bottom, 4)
    }

    // MARK: - O-Counter Logic

    private func incrementOCounter() {
        let originalCount = localOCounter
        localOCounter += 1

        // Burst animation
        showHeartAnimation = true
        heartScale = 0.3
        heartOpacity = 1
        withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
            heartScale = 1.2
        }
        withAnimation(.easeOut(duration: 0.25).delay(0.35)) {
            heartOpacity = 0
            heartScale = 1.5
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            showHeartAnimation = false
            heartScale = 0
        }

        // Persist via increment mutation (same as ReelsView clips)
        viewModel.incrementImageOCounter(imageId: image.id) { returnedCount in
            if let count = returnedCount {
                DispatchQueue.main.async { localOCounter = count }
            } else {
                DispatchQueue.main.async {
                    localOCounter = originalCount
                    ToastManager.shared.show("Counter update failed", icon: "exclamationmark.triangle", style: .error)
                }
            }
        }
    }
}
#endif
