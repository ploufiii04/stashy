//
//  StashLineView.swift
//  stashy

#if !os(tvOS)
import SwiftUI

struct StashLineView: View {
    let externalPerformerFilter: GalleryPerformer?
    @State private var performerFilter: GalleryPerformer?
    let isEmbedded: Bool
    var onPerformerTap: ((GalleryPerformer) -> Void)? = nil

    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @ObservedObject var configManager = ServerConfigManager.shared
    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject private var coordinator: NavigationCoordinator
    @State private var selectedSortOption: StashDBViewModel.ImageSortOption = .dateDesc
    @State private var selectedFilter: StashDBViewModel.SavedFilter? = nil
    @State private var scrollPositionId: String?
    @State private var pendingRestoreId: String?
    @State private var cachedPosts: [StashLinePost] = []
    @AppStorage("stashline_group_by_orientation") private var groupByOrientation: Bool = true
    @State private var sessionKeyCache: [String: String] = [:] // imageId -> sessionKey ("" if absent)
    @State private var shouldScrollToTopAfterReload: Bool = false
    init(performerFilter: GalleryPerformer? = nil, isEmbedded: Bool = false, onPerformerTap: ((GalleryPerformer) -> Void)? = nil) {
        self.externalPerformerFilter = performerFilter
        _performerFilter = State(initialValue: performerFilter)
        self.isEmbedded = isEmbedded
        self.onPerformerTap = onPerformerTap
    }

    private func performSearch() {
        viewModel.fetchImages(
            sortBy: selectedSortOption,
            filter: selectedFilter,
            staticPathFilter: true,
            performerId: performerFilter?.id
        )
    }

    private func rebuildGroupedPosts() {
        cachedPosts = computeGroupedPosts()
    }

    private func menuLabelText(_ text: String, systemImage: String, tint: Color? = nil) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.85)
            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .foregroundColor(tint ?? .primary)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private var sortMenu: some View {
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
            menuLabelText(selectedSortOption.displayName, systemImage: "arrow.up.arrow.down")
        }
        .frame(maxWidth: .infinity)
    }

    private var filterMenu: some View {
        Menu {
            Button(action: {
                selectedFilter = nil
                // Manual timeline change → jump to top after reload
                viewModel.clearStashLineFrozenSnapshot()
                shouldScrollToTopAfterReload = true
                scrollPositionId = nil
                pendingRestoreId = nil
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
                    // Manual timeline change → jump to top after reload
                    viewModel.clearStashLineFrozenSnapshot()
                    shouldScrollToTopAfterReload = true
                    scrollPositionId = nil
                    pendingRestoreId = nil
                    performSearch()
                }) {
                    HStack {
                        Text(filter.name)
                        if selectedFilter?.id == filter.id { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            menuLabelText(
                selectedFilter?.name ?? "Filter",
                systemImage: "line.3.horizontal.decrease",
                tint: selectedFilter != nil ? appearanceManager.tintColor : .primary
            )
        }
        .frame(maxWidth: .infinity)
    }

    private var floatingBarContent: some View {
        HStack(spacing: 0) {
            sortMenu
            Divider().frame(height: 20)
            filterMenu
        }
    }

    var body: some View {
        Group {
            if configManager.activeConfig == nil {
                ConnectionErrorView { performSearch() }
            } else if viewModel.isLoadingImages && viewModel.allImages.isEmpty {
                StandardLoadingView(message: "Loading StashLine...")
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
        .navigationBarHidden(true)
        .if(!isEmbedded) { view in
            view.safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        if performerFilter != nil {
                            Button(action: { dismiss() }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 17, weight: .semibold))
                                }
                                .foregroundColor(appearanceManager.tintColor)
                            }
                            .buttonStyle(.plain)
                        }
                        Text(performerFilter?.name ?? "StashLine")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 32)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)

                    Divider().overlay(Color.white.opacity(0.15))
                }
                .background(.bar)
                .colorScheme(.dark)
            }
        }
        .floatingActionBar {
            floatingBarContent
        }
        .onAppear {
            let sortStr = TabManager.shared.getSortOption(for: .stashline) ?? "createdAtDesc"
            if let sort = StashDBViewModel.ImageSortOption(rawValue: sortStr) {
                selectedSortOption = sort
            }
            if TabManager.shared.getDefaultFilterId(for: .stashline) == nil || !viewModel.savedFilters.isEmpty {
                if viewModel.allImages.isEmpty {
                    performSearch()
                }
            }
            viewModel.fetchSavedFilters()
            let savedId = performerFilter.flatMap { coordinator.picsPerformerScrollIds[$0.id] } ?? coordinator.picsGlobalScrollId
            if !viewModel.allImages.isEmpty {
                if let id = savedId { scrollPositionId = id }
            } else {
                pendingRestoreId = savedId
            }
            rebuildGroupedPosts()
        }
        .onChange(of: selectedSortOption) { _, _ in
            rebuildGroupedPosts()
        }
        .onChange(of: viewModel.allImages.count) { _, _ in
            rebuildGroupedPosts()
        }
        .onChange(of: viewModel.allImages.first?.id) { _, _ in
            rebuildGroupedPosts()
        }
        .onChange(of: viewModel.allImages.last?.id) { _, _ in
            rebuildGroupedPosts()
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
        .onChange(of: viewModel.isLoadingImages) { wasLoading, isLoading in
            print("🔄 isLoadingImages \(wasLoading)→\(isLoading) | pendingRestore=\(pendingRestoreId ?? "nil")")
            if wasLoading && !isLoading, let id = pendingRestoreId {
                pendingRestoreId = nil
                DispatchQueue.main.async { scrollPositionId = id }
            }
            if wasLoading && !isLoading, shouldScrollToTopAfterReload {
                shouldScrollToTopAfterReload = false
                DispatchQueue.main.async {
                    // After reload/group rebuild, jump to the first post if available.
                    if let first = cachedPosts.first?.id {
                        scrollPositionId = first
                    } else {
                        scrollPositionId = nil
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
            selectedFilter = nil
            performSearch()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("PerformerImageUpdated"))) { notification in
            guard let targetId = notification.userInfo?["performerId"] as? String,
                  let newPath = notification.userInfo?["newImagePath"] as? String else { return }
            if performerFilter?.id == targetId {
                performerFilter?.image_path = newPath
            }
            // Patch allImages so future rebuilds have the correct URL.
            for i in 0..<viewModel.allImages.count {
                if var mutablePerformers = viewModel.allImages[i].performers,
                   let pIndex = mutablePerformers.firstIndex(where: { $0.id == targetId }) {
                    mutablePerformers[pIndex].image_path = newPath
                    viewModel.allImages[i].performers = mutablePerformers
                }
            }
            // Update cachedPosts in-place so the avatar refreshes without
            // replacing the array (which would cause the scroll view to jump).
            cachedPosts = cachedPosts.map { post in
                let updatedImages = post.images.map { img -> StashImage in
                    guard var mutablePerformers = img.performers,
                          let pIndex = mutablePerformers.firstIndex(where: { $0.id == targetId })
                    else { return img }
                    var mutableImg = img
                    mutablePerformers[pIndex].image_path = newPath
                    mutableImg.performers = mutablePerformers
                    return mutableImg
                }
                return StashLinePost(images: updatedImages)
            }
        }
        .onChange(of: scrollPositionId) { _, newId in
            print("📍 scrollPositionId changed → \(newId ?? "nil") | pendingRestore=\(pendingRestoreId ?? "nil") | performer=\(performerFilter?.name ?? "global")")
            guard pendingRestoreId == nil, let id = newId else { return }
            if let pid = performerFilter?.id {
                coordinator.picsPerformerScrollIds[pid] = id
            } else {
                coordinator.picsGlobalScrollId = id
            }
        }
        .onChange(of: performerFilter) { oldPerformer, newPerformer in
            print("🎭 performerFilter changed \(oldPerformer?.name ?? "global") → \(newPerformer?.name ?? "global") | scrollId=\(scrollPositionId ?? "nil") | globalSaved=\(coordinator.picsGlobalScrollId ?? "nil")")
            // Save current position for performer views being left
            if let pid = oldPerformer?.id, let id = scrollPositionId {
                coordinator.picsPerformerScrollIds[pid] = id
            }
            // Global position is saved continuously by onChange(of: scrollPositionId)
            // and explicitly by performer tap — don't overwrite here
            // Clear scroll position so stale ID doesn't confuse the new dataset
            scrollPositionId = nil
            // Queue restore for the new filter
            if let newPid = newPerformer?.id {
                pendingRestoreId = coordinator.picsPerformerScrollIds[newPid]
            } else {
                pendingRestoreId = coordinator.picsGlobalScrollId
            }
            performSearch()
        }
        .onChange(of: externalPerformerFilter) { _, newValue in
            performerFilter = newValue
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
                        statColumn(value: cachedPosts.count, label: "Sets")
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
        // Reset scroll state so the list cleanly jumps to the top after the reload.
        shouldScrollToTopAfterReload = true
        pendingRestoreId = nil
        scrollPositionId = nil
        if let pid = performerFilter?.id {
            coordinator.picsPerformerScrollIds[pid] = nil
        } else {
            coordinator.picsGlobalScrollId = nil
        }
        performSearch()
    }

    private func computeGroupedPosts() -> [StashLinePost] {
        // Future grouping rules (requested):
        // - We only group while sorting by Date or Created.
        // - Grouping is *consecutive*: iterate the already-sorted list and keep
        //   appending as long as performer-set + gallery-set + orientation stay identical.
        // - No filename/session parsing; no non-consecutive merging.
        let shouldGroupConsecutively: Bool = {
            switch selectedSortOption {
            case .dateAsc, .dateDesc, .createdAtAsc, .createdAtDesc:
                return true
            default:
                return false
            }
        }()

        func performerKey(_ image: StashImage) -> String {
            let ids = (image.performers ?? []).map(\.id).sorted()
            return ids.joined(separator: ",")
        }

        func galleryKey(_ image: StashImage) -> String {
            // Use only the first (alphabetically) gallery ID so images that share
            // a gallery but also belong to other galleries still group together.
            return (image.galleries ?? []).map(\.id).sorted().first ?? ""
        }

        // Resolved orientation (independent of groupByOrientation toggle).
        func resolvedOrientationKey(_ image: StashImage) -> String {
            if let w = image.visual_files?.first?.width,
               let h = image.visual_files?.first?.height, h > 0 {
                return (w >= h) ? "L" : "P"
            }
            return "P" // treat unknown as portrait
        }

        func sessionKey(_ image: StashImage) -> String {
            // Optional grouping discriminator: if the stash-generated filename contains
            // a session timestamp between "_-_" and the trailing "_<digits>", use it.
            // Example: "042_-_2026-01-12_12-39-43_0.jpg" -> "2026-01-12_12-39-43"
            if let cached = sessionKeyCache[image.id] { return cached }
            let path = image.visual_files?.first?.path ?? image.paths?.image
            guard let path else {
                sessionKeyCache[image.id] = ""
                return ""
            }
            let filename = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            // Fast pre-check to avoid regex unless it can possibly match.
            guard filename.contains("_-_") else {
                sessionKeyCache[image.id] = ""
                return ""
            }
            guard let match = filename.range(of: #"(?<=_-_).+(?=_\d+$)"#, options: .regularExpression) else {
                sessionKeyCache[image.id] = ""
                return ""
            }
            let key = String(filename[match])
            sessionKeyCache[image.id] = key
            return key
        }

        // Extracts the trailing counter (_0, _1, _42 …) from the filename for in-group ordering.
        func imageIndex(_ image: StashImage) -> Int {
            let path = image.visual_files?.first?.path ?? image.paths?.image ?? ""
            let filename = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            guard let match = filename.range(of: #"_(\d+)$"#, options: .regularExpression) else { return 0 }
            return Int(filename[match].dropFirst()) ?? 0
        }

        // Segment key:
        // - Always uses performer set
        // - Uses sessionKey when available (best discriminator for "image sets")
        // - Falls back to primary gallery only when sessionKey is missing
        // (Orientation never breaks the segment; it is only split inside flush()).
        func groupKey(_ image: StashImage) -> String {
            let session = sessionKey(image)
            if !session.isEmpty {
                return "\(performerKey(image))|\(galleryKey(image))|\(session)"
            }
            return "\(performerKey(image))|\(galleryKey(image))"
        }

        guard shouldGroupConsecutively else {
            // No grouping in other sorts: keep the feed exactly as delivered.
            return viewModel.allImages.map { StashLinePost(images: [$0]) }
        }

        // Local tie-breakers for "Sort by Date":
        // Stash often returns images with identical `date` in an arbitrary order
        // (e.g. many galleries on the same day interleaved). Since our grouping
        // is consecutive, we re-order *within the same date bucket* to keep
        // galleries/sets contiguous, without changing the overall date ordering.
        let imagesForGrouping: [StashImage] = {
            switch selectedSortOption {
            case .dateAsc, .dateDesc:
                let ascending = (selectedSortOption == .dateAsc)
                func timeKey(_ img: StashImage) -> String {
                    // When sorting by date, fall back to createdAt if date missing.
                    // Both are ISO-like strings, so lexical compare is stable enough here.
                    return (img.date?.isEmpty == false ? img.date! : (img.createdAt ?? ""))
                }
                func titleIndex(_ img: StashImage) -> Int {
                    if let t = img.title, let n = Int(t.trimmingCharacters(in: .whitespacesAndNewlines)) { return n }
                    return 0
                }
                return viewModel.allImages.sorted { a, b in
                    let ta = timeKey(a)
                    let tb = timeKey(b)
                    if ta != tb { return ascending ? (ta < tb) : (ta > tb) }

                    let ga = galleryKey(a)
                    let gb = galleryKey(b)
                    if ga != gb { return ga < gb }

                    let sa = sessionKey(a)
                    let sb = sessionKey(b)
                    if sa != sb { return sa < sb }

                    let ia = imageIndex(a)
                    let ib = imageIndex(b)
                    if ia != ib { return ia < ib }

                    let na = titleIndex(a)
                    let nb = titleIndex(b)
                    if na != nb { return na < nb }

                    return a.id < b.id
                }
            default:
                return viewModel.allImages
            }
        }()

        var posts: [StashLinePost] = []
        var currentKey: String? = nil
        var buffer: [StashImage] = []

        func flush() {
            guard !buffer.isEmpty else { return }
            defer { buffer.removeAll(keepingCapacity: true) }

            if groupByOrientation {
                // Split buffer into portrait and landscape sub-posts,
                // preserving the order of first appearance of each orientation.
                var portrait: [StashImage] = []
                var landscape: [StashImage] = []
                var firstOrientation: String? = nil
                for img in buffer {
                    let ori = resolvedOrientationKey(img)
                    if firstOrientation == nil { firstOrientation = ori }
                    if ori == "L" { landscape.append(img) } else { portrait.append(img) }
                }
                let groups: [[StashImage]] = (firstOrientation == "L")
                    ? [landscape, portrait]
                    : [portrait, landscape]
                for group in groups where !group.isEmpty {
                    posts.append(StashLinePost(images: group.sorted { imageIndex($0) < imageIndex($1) }))
                }
            } else {
                // No orientation split – all images in one post, sorted by filename index.
                posts.append(StashLinePost(images: buffer.sorted { imageIndex($0) < imageIndex($1) }))
            }
        }

        for image in imagesForGrouping {
            let key = groupKey(image)
            if currentKey == nil {
                currentKey = key
                buffer = [image]
                continue
            }
            if key == currentKey {
                buffer.append(image)
            } else {
                flush()
                currentKey = key
                buffer = [image]
            }
        }
        flush()

        return posts
    }

    private var feedContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if let performer = performerFilter, !isEmbedded {
                    profileHeader(performer: performer)
                }
                ForEach(cachedPosts) { post in
                    StashLinePostView(post: post, viewModel: viewModel, onPerformerTap: onPerformerTap != nil ? { performer in
                        coordinator.picsGlobalScrollId = post.id
                        onPerformerTap?(performer)
                    } : nil)
                    .onAppear {
                        if post.id == cachedPosts.last?.id {
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
            .scrollTargetLayout()
        }
        .scrollPosition(id: $scrollPositionId, anchor: .center)
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

    enum TimeAnchor {
        /// Uses `image.date` (metadata/shoot date). Strict: if missing, do not group.
        case date
        /// Uses `image.createdAt` (DB timestamp). Strict: if missing, do not group.
        case createdAt
        /// Best-effort: prefer `createdAt`, fall back to `date`.
        case bestEffort
    }

    // Group key: performerIds | timeKey | galleryIds | sessionTimestamp
    // - performers + timeKey must be present
    // - gallery IDs separate images from different galleries on same bucket
    // - sessionTimestamp: extracted from filename between _-_ and last _<digits>
    //   e.g. "042_-_2026-01-12_12-39-43_0.jpg" → "2026-01-12_12-39-43"
    //   if not present (no _-_ pattern), falls back to empty string
    static func groupKey(for image: StashImage, anchor: TimeAnchor) -> String? {
        func dayOnly(_ raw: String?) -> String? {
            guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
            // Typical formats:
            // - "YYYY-MM-DD"
            // - ISO-8601 "YYYY-MM-DDTHH:MM:SS+02:00"
            if let t = s.firstIndex(of: "T") {
                s = String(s[..<t])
            }
            // Safety: keep only the leading YYYY-MM-DD when present
            if s.count >= 10 {
                return String(s.prefix(10))
            }
            return s
        }

        // Grouping should always be per single performer.
        // If there are 0 or multiple performers (collabs), do not group.
        guard let performers = image.performers, performers.count == 1 else { return nil }
        let performerKey = performers[0].id

        let galleryKey = image.galleries?.map(\.id).sorted().joined(separator: ",") ?? ""
        
        let timeKeyRaw: String? = {
            switch anchor {
            case .date:
                // When sorting/grouping by "Date", prefer the explicit shoot/metadata date,
                // but fall back to DB timestamp so sets still group when `date` is missing.
                return (image.date?.isEmpty == false ? image.date : (image.createdAt?.isEmpty == false ? image.createdAt : nil))
            case .createdAt:
                return (image.createdAt?.isEmpty == false ? image.createdAt : nil)
            case .bestEffort:
                return (image.createdAt?.isEmpty == false ? image.createdAt : (image.date?.isEmpty == false ? image.date : nil))
            }
        }()
        let timeKey = dayOnly(timeKeyRaw)
        guard let timeKey, !timeKey.isEmpty else { return nil }

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
        
        // Only group when we have a reliable session timestamp.
        guard !sessionKey.isEmpty else { return nil }

        // Orientation: portrait vs landscape — mixed orientations get separate groups
        let orientation: String
        if let w = image.visual_files?.first?.width, let h = image.visual_files?.first?.height {
            orientation = w >= h ? "L" : "P"
        } else {
            orientation = ""
        }

        return "\(performerKey)|\(timeKey)|\(galleryKey)|\(sessionKey)|\(orientation)"
    }

    static func groupSortComponents(fromKey key: String) -> (performer: String, timeKey: String, gallery: String, session: String, orientation: String) {
        if key.hasPrefix("solo-") {
            // Put solos at the end, but keep deterministic ordering
            return (performer: "", timeKey: "", gallery: "", session: "", orientation: "")
        }
        let parts = key.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        // performer|timeKey|gallery|session|orientation
        return (
            performer: parts.count > 0 ? parts[0] : "",
            timeKey: parts.count > 1 ? parts[1] : "",
            gallery: parts.count > 2 ? parts[2] : "",
            session: parts.count > 3 ? parts[3] : "",
            orientation: parts.count > 4 ? parts[4] : ""
        )
    }

    static func imageOrderIndex(_ image: StashImage) -> Int {
        // Try to parse trailing _<digits> from filename (e.g. ..._0.jpg, ..._12.jpg)
        if let path = image.visual_files?.first?.path ?? image.paths?.image {
            let filename = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            if let match = filename.range(of: #"_\d+$"#, options: .regularExpression) {
                let s = filename[match].dropFirst()
                return Int(s) ?? 0
            }
        }
        return 0
    }
}

// MARK: - Post View

struct StashLinePostView: View {
    let post: StashLinePost
    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject var appearanceManager = AppearanceManager.shared
    var onPerformerTap: ((GalleryPerformer) -> Void)? = nil

    @State private var showHeartAnimation = false
    @State private var heartScale: CGFloat = 0
    @State private var heartOpacity: Double = 0
    @State private var oCounters: [String: Int]
    @State private var ratings: [String: Int]
    @State private var carouselIndex = 0
    @State private var isExpanded = false
    @State private var performerDetailTarget: GalleryPerformer?
    @State private var showPerformerDetail = false
    @AppStorage("stashline_crop_enabled") private var cropEnabled = true
    @AppStorage("stashline_group_by_orientation") private var groupByOrientation: Bool = true
    @AppStorage("stashline_load_full_images") private var loadFullImages: Bool = true
    @State private var isFullScreenPresented: Bool = false
    @State private var fullScreenImages: [StashImage]
    @State private var lastFullScreenImageIds: Set<String> = []
    
    private let actionIconSize: CGFloat = 16
    private let actionIconFrame: CGFloat = 22

    var image: StashImage { post.images[carouselIndex] }
    var localOCounter: Int { oCounters[image.id] ?? image.o_counter ?? 0 }
    var localRating: Int { ratings[image.id] ?? image.rating100 ?? 0 }
    
    private func actionIcon(_ systemName: String, tint: Color? = nil, scale: CGFloat = 1) -> some View {
        Image(systemName: systemName)
            .font(.system(size: actionIconSize, weight: .semibold))
            .frame(width: actionIconFrame, height: actionIconFrame, alignment: .center)
            .scaleEffect(scale)
            .foregroundColor(tint ?? appearanceManager.tintColor)
    }

    init(post: StashLinePost, viewModel: StashDBViewModel, onPerformerTap: ((GalleryPerformer) -> Void)? = nil) {
        self.post = post
        self.viewModel = viewModel
        self.onPerformerTap = onPerformerTap
        self._oCounters = State(initialValue: [:])
        self._ratings = State(initialValue: [:])
        self._fullScreenImages = State(initialValue: post.images)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            postHeader

            // Image + overlaid action bar
            imageArea
                .overlay(alignment: .bottom) { actionBar }
                .overlay(alignment: .topLeading) {
                    Button {
                        // Sync current post images into the viewer
                        fullScreenImages = post.images
                        lastFullScreenImageIds = Set(post.images.map(\.id))
                        isFullScreenPresented = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.black.opacity(DesignTokens.Opacity.badge))
                            .clipShape(Circle())
                    }
                    .padding(10)
                }

            HStack(alignment: .top) {
                if let title = image.title, !title.isEmpty {
                    Text(title)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                }
                Spacer()
                
                HStack(spacing: 16) {
                    if let performers = image.performers, !performers.isEmpty {
                        if performers.count == 1, let performer = performers.first {
                            Button {
                                performerDetailTarget = performer
                                showPerformerDetail = true
                            } label: {
                                actionIcon("person.fill", scale: 1.15)
                            }
                        } else {
                            Menu {
                                ForEach(performers) { performer in
                                    Button(performer.name) {
                                        performerDetailTarget = performer
                                        showPerformerDetail = true
                                    }
                                }
                            } label: {
                                actionIcon("person.fill", scale: 1.15)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .navigationDestination(isPresented: $showPerformerDetail) {
                if let performer = performerDetailTarget {
                    PerformerDetailView(performer: performer.toPerformer())
                } else {
                    EmptyView()
                }
            }

            if let tags = image.tags, !tags.isEmpty {
                tagLine(tags: tags)
            }

            Spacer().frame(height: 12)
            Divider()
        }
        #if !os(tvOS)
        .fullScreenCover(isPresented: $isFullScreenPresented) {
            NavigationStack {
                FullScreenImageView(
                    images: $fullScreenImages,
                    selectedImageId: image.id,
                    onLoadMore: nil
                )
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            isFullScreenPresented = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(appearanceManager.tintColor)
                        }
                    }
                }
            }
        }
        .onChange(of: fullScreenImages.count) { _, _ in
            // If the fullscreen viewer deletes images, it mutates `fullScreenImages`.
            // Propagate removals into the timeline source so the items disappear from the feed.
            let newIds = Set(fullScreenImages.map(\.id))
            let removed = lastFullScreenImageIds.subtracting(newIds)
            guard !removed.isEmpty else {
                lastFullScreenImageIds = newIds
                return
            }
            viewModel.allImages.removeAll { removed.contains($0.id) }
            lastFullScreenImageIds = newIds
        }
        #endif
    }

    // MARK: - Header

    private var postHeader: some View {
        let performers = image.performers ?? []
        return HStack(spacing: 10) {
            // Performers
            HStack(spacing: 0) {
                ForEach(Array(performers.enumerated()), id: \.element.id) { idx, performer in
                    if let onPerformerTap = onPerformerTap {
                        Button(action: { onPerformerTap(performer) }) {
                            performerAvatar(performer, offset: idx)
                        }
                        .buttonStyle(.plain)
                    } else {
                        NavigationLink(destination: StashLineView(performerFilter: performer).applyAppBackground()) {
                            performerAvatar(performer, offset: idx)
                        }
                        .buttonStyle(.plain)
                    }
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
                    let performer = performers[0]
                    if let onPerformerTap = onPerformerTap {
                        Button(action: { onPerformerTap(performer) }) {
                            Text(performer.name)
                                .font(.subheadline).fontWeight(.semibold)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    } else {
                        NavigationLink(destination: StashLineView(performerFilter: performer).applyAppBackground()) {
                            Text(performer.name)
                                .font(.subheadline).fontWeight(.semibold)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    HStack(spacing: 4) {
                        ForEach(Array(performers.enumerated()), id: \.element.id) { idx, performer in
                            if let onPerformerTap = onPerformerTap {
                                Button(action: { onPerformerTap(performer) }) {
                                    Text(performer.name)
                                        .font(.subheadline).fontWeight(.semibold)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)
                            } else {
                                NavigationLink(destination: StashLineView(performerFilter: performer).applyAppBackground()) {
                                    Text(performer.name)
                                        .font(.subheadline).fontWeight(.semibold)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                }
                                .buttonStyle(.plain)
                            }
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

    // When orientation grouping is disabled, a post can contain mixed orientations.
    // In that case the first image's ratio pins the container height so it never
    // jumps while swiping. With orientation grouping on, all images share the same
    // orientation anyway, so the behaviour is identical.
    private var containerAspectRatio: CGFloat {
        let anchor = groupByOrientation ? image : (post.images.first ?? image)
        return imageAspectRatio(for: anchor)
    }

    private var imageArea: some View {
        ZStack(alignment: .bottom) {
            if post.isSet {
                ZStack(alignment: .topTrailing) {
                    GeometryReader { geo in
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 0) {
                                ForEach(Array(post.images.enumerated()), id: \.offset) { index, img in
                                    singleImageView(img, ratio: imageAspectRatio(for: img))
                                        .frame(width: geo.size.width)
                                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                            content.opacity(phase.isIdentity ? 1 : 0.97)
                                        }
                                        .id(index)
                                }
                            }
                            .scrollTargetLayout()
                        }
                        .scrollTargetBehavior(.viewAligned)
                        .scrollPosition(id: Binding(
                            get: { carouselIndex },
                            set: { carouselIndex = $0 ?? 0 }
                        ))
                        .frame(width: geo.size.width)
                    }
                    .aspectRatio(containerAspectRatio, contentMode: .fit)
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
            let url = loadFullImages ? (img.imageURL ?? img.previewURL ?? img.thumbnailURL) : img.thumbnailURL
            if let url {
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
    
}
#endif
