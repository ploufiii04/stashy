//
//  StashLineView.swift
//  stashy

#if !os(tvOS)
import SwiftUI

struct StashLineView: View {
    @State var performerFilter: GalleryPerformer?

    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @ObservedObject var configManager = ServerConfigManager.shared

    @State private var selectedSortOption: StashDBViewModel.ImageSortOption = .dateDesc
    @State private var selectedFilter: StashDBViewModel.SavedFilter? = nil

    init(performerFilter: GalleryPerformer? = nil) {
        _performerFilter = State(initialValue: performerFilter)
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PerformerImageUpdated"))) { notification in
            if let targetId = notification.userInfo?["performerId"] as? String,
               let newPath = notification.userInfo?["newImagePath"] as? String {
                if performerFilter?.id == targetId {
                    performerFilter?.image_path = newPath
                }
                
                // Update avatars in this specific view model's list
                for i in 0..<viewModel.allImages.count {
                    if var mutablePerformers = viewModel.allImages[i].performers, 
                       let pIndex = mutablePerformers.firstIndex(where: { $0.id == targetId }) {
                        mutablePerformers[pIndex].image_path = newPath
                        viewModel.allImages[i].performers = mutablePerformers
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func profileHeader(performer: GalleryPerformer) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                // Avatar
                NavigationLink(destination: PerformerDetailView(performer: performer.toPerformer())) {
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
                }
                .buttonStyle(.plain)

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

    // Group images by stable key (basename + performerIds + date).
    // Non-consecutive grouping: all images sharing a key are merged regardless of position.
    // Order of first appearance determines post order in feed.
    private var groupedPosts: [StashLinePost] {
        var keyOrder: [String] = []
        var groups: [String: [StashImage]] = [:]

        for image in viewModel.allImages {
            if let key = StashLinePost.groupKey(for: image) {
                if groups[key] == nil {
                    keyOrder.append(key)
                    groups[key] = []
                }
                groups[key]!.append(image)
            } else {
                // No groupable key → single post, use image id as unique key
                let fallback = "solo-\(image.id)"
                keyOrder.append(fallback)
                groups[fallback] = [image]
            }
        }

        // Hold back last group while more pages may load — it could grow
        let lastKey = keyOrder.last
        let posts = keyOrder.compactMap { key -> StashLinePost? in
            guard let images = groups[key] else { return nil }
            // If last group is incomplete (still loading), skip unless multi-image
            if key == lastKey && viewModel.hasMoreImages && images.count == 1
                && StashLinePost.groupKey(for: images[0]) != nil {
                return nil
            }
            return StashLinePost(images: images)
        }

        // Debug log
        let context = performerFilter != nil ? "PROFILE[\(performerFilter!.name)]" : "TIMELINE"
        print("=== StashLine groupedPosts [\(context)] total images: \(viewModel.allImages.count) → \(posts.count) posts ===")
        for (i, post) in posts.enumerated() {
            let key = StashLinePost.groupKey(for: post.primaryImage) ?? "solo-\(post.primaryImage.id)"
            print("  [\(i)] \(post.images.count)x | key=\(key)")
            for img in post.images {
                let filename = (img.visual_files?.first?.path ?? img.paths?.image).map { URL(fileURLWithPath: $0).lastPathComponent } ?? "?"
                let imgDate = img.date ?? "nil"
                let performers = img.performers?.map(\.id).sorted().joined(separator: ",") ?? "nil"
                print("    - id=\(img.id) file=\(filename) image.date=\(imgDate) performers=[\(performers)]")
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
        self.images = images
        self.id = images.map(\.id).sorted().joined(separator: "-")
    }

    var primaryImage: StashImage { images[0] }
    var isSet: Bool { images.count > 1 }

    // Group key: performerIds | date | galleryIds | sessionTimestamp
    // - performers + date must be present
    // - gallery IDs separate images from different galleries on same date
    // - sessionTimestamp: extracted from filename between _-_ and last _<digits>
    //   e.g. "042_-_2026-01-12_12-39-43_0.jpg" → "2026-01-12_12-39-43"
    //   if not present (no _-_ pattern), falls back to empty string
    static func groupKey(for image: StashImage) -> String? {
        guard let performers = image.performers, !performers.isEmpty,
              let date = image.date, !date.isEmpty else { return nil }

        let performerKey = performers.map(\.id).sorted().joined(separator: ",")
        let galleryKey = image.galleries?.map(\.id).sorted().joined(separator: ",") ?? ""

        // Extract session timestamp from filename: part between _-_ and trailing _<digits>
        let sessionKey: String
        if let path = image.visual_files?.first?.path ?? image.paths?.image {
            let filename = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            if let match = filename.range(of: #"(?<=_-_).+(?=_\d+$)"#, options: .regularExpression) {
                sessionKey = String(filename[match])
            } else {
                sessionKey = ""
            }
        } else {
            sessionKey = ""
        }

        // Orientation: portrait vs landscape — mixed orientations get separate groups
        let orientation: String
        if let w = image.visual_files?.first?.width, let h = image.visual_files?.first?.height {
            orientation = w >= h ? "L" : "P"
        } else {
            orientation = ""
        }

        return "\(performerKey)|\(date)|\(galleryKey)|\(sessionKey)|\(orientation)"
    }
}

// MARK: - Post View

struct ShareWrapper: Identifiable {
    let id = UUID()
    let items: [Any]
}

struct StashLinePostView: View {
    let post: StashLinePost
    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject var appearanceManager = AppearanceManager.shared

    @State private var showHeartAnimation = false
    @State private var heartScale: CGFloat = 0
    @State private var heartOpacity: Double = 0
    @State private var oCounters: [String: Int]
    @State private var ratings: [String: Int]
    @State private var carouselIndex = 0
    @State private var isExpanded = false
    @State private var showDeleteConfirmation = false
    @State private var showShareConfirmation = false
    @State private var activeShareWrapper: ShareWrapper?
    @State private var showSetPerformerImagePicker = false
    @State private var performerImageTargetPerformers: [GalleryPerformer] = []
    @AppStorage("stashline_crop_enabled") private var cropEnabled = true

    var image: StashImage { post.images[carouselIndex] }
    var localOCounter: Int { oCounters[image.id] ?? image.o_counter ?? 0 }
    var localRating: Int { ratings[image.id] ?? image.rating100 ?? 0 }

    init(post: StashLinePost, viewModel: StashDBViewModel) {
        self.post = post
        self.viewModel = viewModel
        self._oCounters = State(initialValue: [:])
        self._ratings = State(initialValue: [:])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            postHeader

            // Image + overlaid action bar
            imageArea
                .overlay(alignment: .bottom) { actionBar }

            HStack(alignment: .top) {
                if let title = image.title, !title.isEmpty {
                    Text(title)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                }
                Spacer()
                
                HStack(spacing: 16) {
                    Button {
                        if post.isSet {
                            showShareConfirmation = true
                        } else {
                            shareImage(shareWholeSet: false)
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(appearanceManager.tintColor)
                    }
                    if let performers = image.performers, !performers.isEmpty {
                        Button {
                            performerImageTargetPerformers = performers
                            showSetPerformerImagePicker = true
                        } label: {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .foregroundColor(appearanceManager.tintColor)
                        }
                    }
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .foregroundColor(appearanceManager.tintColor)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)

            if let tags = image.tags, !tags.isEmpty {
                tagLine(tags: tags)
            }

            Spacer().frame(height: 12)
            Divider()
        }
        .alert("Set as Performer Image?", isPresented: $showSetPerformerImagePicker) {
            ForEach(performerImageTargetPerformers) { performer in
                Button("Okay") {
                    setPerformerImage(performer: performer)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Update the profile picture for the selected performer.")
        }
        .alert("Delete", isPresented: $showDeleteConfirmation) {
            if post.isSet {
                Button("Delete Single Image", role: .destructive) {
                    deleteImage(deleteWholeSet: false)
                }
                Button("Delete Entire Set (\(post.images.count) images)", role: .destructive) {
                    deleteImage(deleteWholeSet: true)
                }
            } else {
                Button("Delete Image", role: .destructive) {
                    deleteImage(deleteWholeSet: false)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text(post.isSet ? "Do you want to delete only this image or the entire set?" : "This image will be permanently deleted. This action cannot be undone.")
        }
        .alert("Share", isPresented: $showShareConfirmation) {
            Button("Share Single Image") {
                shareImage(shareWholeSet: false)
            }
            Button("Share Entire Set (\(post.images.count) images)") {
                shareImage(shareWholeSet: true)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Do you want to share only this image or the entire set?")
        }
        .sheet(item: $activeShareWrapper) { wrapper in
            ShareSheet(items: wrapper.items)
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
                            singleImageView(img, ratio: imageAspectRatio(for: img)).tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .aspectRatio(imageAspectRatio(for: image), contentMode: .fit)
                    .clipped()

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
                GeometryReader { geo in
                    singleImageView(image, ratio: imageAspectRatio(for: image))
                        .frame(width: geo.size.width, height: geo.size.width / imageAspectRatio(for: image))
                }
                .aspectRatio(imageAspectRatio(for: image), contentMode: .fit)
                .clipped()
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
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            withAnimation(.easeInOut(duration: 0.25)) { isExpanded.toggle() }
        }
    }

    private func imageAspectRatio(for img: StashImage) -> CGFloat {
        if let w = img.visual_files?.first?.width, let h = img.visual_files?.first?.height, h > 0 {
            let native = CGFloat(w) / CGFloat(h)
            if isExpanded || !cropEnabled { return native }
            return w >= h ? 16.0 / 9.0 : 4.0 / 5.0
        }
        return cropEnabled ? 4.0 / 5.0 : 1.0
    }

    @ViewBuilder
    private func singleImageView(_ img: StashImage, ratio: CGFloat) -> some View {
        ZStack {
            Color.studioHeaderGray
            if let url = img.thumbnailURL {
                CustomAsyncImage(url: url) { loader in
                    if loader.isLoading {
                        ProgressView().frame(maxWidth: .infinity)
                    } else if let loaded = loader.image {
                        if isExpanded || !cropEnabled {
                            loaded.resizable().scaledToFit().frame(maxWidth: .infinity)
                        } else {
                            loaded.resizable().scaledToFill().frame(maxWidth: .infinity)
                        }
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
        .clipped()
        .allowsHitTesting(false)
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
                let imageId = image.id
                let originalRating = localRating
                ratings[imageId] = newRating ?? 0
                viewModel.updateImageRating(imageId: imageId, rating100: newRating) { success in
                    if !success {
                        DispatchQueue.main.async { self.ratings[imageId] = originalRating }
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
        let imageId = image.id
        let originalCount = localOCounter
        oCounters[imageId] = originalCount + 1

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
        viewModel.incrementImageOCounter(imageId: imageId) { returnedCount in
            if let count = returnedCount {
                DispatchQueue.main.async { self.oCounters[imageId] = count }
            } else {
                DispatchQueue.main.async {
                    self.oCounters[imageId] = originalCount
                    ToastManager.shared.show("Counter update failed", icon: "exclamationmark.triangle", style: .error)
                }
            }
        }
    }
    
    // MARK: - Local Actions

    private func deleteImage(deleteWholeSet: Bool) {
        let targets = deleteWholeSet ? post.images : [image]
        
        for target in targets {
            viewModel.deleteImage(imageId: target.id) { success in
                DispatchQueue.main.async {
                    if success {
                        withAnimation {
                            if let index = self.viewModel.allImages.firstIndex(where: { $0.id == target.id }) {
                                self.viewModel.allImages.remove(at: index)
                            }
                        }
                    } else {
                        ToastManager.shared.show("Failed to delete image \(target.id)", icon: "exclamationmark.triangle", style: .error)
                    }
                }
            }
        }
        ToastManager.shared.show(deleteWholeSet ? "Deleting set..." : "Deleting image...", icon: "trash", style: .success)
    }

    private func shareImage(shareWholeSet: Bool) {
        let targets = shareWholeSet ? post.images : [image]
        
        Task {
            var items: [Any] = []
            let sessionConfig = URLSessionConfiguration.default
            sessionConfig.timeoutIntervalForRequest = 60
            let session = URLSession(configuration: sessionConfig, delegate: ImageLoaderSessionDelegate(), delegateQueue: nil)
            let apiKey = ServerConfigManager.shared.activeConfig?.secureApiKey ?? ""
            
            for target in targets {
                guard let url = target.imageURL else { continue }
                var request = URLRequest(url: url)
                if !apiKey.isEmpty {
                    request.addValue(apiKey, forHTTPHeaderField: "ApiKey")
                }
                guard let (data, response) = try? await session.data(for: request) else { continue }
                
                let mimeType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""
                let isVideo = mimeType.contains("video") || url.absoluteString.lowercased().contains(".mp4")
                
                if isVideo {
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString)
                        .appendingPathExtension("mp4")
                    guard (try? data.write(to: tempURL)) != nil else { continue }
                    items.append(tempURL)
                } else {
                    guard let uiImage = UIImage(data: data) else { continue }
                    items.append(uiImage)
                }
            }
            
            await MainActor.run {
                if !items.isEmpty {
                    self.activeShareWrapper = ShareWrapper(items: items)
                }
            }
        }
    }

    private func setPerformerImage(performer: GalleryPerformer) {
        let urlObj: URL?
        if let ext = image.fileExtension, ["JPG", "JPEG", "PNG", "WEBP"].contains(ext.uppercased()) {
            urlObj = image.imageURL
        } else {
            urlObj = image.thumbnailURL
        }
        
        guard let url = urlObj?.absoluteString else { return }

        viewModel.setPerformerImage(performerId: performer.id, imageURL: url) { success in
            DispatchQueue.main.async {
                if success {
                    ToastManager.shared.show("Performer image updated", icon: "person.crop.circle.badge.checkmark", style: .success)
                    
                    // Visually update the avatar everywhere in allImages by overriding image_path
                    let bustedUrl = "\(url)?bust=\(UUID().uuidString)"
                    for i in 0..<self.viewModel.allImages.count {
                        if var mutablePerformers = self.viewModel.allImages[i].performers, 
                           let pIndex = mutablePerformers.firstIndex(where: { $0.id == performer.id }) {
                            mutablePerformers[pIndex].image_path = bustedUrl
                            self.viewModel.allImages[i].performers = mutablePerformers
                        }
                    }
                    
                    NotificationCenter.default.post(
                        name: NSNotification.Name("PerformerImageUpdated"),
                        object: nil,
                        userInfo: [
                            "performerId": performer.id,
                            "newImagePath": bustedUrl
                        ]
                    )
                } else {
                    ToastManager.shared.show("Failed to update performer image", icon: "exclamationmark.triangle", style: .error)
                }
            }
        }
    }
}
#endif
