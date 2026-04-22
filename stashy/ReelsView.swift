#if !os(tvOS)
//
//  ReelsView.swift
//  stashy
//
//  Created by Daniel Goletz on 13.01.26.
//

import SwiftUI
import AVKit
import AVFoundation

private extension Notification.Name {
    static let reelsPauseAllPlayers = Notification.Name("ReelsPauseAllPlayers")
}

private enum ReelsPlayerRegistry {
    private static let players = NSHashTable<AVPlayer>.weakObjects()
    private static let lock = NSLock()

    static func register(_ player: AVPlayer) {
        lock.lock()
        players.add(player)
        lock.unlock()
    }

    static func unregister(_ player: AVPlayer) {
        lock.lock()
        players.remove(player)
        lock.unlock()
    }

    static func pauseAll() {
        lock.lock()
        let all = players.allObjects
        lock.unlock()
        all.forEach { $0.pause() }
    }
}

/// Reels „Session“ state: **RAM only** — survives tab switches / navigation within one app launch, **not** an app restart.
/// One-time cleanup removes legacy `UserDefaults` keys from older builds so nothing persists across relaunch.
private enum ReelsSessionRAM {
    private static let lock = NSLock()
    private static var strings: [String: String] = [:]
    private static var ints: [String: Int] = [:]
    private static var didClearLegacyUserDefaults = false

    static func clearLegacyUserDefaultsIfNeeded() {
        lock.lock()
        let shouldClear = !didClearLegacyUserDefaults
        if shouldClear { didClearLegacyUserDefaults = true }
        lock.unlock()
        guard shouldClear else { return }
        let ud = UserDefaults.standard
        let keys = Array(ud.dictionaryRepresentation().keys)
        for key in keys {
            if key.hasPrefix("reels_last_visible_")
                || key.hasPrefix("reels_session_sort_")
                || key.hasPrefix("reels_session_filter_")
                || key.hasPrefix("reels_session_random_seed_") {
                ud.removeObject(forKey: key)
            }
        }
    }

    static func string(forKey key: String) -> String? {
        lock.lock()
        let v = strings[key]
        lock.unlock()
        return v
    }

    static func setString(_ value: String?, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        if let value, !value.isEmpty { strings[key] = value }
        else { strings.removeValue(forKey: key) }
    }

    static func int(forKey key: String) -> Int {
        lock.lock()
        let v = ints[key] ?? 0
        lock.unlock()
        return v
    }

    static func setInt(_ value: Int, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        if value > 0 { ints[key] = value }
        else { ints.removeValue(forKey: key) }
    }
}

struct ReelsView: View {
    @ObservedObject private var appearanceManager = AppearanceManager.shared
    @ObservedObject private var tabManager = TabManager.shared
    @StateObject private var viewModel = StashDBViewModel()
    @EnvironmentObject var coordinator: NavigationCoordinator
    @State private var selectedSortOption: StashDBViewModel.SceneSortOption = StashDBViewModel.SceneSortOption(rawValue: TabManager.shared.getReelsDefaultSort(for: .scenes) ?? "") ?? .random
    @State private var selectedFilter: StashDBViewModel.SavedFilter?
    @State private var selectedPerformer: ScenePerformer?
    @State private var selectedTags: [Tag] = []
    @State private var isMuted = !isHeadphonesConnected() // Shared mute state for Reels
    @State private var currentVisibleSceneId: String?
    @State private var showDeleteConfirmation = false
    @State private var sceneToDelete: Scene?
    @State private var reelsMode: ReelsMode = ReelsMode(from: TabManager.shared.enabledReelsModes.first ?? .scenes)
    @State private var selectedMarkerSortOption: StashDBViewModel.SceneMarkerSortOption = StashDBViewModel.SceneMarkerSortOption(rawValue: TabManager.shared.getReelsDefaultSort(for: .markers) ?? "") ?? .random
    @State private var selectedClipSortOption: StashDBViewModel.ImageSortOption = StashDBViewModel.ImageSortOption(rawValue: TabManager.shared.getReelsDefaultSort(for: .clips) ?? "") ?? .random
    @State private var selectedClipFilter: StashDBViewModel.SavedFilter?
    @State private var selectedPreviewFilter: StashDBViewModel.SavedFilter?
    @State private var isMenuOpen = false
    @State private var isMediaZoomed = false
    @State private var isRotating = false
    @State private var isUIVisible = true
    @State private var isUserScrollingReels = false
    @State private var lastMainListPosition: String?
    @State private var currentItemIsPlaying = true
    @State private var currentItemShowRatingOverlay = false
    @State private var showStashSyncSheet = false
    @State private var scrubberState = ScrubberState()
    @State private var isInitialized = false
    @State private var playTrigger = 0  // Incremented when first item should autoplay
    @State private var pendingRestoreId: String? = nil

    // MARK: - Session-persisted sort/filter (per server + mode)
    private func reelsSessionSortKey(for mode: ReelsMode) -> String {
        let serverID = ServerConfigManager.shared.activeConfig?.id.uuidString ?? "default"
        return "reels_session_sort_\(serverID)_\(mode.rawValue)"
    }

    private func reelsSessionFilterKey(for mode: ReelsMode) -> String {
        let serverID = ServerConfigManager.shared.activeConfig?.id.uuidString ?? "default"
        return "reels_session_filter_\(serverID)_\(mode.rawValue)"
    }

    private func sessionSortRaw(for mode: ReelsMode) -> String? {
        ReelsSessionRAM.string(forKey: reelsSessionSortKey(for: mode))
    }

    private func sessionFilterId(for mode: ReelsMode) -> String? {
        ReelsSessionRAM.string(forKey: reelsSessionFilterKey(for: mode))
    }

    private func saveSessionState(for mode: ReelsMode) {
        // Sort
        let sortRaw: String? = {
            switch mode {
            case .scenes: return selectedSortOption.rawValue
            case .markers: return selectedMarkerSortOption.rawValue
            case .clips: return selectedClipSortOption.rawValue
            case .previews: return selectedSortOption.rawValue
            case .pics: return nil
            }
        }()
        if let raw = sortRaw {
            ReelsSessionRAM.setString(raw, forKey: reelsSessionSortKey(for: mode))
        }

        // Filter
        let filterId: String? = {
            switch mode {
            case .scenes, .markers:
                return selectedFilter?.id
            case .clips:
                return selectedClipFilter?.id
            case .previews:
                return selectedPreviewFilter?.id
            case .pics:
                return nil
            }
        }()
        if let id = filterId, !id.isEmpty {
            ReelsSessionRAM.setString(id, forKey: reelsSessionFilterKey(for: mode))
        } else {
            ReelsSessionRAM.setString(nil, forKey: reelsSessionFilterKey(for: mode))
        }
    }

    /// Maps a ReelsMode to the VM's per-kind random-seed bucket.
    /// Pics has no random sort; returns nil.
    private func seedKind(for mode: ReelsMode) -> StashDBViewModel.RandomSeedKind? {
        switch mode {
        case .scenes: return .scenes
        case .markers: return .markers
        case .clips: return .images   // clips are served via findImages
        case .previews: return .previews
        case .pics: return nil
        }
    }

    private func reelsSessionRandomSeedKey(for mode: ReelsMode) -> String {
        let serverID = ServerConfigManager.shared.activeConfig?.id.uuidString ?? "default"
        return "reels_session_random_seed_\(serverID)_\(mode.rawValue)"
    }

    /// Restore per-mode session seeds so Scenes / Previews / Markers / Clips keep
    /// independent but stable "random" orders across navigation.
    private func restoreSessionRandomSeedIfAvailable() {
        for mode in [ReelsMode.scenes, .markers, .clips, .previews] {
            guard let kind = seedKind(for: mode) else { continue }
            let seed = ReelsSessionRAM.int(forKey: reelsSessionRandomSeedKey(for: mode))
            if seed > 0 {
                viewModel.setRandomSeed(seed, for: kind)
            }
        }
    }

    private func persistSessionRandomSeed(for mode: ReelsMode) {
        guard let kind = seedKind(for: mode) else { return }
        ReelsSessionRAM.setInt(viewModel.getRandomSeed(for: kind), forKey: reelsSessionRandomSeedKey(for: mode))
    }

    private func reelsPositionKey(for mode: ReelsMode) -> String {
        let serverID = ServerConfigManager.shared.activeConfig?.id.uuidString ?? "default"
        return "reels_last_visible_\(serverID)_\(mode.rawValue)"
    }

    private func expectedPrefix(for mode: ReelsMode) -> String? {
        switch mode {
        case .scenes: return "scene"
        case .markers: return "marker"
        case .clips: return "clip"
        case .previews: return "preview"
        case .pics: return nil
        }
    }

    private func savedPosition(for mode: ReelsMode) -> String? {
        ReelsSessionRAM.string(forKey: reelsPositionKey(for: mode))
    }

    private func savePosition(_ id: String, for mode: ReelsMode) {
        ReelsSessionRAM.setString(id, forKey: reelsPositionKey(for: mode))
    }

    private func saveCurrentPositionIfPossible(for mode: ReelsMode) {
        guard let prefix = expectedPrefix(for: mode) else { return }
        guard let id = currentVisibleSceneId, id.hasPrefix("\(prefix)-") else { return }
        savePosition(id, for: mode)
    }

    private func restorePositionIfAvailable(for mode: ReelsMode, forceIfPrefixMismatch: Bool) {
        let currentPrefix = currentVisibleSceneId?.split(separator: "-").first.map(String.init)
        let expected = expectedPrefix(for: mode)

        if forceIfPrefixMismatch {
            if let expected, currentPrefix == expected { return }
        } else {
            guard currentVisibleSceneId == nil else { return }
        }

        // Keep restore target OUTSIDE of `currentVisibleSceneId`. Setting an ID
        // into `.scrollPosition(id:)` that isn't in the list yet causes SwiftUI
        // to visually stall (black view) until it appears.
        if let saved = savedPosition(for: mode), !saved.isEmpty {
            pendingRestoreId = saved
        }
    }

    private func beginPagedRestoreIfNeeded() {
        guard let targetId = pendingRestoreId ?? currentVisibleSceneId else {
            pendingRestoreId = nil
            return
        }
        // If it's already present, we're done.
        if currentReelItems.contains(where: { $0.id == targetId }) {
            pendingRestoreId = nil
            return
        }
        pendingRestoreId = targetId
        continuePagedRestoreIfNeeded()
    }

    private func continuePagedRestoreIfNeeded() {
        guard let targetId = pendingRestoreId else { return }

        // Stop when found.
        if currentReelItems.contains(where: { $0.id == targetId }) {
            pendingRestoreId = nil
            return
        }

        // Load more until we either find it or run out of pages.
        switch reelsMode {
        case .scenes:
            guard viewModel.hasMoreScenes, !viewModel.isLoadingMoreScenes else { return }
            viewModel.loadMoreScenes()
        case .markers:
            guard viewModel.hasMoreMarkers, !viewModel.isLoadingMarkers else { return }
            viewModel.loadMoreMarkers()
        case .clips:
            guard viewModel.hasMoreClips, !viewModel.isLoadingClips else { return }
            viewModel.loadMoreClips()
        case .previews:
            guard viewModel.hasMorePreviews, !viewModel.isLoadingMorePreviews else { return }
            viewModel.loadMorePreviews()
        case .pics:
            pendingRestoreId = nil
        }
    }

    // Extracted binding to help the Swift compiler with type-checking
    // Native scroll binding
    private var scrollPositionBinding: Binding<String?> {
        Binding<String?>(
            get: { currentVisibleSceneId },
            set: { newValue in
                currentVisibleSceneId = newValue
            }
        )
    }

    enum ReelsMode: String, CaseIterable {
        case scenes = "Scenes"
        case markers = "Markers"
        case clips = "Clips"
        case previews = "Previews"
        case pics = "Pics"
        
        var icon: String {
            switch self {
            case .scenes: return "film"
            case .markers: return "bookmark.fill"
            case .clips: return "photo.on.rectangle.angled"
            case .previews: return "play.rectangle.on.rectangle.fill"
            case .pics: return "camera.fill"
            }
        }
        
        var toModeType: ReelsModeType {
            switch self {
            case .scenes: return .scenes
            case .markers: return .markers
            case .clips: return .clips
            case .previews: return .previews
            case .pics: return .pics
            }
        }
        
        init(from type: ReelsModeType) {
            switch type {
            case .scenes: self = .scenes
            case .markers: self = .markers
            case .clips: self = .clips
            case .previews: self = .previews
            case .pics: self = .pics
            }
        }
    }

    enum ReelItemData: Identifiable {
        case scene(Scene)
        case marker(SceneMarker)
        case clip(StashImage)
        case preview(Scene)
        
        var id: String {
            switch self {
            case .scene(let s): return "scene-\(s.id)"
            case .marker(let m): return "marker-\(m.id)"
            case .clip(let c): return "clip-\(c.id)"
            case .preview(let s): return "preview-\(s.id)"
            }
        }
        
        var title: String? {
            func nonEmpty(_ s: String?) -> String? {
                guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
                return t
            }
            func fileNameFromPath(_ path: String?) -> String? {
                guard let p = nonEmpty(path) else { return nil }
                let clean = p.components(separatedBy: "?").first ?? p
                return URL(fileURLWithPath: clean).lastPathComponent
            }

            switch self {
            case .scene(let s):
                if let t = nonEmpty(s.title) { return t }
                // Fallback: use filename if title is missing
                if let name = fileNameFromPath(s.files?.first?.path) { return name }
                if let name = fileNameFromPath(s.paths?.stream) { return name }
                return nil
            case .marker(let m):
                if let t = nonEmpty(m.scene?.title) { return t }
                if let name = fileNameFromPath(m.scene?.files?.first?.path) { return name }
                if let name = fileNameFromPath(m.scene?.paths?.stream) { return name }
                return nil
            case .clip(let c):
                if let t = nonEmpty(c.title) { return t }
                // Fallback: show filename when no title is present
                if let name = fileNameFromPath(c.visual_files?.first?.path) { return name }
                if let name = fileNameFromPath(c.paths?.image) { return name }
                return nil
            case .preview(let s):
                if let t = nonEmpty(s.title) { return t }
                if let name = fileNameFromPath(s.files?.first?.path) { return name }
                if let name = fileNameFromPath(s.paths?.stream) { return name }
                return nil
            }
        }
        
        var performers: [ScenePerformer] {
            switch self {
            case .scene(let s): return s.performers
            case .marker(let m): return m.scene?.performers ?? []
            case .clip(let c): return c.performers?.map { ScenePerformer(id: $0.id, name: $0.name, birthdate: nil, sceneCount: nil, galleryCount: nil, oCounter: nil, updatedAt: nil) } ?? []
            case .preview(let s): return s.performers
            }
        }
        
        var tags: [Tag] {
            switch self {
            case .scene(let s): return s.tags ?? []
            case .marker(let m):
                var allTags = m.tags ?? []
                if let primary = m.primaryTag {
                    allTags.insert(primary, at: 0)
                }
                return allTags
            case .clip(let c): return c.tags ?? []
            case .preview(let s): return s.tags ?? []
            }
        }
        
        var thumbnailURL: URL? {
            switch self {
            case .scene(let s): return s.thumbnailURL
            case .marker(let m): return m.thumbnailURL
            case .clip(let c): return c.thumbnailURL
            case .preview(let s): return s.thumbnailURL
            }
        }
        
        var videoURL: URL? {
            let quality = ServerConfigManager.shared.activeConfig?.reelsQuality ?? .sd
            switch self {
            case .scene(let s):
                // 0. Check local first
                if let local = s.videoURL, !local.absoluteString.hasPrefix("http") {
                    return local
                }
                return s.bestStream(for: quality) ?? s.videoURL
                
            case .marker(let m):
                let potentialURL: URL?
                if let streamPath = m.stream, let url = URL(string: streamPath) {
                    potentialURL = url
                } else if let config = ServerConfigManager.shared.loadConfig() {
                    potentialURL = URL(string: "\(config.baseURL)/scenemarker/\(m.id)/stream")
                } else {
                    potentialURL = nil
                }
                
                guard let config = ServerConfigManager.shared.activeConfig, let key = config.secureApiKey, !key.isEmpty, let url = potentialURL else { return potentialURL }
                var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
                var items = comps?.queryItems ?? []
                if !items.contains(where: { $0.name == "apikey" }) {
                    items.append(URLQueryItem(name: "apikey", value: key.trimmingCharacters(in: .whitespacesAndNewlines)))
                    comps?.queryItems = items
                }
                return comps?.url ?? url
                
            case .clip(let c):
                // For clips (images that are videos or animations), the imagePath IS the video path
                return c.imageURL
            case .preview(let s):
                return s.previewURL
            }
        }
        
        var startTime: Double {
            switch self {
            case .scene: return 0
            case .marker: return 0
            case .clip: return 0
            case .preview: return 0
            }
        }

        var endTime: Double? {
            switch self {
            case .marker: return nil
            case .preview: return nil
            default: return nil
            }
        }

        var duration: Double? {
            switch self {
            case .scene(let s): return s.duration
            case .marker(let m): 
                if let end = m.endSeconds { return end - m.seconds }
                return nil
            case .clip(let c): return c.visual_files?.first?.duration
            case .preview(let s): return s.duration
            }
        }
        
        var isPortrait: Bool {
            switch self {
            case .scene(let s): return s.isPortrait
            case .marker(let m):
                if let width = m.scene?.files?.first?.width, let height = m.scene?.files?.first?.height {
                    return height > width
                }
                return false
            case .clip(let c):
                if let file = c.visual_files?.first {
                    return (file.height ?? 0) > (file.width ?? 0)
                }
                return false
            case .preview(let s): return s.isPortrait
            }
        }
        
        var rating100: Int? {
            switch self {
            case .scene(let s): return s.rating100
            case .marker(let m): return m.scene?.rating100
            case .clip(let c): return c.rating100
            case .preview(let s): return s.rating100
            }
        }
        
        var oCounter: Int? {
            switch self {
            case .scene(let s): return s.oCounter
            case .marker(let m): return m.scene?.oCounter
            case .clip(let c): return c.o_counter
            case .preview(let s): return s.oCounter
            }
        }
        
        var playCount: Int? {
            switch self {
            case .scene(let s): return s.playCount
            case .marker(let m): return m.playCount
            case .clip: return nil  // Images don't track play count
            case .preview(let s): return s.playCount
            }
        }
        
        var dateString: String? {
            switch self {
            case .scene(let s): return s.date
            case .marker(let m): return m.scene?.date
            case .clip(let c): return c.date
            case .preview(let s): return s.date
            }
        }
        
        var sceneID: String? {
            switch self {
            case .scene(let s): return s.id
            case .marker(let m): return m.scene?.id
            case .clip: return nil  // Clips are images, not scenes
            case .preview(let s): return s.id
            }
        }
        
        var isAnimated: Bool {
            switch self {
            case .clip(let c):
                let ext = c.fileExtension?.uppercased()
                return ext == "GIF" || ext == "WEBP"
            case .scene: return false
            case .marker: return false
            case .preview: return false
            }
        }

        var underlyingScene: Scene? {
            switch self {
            case .scene(let s): return s
            case .marker(let m): return m.scene?.toScene()
            case .clip: return nil
            case .preview(let s): return s
            }
        }

    }

    private var currentReelItems: [ReelItemData] {
        switch reelsMode {
        case .scenes: return viewModel.scenes.map { ReelItemData.scene($0) }
        case .markers: return viewModel.sceneMarkers.filter { $0.stream != nil && !$0.stream!.isEmpty }.map { ReelItemData.marker($0) }
        case .clips: return viewModel.clips.map { ReelItemData.clip($0) }
        case .previews: return viewModel.previews.map { ReelItemData.preview($0) }
        case .pics: return []
        }
    }

    

    private func applySettings(sortBy: StashDBViewModel.SceneSortOption? = nil, markerSortBy: StashDBViewModel.SceneMarkerSortOption? = nil, clipSortBy: StashDBViewModel.ImageSortOption? = nil, previewSortBy: StashDBViewModel.SceneSortOption? = nil, filter: StashDBViewModel.SavedFilter?, clipFilter: StashDBViewModel.SavedFilter? = nil, previewFilter: StashDBViewModel.SavedFilter? = nil, performer: ScenePerformer? = nil, tags: [Tag] = [], mode: ReelsMode? = nil, clearClipFilter: Bool = false, clearPreviewFilter: Bool = false, rerollRandom: Bool = false) {
        let currentMode = mode ?? reelsMode
        if let providedMode = mode { reelsMode = providedMode }

        // Position Persistence Logic:
        // If we change the mode, the saved position is invalid (different IDs)
        if mode != nil && mode != reelsMode {
            lastMainListPosition = nil
        }

        // If we are clearing filters (returning to main list) and have a saved position, restore it.
        let isClearingFilters = performer == nil && tags.isEmpty
        let restoredPosition: String?
        if isClearingFilters, let savedPos = lastMainListPosition {
            print("🔄 ReelsView: Restoring scroll position to \(savedPos)")
            currentVisibleSceneId = savedPos
            lastMainListPosition = nil
            restoredPosition = savedPos
        } else {
            restoredPosition = nil
            if !isClearingFilters && lastMainListPosition == nil {
                // If we are ADDING a filter for the first time (not already filtering), save.
                // Check if we already have criterion set (avoid overwriting on second tag)
                if selectedPerformer == nil && selectedTags.isEmpty {
                    print("💾 ReelsView: Saving position \(currentVisibleSceneId ?? "none") before filtering")
                    lastMainListPosition = currentVisibleSceneId
                }
                // Don't nil-out currentVisibleSceneId here — let autoSelectFirstItem
                // update it when new data arrives. Setting nil causes broken UI state
                // (strikethrough mute/play, no stars) during the loading gap.
            }
        }

        // Update local state and handle random re-roll (only when explicitly requested)
        // Don't override a just-restored position with nil
        if let sortBy = sortBy {
            if rerollRandom && sortBy == .random && selectedSortOption == .random && reelsMode == .scenes {
                viewModel.refreshRandomSeed(for: .scenes)
                persistSessionRandomSeed(for: .scenes)
            }
            selectedSortOption = sortBy
            if restoredPosition == nil { currentVisibleSceneId = nil }
        }

        if let markerSortBy = markerSortBy {
            if rerollRandom && markerSortBy == .random && selectedMarkerSortOption == .random && reelsMode == .markers {
                viewModel.refreshRandomSeed(for: .markers)
                persistSessionRandomSeed(for: .markers)
            }
            selectedMarkerSortOption = markerSortBy
            if restoredPosition == nil { currentVisibleSceneId = nil }
        }

        if let clipSortBy = clipSortBy {
            if rerollRandom && clipSortBy == .random && selectedClipSortOption == .random && reelsMode == .clips {
                viewModel.refreshRandomSeed(for: .images)
                persistSessionRandomSeed(for: .clips)
            }
            selectedClipSortOption = clipSortBy
            if restoredPosition == nil { currentVisibleSceneId = nil }
        }

        if let previewSortBy = previewSortBy {
            if rerollRandom && previewSortBy == .random && selectedSortOption == .random && reelsMode == .previews {
                viewModel.refreshRandomSeed(for: .previews)
                persistSessionRandomSeed(for: .previews)
            }
            // Previews use standard selectedSortOption since they are scenes
            selectedSortOption = previewSortBy
            if restoredPosition == nil { currentVisibleSceneId = nil }
        }

        // For clip filter: use explicitly passed value; fall back to existing selectedClipFilter
        // unless clearClipFilter is true (used when explicitly removing the clip filter).
        let resolvedClipFilter: StashDBViewModel.SavedFilter?
        if clearClipFilter {
            resolvedClipFilter = nil
        } else if clipFilter != nil {
            resolvedClipFilter = clipFilter
        } else {
            resolvedClipFilter = selectedClipFilter
        }
        selectedClipFilter = resolvedClipFilter
        
        let resolvedPreviewFilter: StashDBViewModel.SavedFilter?
        if clearPreviewFilter {
            resolvedPreviewFilter = nil
        } else if previewFilter != nil {
            resolvedPreviewFilter = previewFilter
        } else {
            resolvedPreviewFilter = selectedPreviewFilter
        }
        selectedPreviewFilter = resolvedPreviewFilter
        
        selectedFilter = filter
        selectedPerformer = performer
        selectedTags = tags

        // Merge performer and tags into filter if needed
        // IMPORTANT: Use the arguments (filter/clipFilter) instead of @State (selectedFilter/selectedClipFilter)
        // because @State might not have propagated yet.
        let mergedFilter = viewModel.mergeFilterWithCriteria(filter: filter, performer: performer, tags: tags, mode: .scenes)
        let mergedClipFilter = viewModel.mergeFilterWithCriteria(filter: resolvedClipFilter, performer: performer, tags: tags, mode: .images)
        let mergedPreviewFilter = viewModel.mergeFilterWithCriteria(filter: resolvedPreviewFilter, performer: performer, tags: tags, mode: .scenes)

        switch currentMode {
        case .scenes:
            viewModel.fetchScenes(sortBy: selectedSortOption, filter: mergedFilter)
        case .markers:
            viewModel.fetchSceneMarkers(sortBy: selectedMarkerSortOption, filter: mergedFilter)
        case .clips:
            print("🎬 ReelsView: Fetching Clips with performer: \(performer?.name ?? "none")")
            viewModel.fetchClips(sortBy: selectedClipSortOption, filter: mergedClipFilter, isInitialLoad: true)
        case .previews:
            viewModel.fetchPreviews(sortBy: selectedSortOption, isInitialLoad: true, filter: mergedPreviewFilter)
        case .pics:
            break
        }

        // Persist sort/filter for this session (per mode)
        saveSessionState(for: currentMode)
    }
    
    private func autoSelectFirstItem() {
        guard !currentReelItems.isEmpty else { return }
        let currentPrefix = currentVisibleSceneId?.split(separator: "-").first.map(String.init)
        guard let expectedPrefix = expectedPrefix(for: reelsMode) else { return }

        let currentIdExists: Bool = {
            guard let id = currentVisibleSceneId else { return false }
            return currentReelItems.contains(where: { $0.id == id })
        }()

        if !currentIdExists || currentPrefix != expectedPrefix {
            // If the restore target is already loaded in the current page, use it.
            // Otherwise show first item immediately — snapToPendingRestoreIfLoaded
            // will scroll later when the target arrives via pagination.
            if let target = pendingRestoreId,
               currentReelItems.contains(where: { $0.id == target }) {
                currentVisibleSceneId = target
                pendingRestoreId = nil
                playTrigger += 1
                return
            }
            if let saved = savedPosition(for: reelsMode),
               currentReelItems.contains(where: { $0.id == saved }) {
                currentVisibleSceneId = saved
                pendingRestoreId = nil
                playTrigger += 1
                return
            }

            var newId: String?
            switch reelsMode {
            case .scenes:
                if let firstId = viewModel.scenes.first?.id { newId = "scene-\(firstId)" }
            case .markers:
                if let firstId = viewModel.sceneMarkers.first?.id { newId = "marker-\(firstId)" }
            case .clips:
                if let firstId = viewModel.clips.first?.id { newId = "clip-\(firstId)" }
            case .previews:
                if let firstId = viewModel.previews.first?.id { newId = "preview-\(firstId)" }
            case .pics:
                break
            }
            if let id = newId {
                currentVisibleSceneId = id
                // Signal ReelItemView to start playback — onChange(of: isActive)
                // may not fire reliably when the view was just created.
                playTrigger += 1
            }
        }
    }



    private func handleRatingChange(item: ReelItemData, newRating: Int?) {
        // Preview items live in viewModel.previews, not viewModel.scenes
        if case .preview(let scene) = item {
            let sceneId = scene.id
            if let index = viewModel.previews.firstIndex(where: { $0.id == sceneId }) {
                let originalRating = viewModel.previews[index].rating100
                viewModel.previews[index] = viewModel.previews[index].withRating(newRating)
                if let r = newRating {
                    viewModel.updateSceneRating(sceneId: sceneId, rating100: r) { success in
                        if !success {
                            DispatchQueue.main.async {
                                viewModel.previews[index] = viewModel.previews[index].withRating(originalRating)
                                ToastManager.shared.show("Failed to save rating", icon: "exclamationmark.triangle", style: .error)
                            }
                        }
                    }
                }
            }
            return
        }

        var targetSceneId: String?
        if case .scene(let scene) = item { targetSceneId = scene.id }
        else if case .marker(let marker) = item { targetSceneId = marker.scene?.id }

        if let sceneId = targetSceneId {
            // 1. Optimistic Update for Scene List
            if let sceneIndex = viewModel.scenes.firstIndex(where: { $0.id == sceneId }) {
                let originalRating = viewModel.scenes[sceneIndex].rating100
                viewModel.scenes[sceneIndex] = viewModel.scenes[sceneIndex].withRating(newRating)

                if let r = newRating {
                    viewModel.updateSceneRating(sceneId: sceneId, rating100: r) { success in
                        if !success {
                            DispatchQueue.main.async {
                                viewModel.scenes[sceneIndex] = viewModel.scenes[sceneIndex].withRating(originalRating)
                                ToastManager.shared.show("Failed to save rating", icon: "exclamationmark.triangle", style: .error)
                            }
                        }
                    }
                }
            }

            // 2. Optimistic Update for Scene Markers
            let markerIndices = viewModel.sceneMarkers.enumerated().compactMap { index, marker in
                marker.scene?.id == sceneId ? index : nil
            }

            for index in markerIndices {
                if let markerScene = viewModel.sceneMarkers[index].scene {
                    viewModel.sceneMarkers[index] = viewModel.sceneMarkers[index].withScene(markerScene.withRating(newRating))
                }
            }

            // If not in scenes list
            if !viewModel.scenes.contains(where: { $0.id == sceneId }) {
                if let r = newRating {
                    viewModel.updateSceneRating(sceneId: sceneId, rating100: r) { _ in }
                }
            }
        } else if case .clip(let image) = item {
            // 3. Optimistic Update for Clips List
            if let clipIndex = viewModel.clips.firstIndex(where: { $0.id == image.id }) {
                let originalRating = viewModel.clips[clipIndex].rating100
                viewModel.clips[clipIndex] = viewModel.clips[clipIndex].withRating(newRating)
                
                if let r = newRating {
                    viewModel.updateImageRating(imageId: image.id, rating100: r) { success in
                        if !success {
                            DispatchQueue.main.async {
                                viewModel.clips[clipIndex] = viewModel.clips[clipIndex].withRating(originalRating)
                                ToastManager.shared.show("Failed to save rating", icon: "exclamationmark.triangle", style: .error)
                            }
                        }
                    }
                }
            }
        }
    }

    private func handleOCounterChange(item: ReelItemData, newCount: Int) {
        // Preview items live in viewModel.previews, not viewModel.scenes
        if case .preview(let scene) = item {
            let sceneId = scene.id
            if let index = viewModel.previews.firstIndex(where: { $0.id == sceneId }) {
                let originalCount = viewModel.previews[index].oCounter ?? 0
                viewModel.previews[index] = viewModel.previews[index].withOCounter(newCount)
                viewModel.incrementOCounter(sceneId: sceneId) { returnedCount in
                    if let count = returnedCount {
                        DispatchQueue.main.async {
                            viewModel.previews[index] = viewModel.previews[index].withOCounter(count)
                        }
                    } else {
                        DispatchQueue.main.async {
                            viewModel.previews[index] = viewModel.previews[index].withOCounter(originalCount)
                            ToastManager.shared.show("Counter update failed", icon: "exclamationmark.triangle", style: .error)
                        }
                    }
                }
            }
            return
        }

        var targetSceneId: String?
        if case .scene(let scene) = item { targetSceneId = scene.id }
        else if case .marker(let marker) = item { targetSceneId = marker.scene?.id }

        if let sceneId = targetSceneId {
            // 1. Scene List Update
            if let index = viewModel.scenes.firstIndex(where: { $0.id == sceneId }) {
                let originalCount = viewModel.scenes[index].oCounter ?? 0
                viewModel.scenes[index] = viewModel.scenes[index].withOCounter(newCount)
                
                viewModel.incrementOCounter(sceneId: sceneId) { returnedCount in
                    if let count = returnedCount {
                        DispatchQueue.main.async {
                            viewModel.scenes[index] = viewModel.scenes[index].withOCounter(count)
                        }
                    } else {
                        DispatchQueue.main.async {
                            viewModel.scenes[index] = viewModel.scenes[index].withOCounter(originalCount)
                            ToastManager.shared.show("Counter update failed", icon: "exclamationmark.triangle", style: .error)
                        }
                    }
                }
            }
            
            // 2. Scene Markers Update
            let markerIndices = viewModel.sceneMarkers.enumerated().compactMap { index, marker in
                marker.scene?.id == sceneId ? index : nil
            }
            
            for index in markerIndices {
                if let markerScene = viewModel.sceneMarkers[index].scene {
                    let originalCount = markerScene.oCounter ?? 0
                    viewModel.sceneMarkers[index] = viewModel.sceneMarkers[index].withScene(markerScene.withOCounter(newCount))
                    
                    // If NOT already handled by scene list update
                    if !viewModel.scenes.contains(where: { $0.id == sceneId }) {
                         viewModel.incrementOCounter(sceneId: sceneId) { returnedCount in
                            if let count = returnedCount {
                                DispatchQueue.main.async {
                                    viewModel.sceneMarkers[index] = viewModel.sceneMarkers[index].withScene(markerScene.withOCounter(count))
                                }
                            } else {
                                DispatchQueue.main.async {
                                    viewModel.sceneMarkers[index] = viewModel.sceneMarkers[index].withScene(markerScene.withOCounter(originalCount))
                                }
                            }
                         }
                    }
                }
            }
            
            // 3. Fallback (if not in any list)
            if !viewModel.scenes.contains(where: { $0.id == sceneId }) && markerIndices.isEmpty {
                viewModel.incrementOCounter(sceneId: sceneId) { _ in }
            }
            
        } else if case .clip(let image) = item {
            // 4. Clip Update
            if let index = viewModel.clips.firstIndex(where: { $0.id == image.id }) {
                let originalCount = viewModel.clips[index].o_counter ?? 0
                
                // Optimistic Update
                viewModel.clips[index] = viewModel.clips[index].withOCounter(newCount)
                
                viewModel.incrementImageOCounter(imageId: image.id) { returnedCount in
                    if let count = returnedCount {
                        DispatchQueue.main.async {
                            viewModel.clips[index] = viewModel.clips[index].withOCounter(count)
                        }
                    } else {
                        DispatchQueue.main.async {
                            if let revertIndex = viewModel.clips.firstIndex(where: { $0.id == image.id }) {
                                viewModel.clips[revertIndex] = viewModel.clips[revertIndex].withOCounter(originalCount)
                            }
                            ToastManager.shared.show("Counter update failed", icon: "exclamationmark.triangle", style: .error)
                        }
                    }
                }
            }
        }
    }

    private func handlePlayCountChange(item: ReelItemData, newCount: Int) {
        // As requested: bypass view counter for Previews
        if case .preview = item { return }
        
        if case .scene(let scene) = item {
            let sceneId = scene.id
            // 1. Scene List Update
            if let index = viewModel.scenes.firstIndex(where: { $0.id == sceneId }) {
                let originalCount = viewModel.scenes[index].playCount ?? 0
                viewModel.scenes[index] = viewModel.scenes[index].withPlayCount(newCount)
                
                viewModel.addScenePlay(sceneId: sceneId) { returnedCount in
                    if let count = returnedCount {
                        DispatchQueue.main.async {
                            viewModel.scenes[index] = viewModel.scenes[index].withPlayCount(count)
                        }
                    } else {
                        DispatchQueue.main.async {
                            viewModel.scenes[index] = viewModel.scenes[index].withPlayCount(originalCount)
                            ToastManager.shared.show("View count update failed", icon: "exclamationmark.triangle", style: .error)
                        }
                    }
                }
            }
            
            // 2. Scene Markers Update (associated scene count)
            let markerIndices = viewModel.sceneMarkers.enumerated().compactMap { index, marker in
                marker.scene?.id == sceneId ? index : nil
            }
            
            for index in markerIndices {
                if let markerScene = viewModel.sceneMarkers[index].scene {
                    let originalCount = markerScene.playCount ?? 0
                    viewModel.sceneMarkers[index] = viewModel.sceneMarkers[index].withScene(markerScene.withPlayCount(newCount))
                    
                    // If NOT already handled by scene list update
                    if !viewModel.scenes.contains(where: { $0.id == sceneId }) {
                         viewModel.addScenePlay(sceneId: sceneId) { returnedCount in
                            if let count = returnedCount {
                                DispatchQueue.main.async {
                                    viewModel.sceneMarkers[index] = viewModel.sceneMarkers[index].withScene(markerScene.withPlayCount(count))
                                }
                            } else {
                                DispatchQueue.main.async {
                                    viewModel.sceneMarkers[index] = viewModel.sceneMarkers[index].withScene(markerScene.withPlayCount(originalCount))
                                }
                            }
                         }
                    }
                }
            }
            
            // 3. Fallback (if not in any list)
            if !viewModel.scenes.contains(where: { $0.id == sceneId }) && markerIndices.isEmpty {
                viewModel.addScenePlay(sceneId: sceneId) { _ in }
            }
        } else if case .marker(let marker) = item {
            // MARKER Play Count Update (The fix)
            let markerId = marker.id
            
            // 1. Optimistic Update for Scene Markers List
            if let index = viewModel.sceneMarkers.firstIndex(where: { $0.id == markerId }) {
                let originalCount = viewModel.sceneMarkers[index].playCount ?? 0
                viewModel.sceneMarkers[index] = viewModel.sceneMarkers[index].withPlayCount(newCount)
                
                viewModel.addSceneMarkerPlay(markerId: markerId) { returnedCount in
                    if let count = returnedCount {
                        DispatchQueue.main.async {
                            viewModel.sceneMarkers[index] = viewModel.sceneMarkers[index].withPlayCount(count)
                        }
                    } else {
                        DispatchQueue.main.async {
                            viewModel.sceneMarkers[index] = viewModel.sceneMarkers[index].withPlayCount(originalCount)
                            ToastManager.shared.show("Marker view count update failed", icon: "exclamationmark.triangle", style: .error)
                        }
                    }
                }
            } else {
                // 2. Fallback (if not in current list)
            viewModel.addSceneMarkerPlay(markerId: markerId) { _ in }
            }
        }
    }

    private var isListEmpty: Bool {
        switch reelsMode {
        case .scenes: return viewModel.scenes.isEmpty
        case .markers: return viewModel.sceneMarkers.isEmpty
        case .clips: return viewModel.clips.isEmpty
        case .previews: return viewModel.previews.isEmpty
        case .pics: return false
        }
    }

    var body: some View {
        premiumContent
    }


    @ViewBuilder
    private var premiumContent: some View {
        premiumContentBase
            .onAppear { handleOnAppear() }
            .onChange(of: isMenuOpen) { _, newValue in
                guard newValue else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    isMenuOpen = false
                }
            }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
                
                // Stop all audio & interactive sync
                HandyManager.shared.stop()
                ButtplugManager.shared.stopAllDevices()
                LoveSpouseManager.shared.stop()
                
                // Deactivate audio session to release focus immediately
                do {
                    try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                    print("🎬 Reels: Audio session deactivated")
                } catch {
                    print("🎬 Reels: Audio deactivation error: \(error)")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DefaultFilterChanged"))) { notification in
                handleDefaultFilterChanged(notification)
            }
            .onChange(of: viewModel.savedFilters) { _, newValue in
                handleSavedFiltersChanged(newValue)
            }
    }

    @ViewBuilder
    private var premiumContentBase: some View {
        premiumContentLayout
            .toolbar(reelsMode == .pics || isUIVisible ? .visible : .hidden, for: .tabBar)
            .sheet(isPresented: $showStashSyncSheet) {
                #if !os(tvOS)
                StashSyncSheet()
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                #endif
            }
            .onChange(of: reelsMode) { oldValue, newValue in handleModeChange(from: oldValue, to: newValue) }
            .onChange(of: currentVisibleSceneId) { _, _ in
                isMenuOpen = false
                currentItemIsPlaying = true
                currentItemShowRatingOverlay = false
                scrubberState.time = 0.0
                scrubberState.duration = 1.0
                scrubberState.seeking = false
                scrubberState.seekTarget = nil
                saveCurrentPositionIfPossible(for: reelsMode)
            }
            .onChange(of: viewModel.scenes.first?.id) { _, _ in autoSelectFirstItem() }
            .onChange(of: viewModel.sceneMarkers.first?.id) { _, _ in autoSelectFirstItem() }
            .onChange(of: viewModel.clips.first?.id) { _, _ in autoSelectFirstItem() }
            .onChange(of: viewModel.previews.first?.id) { _, _ in autoSelectFirstItem() }
    }

    @ViewBuilder
    private var premiumContentLayout: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if reelsMode == .pics {
                if isInitialized {
                    StashLineView(
                        performerFilter: selectedPerformer?.toGalleryPerformer(),
                        isEmbedded: true,
                        onPerformerTap: { performer in
                            applySettings(sortBy: selectedSortOption, filter: selectedFilter, performer: performer.toScenePerformer(), tags: selectedTags)
                        }
                    )
                    .applyAppBackground()
                } else {
                    StandardLoadingView(message: "Loading StashLine...")
                }
            } else {
                let isLoading = viewModel.isLoading && isListEmpty

                if isLoading {
                    loadingStateView
                } else if isListEmpty && viewModel.errorMessage != nil {
                    errorStateView
                } else {
                    reelsListView()
                }
            }
        }
        .ignoresSafeArea(reelsMode == .pics ? [] : .all)
        .allowsHitTesting(!isMenuOpen)
        .navigationBarHidden(true)
        .safeAreaInset(edge: .top, spacing: 0) {
            reelsNavBar
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if reelsMode != .pics {
                VStack(spacing: 0) {
                    reelsInfoOverlay
                    reelsScrubberBar
                    reelsCapsulesBar
                }
                .contentShape(Rectangle())
                .onTapGesture {}
                .allowsHitTesting(isUIVisible)
            }
        }
    }

    private func handleDefaultFilterChanged(_ notification: Notification) {
        if let tabId = notification.userInfo?["tab"] as? String, tabId == AppTab.reels.rawValue {
            switch reelsMode {
            case .scenes:
                let defaultId = TabManager.shared.getDefaultFilterId(for: .reels)
                let newFilter = defaultId != nil ? viewModel.savedFilters[defaultId!] : nil
                applySettings(sortBy: selectedSortOption, filter: newFilter, performer: selectedPerformer, tags: selectedTags)
            case .markers:
                let defaultId = TabManager.shared.getDefaultMarkerFilterId(for: .reels)
                let newFilter = defaultId != nil ? viewModel.savedFilters[defaultId!] : nil
                applySettings(markerSortBy: selectedMarkerSortOption, filter: newFilter, performer: selectedPerformer, tags: selectedTags)
            case .clips:
                let defaultId = TabManager.shared.getDefaultClipFilterId(for: .reels)
                let newFilter = defaultId != nil ? viewModel.savedFilters[defaultId!] : nil
                selectedClipFilter = newFilter
                applySettings(clipSortBy: selectedClipSortOption, filter: nil, clipFilter: newFilter, performer: selectedPerformer, tags: selectedTags)
            case .previews:
                let defaultId = TabManager.shared.getDefaultPreviewFilterId(for: .reels)
                let newFilter = defaultId != nil ? viewModel.savedFilters[defaultId!] : nil
                selectedPreviewFilter = newFilter
                applySettings(previewSortBy: StashDBViewModel.SceneSortOption(rawValue: TabManager.shared.getReelsDefaultSort(for: .previews) ?? "") ?? selectedSortOption, filter: nil, previewFilter: newFilter, performer: selectedPerformer, tags: selectedTags)
            case .pics:
                break
            }
        }
    }

    private func handleSavedFiltersChanged(_ newValue: [String: StashDBViewModel.SavedFilter]) {
        let isCurrentlyEmpty: Bool = {
            switch reelsMode {
            case .scenes: return viewModel.scenes.isEmpty
            case .markers: return viewModel.sceneMarkers.isEmpty
            case .clips: return viewModel.clips.isEmpty
            case .previews: return viewModel.previews.isEmpty
            case .pics: return false
            }
        }()

        let noCriteriaSet = (reelsMode == .clips ? selectedClipFilter == nil : selectedFilter == nil) && selectedPerformer == nil && selectedTags.isEmpty

        if selectedFilter == nil && reelsMode != .clips && !newValue.isEmpty {
            if let defId = TabManager.shared.getDefaultFilterId(for: .reels), let filter = newValue[defId] {
                selectedFilter = filter
            }
        }

        if noCriteriaSet && isCurrentlyEmpty && !newValue.isEmpty {
            print("✅ ReelsView: Saved filters arrived, triggering initial load...")
            let defaultId: String? = {
                switch reelsMode {
                case .scenes: return TabManager.shared.getDefaultFilterId(for: .reels)
                case .markers: return TabManager.shared.getDefaultMarkerFilterId(for: .reels)
                case .clips: return TabManager.shared.getDefaultClipFilterId(for: .reels)
                case .previews: return TabManager.shared.getDefaultPreviewFilterId(for: .reels)
                case .pics: return nil
                }
            }()

            if let defId = defaultId, let filter = newValue[defId] {
                switch reelsMode {
                case .scenes:
                    applySettings(sortBy: selectedSortOption, filter: filter, performer: selectedPerformer, tags: selectedTags)
                case .markers:
                    applySettings(markerSortBy: selectedMarkerSortOption, filter: filter, performer: selectedPerformer, tags: selectedTags)
                case .clips:
                    selectedClipFilter = filter
                    applySettings(clipSortBy: selectedClipSortOption, filter: nil, clipFilter: filter, performer: selectedPerformer, tags: selectedTags)
                case .previews:
                    selectedPreviewFilter = filter
                    applySettings(previewSortBy: StashDBViewModel.SceneSortOption(rawValue: TabManager.shared.getReelsDefaultSort(for: .previews) ?? "") ?? selectedSortOption, filter: nil, previewFilter: filter, performer: selectedPerformer, tags: selectedTags)
                case .pics:
                    break
                }
            } else {
                let currentModeType = reelsMode.toModeType
                let savedSortStr = TabManager.shared.getReelsDefaultSort(for: currentModeType)

                switch reelsMode {
                case .scenes:
                    let savedSort = StashDBViewModel.SceneSortOption(rawValue: savedSortStr ?? "") ?? .random
                    applySettings(sortBy: savedSort, filter: nil, performer: selectedPerformer, tags: selectedTags)
                case .markers:
                    let savedSort = StashDBViewModel.SceneMarkerSortOption(rawValue: savedSortStr ?? "") ?? .random
                    applySettings(markerSortBy: savedSort, filter: nil, performer: selectedPerformer, tags: selectedTags)
                case .clips:
                    let savedSort = StashDBViewModel.ImageSortOption(rawValue: savedSortStr ?? "") ?? .random
                    applySettings(clipSortBy: savedSort, filter: nil, clipFilter: nil, performer: selectedPerformer, tags: selectedTags, clearClipFilter: true)
                case .previews:
                    let savedSort = StashDBViewModel.SceneSortOption(rawValue: savedSortStr ?? "") ?? .random
                    applySettings(previewSortBy: savedSort, filter: nil, previewFilter: nil, performer: selectedPerformer, tags: selectedTags, clearPreviewFilter: true)
                case .pics:
                    break
                }
            }
        }
    }

    private func handleOnAppear() {
        UIApplication.shared.isIdleTimerDisabled = true

        ReelsSessionRAM.clearLegacyUserDefaultsIfNeeded()
        
        // Audio Optimization: Only activate audio session for video modes.
        // Pics/StashLine has no audio and should not steal iOS audio focus.
        if reelsMode != .pics {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                print("🎬 Reels: Audio setup error: \(error)")
            }
        }

        // 0. Guard against rotation-triggered onAppear
        if isRotating {
            print("🔄 ReelsView: Skipping recursive onAppear during rotation")
            isRotating = false
            return
        }

        if viewModel.savedFilters.isEmpty {
            viewModel.fetchSavedFilters()
        }

        restoreSessionRandomSeedIfAvailable()

        // Restore session sort/filter for the current mode (prevents resetting to defaults on tab return)
        switch reelsMode {
        case .scenes:
            if let raw = sessionSortRaw(for: .scenes), let opt = StashDBViewModel.SceneSortOption(rawValue: raw) {
                selectedSortOption = opt
            }
            if let fid = sessionFilterId(for: .scenes) {
                selectedFilter = viewModel.savedFilters[fid]
            }
        case .markers:
            if let raw = sessionSortRaw(for: .markers), let opt = StashDBViewModel.SceneMarkerSortOption(rawValue: raw) {
                selectedMarkerSortOption = opt
            }
            if let fid = sessionFilterId(for: .markers) {
                selectedFilter = viewModel.savedFilters[fid]
            }
        case .clips:
            if let raw = sessionSortRaw(for: .clips), let opt = StashDBViewModel.ImageSortOption(rawValue: raw) {
                selectedClipSortOption = opt
            }
            if let fid = sessionFilterId(for: .clips) {
                selectedClipFilter = viewModel.savedFilters[fid]
            }
        case .previews:
            if let raw = sessionSortRaw(for: .previews), let opt = StashDBViewModel.SceneSortOption(rawValue: raw) {
                selectedSortOption = opt
            }
            if let fid = sessionFilterId(for: .previews) {
                selectedPreviewFilter = viewModel.savedFilters[fid]
            }
        case .pics:
            break
        }

        // IMPORTANT: Restore the session sort/filter BEFORE restoring scroll position.
        // Otherwise we may auto-select (and persist) the first item from the wrong sort,
        // which breaks position restore (notably for Clips when using Created sorting).
        restorePositionIfAvailable(for: reelsMode, forceIfPrefixMismatch: false)
        beginPagedRestoreIfNeeded()
        autoSelectFirstItem()
        
        // 1. Initialize reelsMode ONLY if current mode is disabled in settings
        let enabledTypes = tabManager.enabledReelsModes
        var currentEffectiveMode = reelsMode
        if !enabledTypes.contains(reelsMode.toModeType) {
            if let first = enabledTypes.first {
                currentEffectiveMode = ReelsMode(from: first)
                reelsMode = currentEffectiveMode
            }
        }
        
        // Determine initial state from coordinator
        let initialPerformer: ScenePerformer? = coordinator.reelsPerformer
        let initialTags: [Tag] = coordinator.reelsTags
        let picsPerformer: GalleryPerformer? = coordinator.picsPerformerFilter
        let targetModeStr: String? = coordinator.reelsTargetMode
        
        // Priority 0: Target mode navigation
        if let modeStr = targetModeStr {
            coordinator.reelsTargetMode = nil
            if let mode = ReelsMode(rawValue: modeStr) {
                currentEffectiveMode = mode
                self.reelsMode = mode
            } else if modeStr == "Pics" {
                currentEffectiveMode = .pics
                self.reelsMode = .pics
            }
        }

        // Priority 0.5: Pics mode navigation from performer detail (legacy check)
        if let performer = picsPerformer {
            coordinator.picsPerformerFilter = nil
            reelsMode = .pics
            applySettings(sortBy: .dateDesc, filter: nil, performer: performer.toScenePerformer())
            isInitialized = true
            return
        }
        
        // Priority 0.75: If effective mode is Pics and we have a performer from nav context,
        // set performer BEFORE body renders StashLineView to avoid an unfiltered initial load.
        if currentEffectiveMode == .pics, let performer = initialPerformer {
            coordinator.reelsPerformer = nil
            coordinator.reelsTags = []
            reelsMode = .pics
            selectedPerformer = performer
            selectedTags = []
            isInitialized = true
            return
        }

        // Priority 1: Navigation Context
        if initialPerformer != nil || !initialTags.isEmpty {
            coordinator.reelsPerformer = nil
            coordinator.reelsTags = []

            // Load saved sort for Scenes mode (default for nav context)
            let savedSortStr = TabManager.shared.getReelsDefaultSort(for: .scenes)
            let savedSort = StashDBViewModel.SceneSortOption(rawValue: savedSortStr ?? "") ?? .random

            // Resolve default filter so removing the performer/tag pill reverts to it (not nil)
            var baseFilter = selectedFilter
            if baseFilter == nil, let defId = TabManager.shared.getDefaultFilterId(for: .reels) {
                baseFilter = viewModel.savedFilters[defId]
            }

            applySettings(sortBy: savedSort, filter: baseFilter, performer: initialPerformer, tags: initialTags, mode: currentEffectiveMode)
            isInitialized = true
        } else {
            let isCurrentlyEmpty: Bool = {
                switch reelsMode {
                case .scenes: return viewModel.scenes.isEmpty
                case .markers: return viewModel.sceneMarkers.isEmpty
                case .clips: return viewModel.clips.isEmpty
                case .previews: return viewModel.previews.isEmpty
                case .pics: return false
                }
            }()

            if isCurrentlyEmpty {
                // Priority 2: Try to apply default filter
                let defaultId: String? = {
                    switch reelsMode {
                    case .scenes: return TabManager.shared.getDefaultFilterId(for: .reels)
                    case .markers: return TabManager.shared.getDefaultMarkerFilterId(for: .reels)
                    case .clips: return TabManager.shared.getDefaultClipFilterId(for: .reels)
                    case .previews: return TabManager.shared.getDefaultPreviewFilterId(for: .reels)
                    case .pics: return nil
                    }
                }()
                    
                let hasFiltersArrived = !viewModel.savedFilters.isEmpty
                
                if defaultId != nil, !hasFiltersArrived {
                    // We need to wait for onChange(of: viewModel.savedFilters) to trigger applySettings
                    print("🕓 ReelsView: Waiting for filters before initial load...")
                } else {
                    // Filters are ready OR no default filter is configured
                    var initialFilter = selectedFilter
                    if initialFilter == nil, let defId = defaultId {
                        initialFilter = viewModel.savedFilters[defId]
                    }
                    
                    // Load saved sort for current mode
                    let currentModeType = reelsMode.toModeType
                    let savedSortStr = TabManager.shared.getReelsDefaultSort(for: currentModeType)
                    
                    // Apply based on mode
                    switch reelsMode {
                    case .scenes:
                        let savedSort = StashDBViewModel.SceneSortOption(rawValue: savedSortStr ?? "") ?? .random
                        selectedSortOption = savedSort
                        applySettings(sortBy: savedSort, filter: initialFilter, performer: selectedPerformer, tags: selectedTags)
                    case .markers:
                        let savedSort = StashDBViewModel.SceneMarkerSortOption(rawValue: savedSortStr ?? "") ?? .random
                        selectedMarkerSortOption = savedSort
                        applySettings(markerSortBy: savedSort, filter: initialFilter, performer: selectedPerformer, tags: selectedTags)
                    case .clips:
                        let savedSort = StashDBViewModel.ImageSortOption(rawValue: savedSortStr ?? "") ?? .random
                        selectedClipSortOption = savedSort
                        var clipFilter = selectedClipFilter
                        if clipFilter == nil, let defId = defaultId {
                            clipFilter = viewModel.savedFilters[defId]
                        }
                        selectedClipFilter = clipFilter
                        applySettings(clipSortBy: savedSort, filter: nil, clipFilter: clipFilter)
                    case .previews:
                        let savedSort = StashDBViewModel.SceneSortOption(rawValue: savedSortStr ?? "") ?? .random
                        selectedSortOption = savedSort
                        var prevFilter = selectedPreviewFilter
                        if prevFilter == nil, let defId = defaultId {
                            prevFilter = viewModel.savedFilters[defId]
                        }
                        selectedPreviewFilter = prevFilter
                        applySettings(previewSortBy: savedSort, filter: nil, previewFilter: prevFilter)
                    case .pics:
                        break
                    }
                }
            }
        }
        isInitialized = true
    }

    private func handleModeChange(from oldValue: ReelsMode, to newValue: ReelsMode) {
        // When switching sub-tabs (Scenes/Markers/Clips/Previews/Pics) always pause the
        // currently playing item immediately. Autoplay for the new mode is handled by
        // autoSelectFirstItem -> currentVisibleSceneId change (which resets isPlaying).
        currentItemIsPlaying = false
        // Some mode switches may not trigger a scrollPosition/currentVisibleSceneId change
        // (e.g. when the list is already populated). Ensure we resume playback intent
        // shortly after the mode switch so the active item can start playing again.
        if newValue != .pics {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.currentItemIsPlaying = true
            }
        } else {
            // Switching into Pics: release audio focus immediately.
            do {
                try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            } catch {
                print("🎬 Reels: Audio deactivation error: \(error)")
            }
        }

        // Persist old mode position, then restore the last known position for the new mode.
        saveCurrentPositionIfPossible(for: oldValue)
        restorePositionIfAvailable(for: newValue, forceIfPrefixMismatch: true)
        beginPagedRestoreIfNeeded()

        // Restore session sort/filter (prefer session over defaults)
        switch newValue {
        case .scenes:
            let sortRaw = sessionSortRaw(for: .scenes) ?? TabManager.shared.getReelsDefaultSort(for: .scenes) ?? ""
            selectedSortOption = StashDBViewModel.SceneSortOption(rawValue: sortRaw) ?? selectedSortOption
            let fid = sessionFilterId(for: .scenes) ?? TabManager.shared.getDefaultFilterId(for: .reels)
            let f = fid != nil ? viewModel.savedFilters[fid!] : nil
            selectedFilter = f
        case .markers:
            let sortRaw = sessionSortRaw(for: .markers) ?? TabManager.shared.getReelsDefaultSort(for: .markers) ?? ""
            selectedMarkerSortOption = StashDBViewModel.SceneMarkerSortOption(rawValue: sortRaw) ?? selectedMarkerSortOption
            let fid = sessionFilterId(for: .markers) ?? TabManager.shared.getDefaultMarkerFilterId(for: .reels)
            let f = fid != nil ? viewModel.savedFilters[fid!] : nil
            selectedFilter = f
        case .clips:
            let sortRaw = sessionSortRaw(for: .clips) ?? TabManager.shared.getReelsDefaultSort(for: .clips) ?? ""
            selectedClipSortOption = StashDBViewModel.ImageSortOption(rawValue: sortRaw) ?? selectedClipSortOption
            let fid = sessionFilterId(for: .clips) ?? TabManager.shared.getDefaultClipFilterId(for: .reels)
            selectedClipFilter = (fid != nil ? viewModel.savedFilters[fid!] : nil)
        case .previews:
            let sortRaw = sessionSortRaw(for: .previews) ?? TabManager.shared.getReelsDefaultSort(for: .previews) ?? ""
            selectedSortOption = StashDBViewModel.SceneSortOption(rawValue: sortRaw) ?? selectedSortOption
            let fid = sessionFilterId(for: .previews) ?? TabManager.shared.getDefaultPreviewFilterId(for: .reels)
            selectedPreviewFilter = (fid != nil ? viewModel.savedFilters[fid!] : nil)
        case .pics:
            break
        }

        switch newValue {
        case .markers:
            applySettings(markerSortBy: selectedMarkerSortOption, filter: selectedFilter, performer: selectedPerformer, tags: selectedTags, mode: newValue)
        case .scenes:
            applySettings(sortBy: selectedSortOption, filter: selectedFilter, performer: selectedPerformer, tags: selectedTags, mode: newValue)
        case .clips:
            applySettings(clipSortBy: selectedClipSortOption, filter: nil, clipFilter: selectedClipFilter, performer: selectedPerformer, tags: selectedTags, mode: newValue)
        case .previews:
            applySettings(previewSortBy: selectedSortOption, filter: nil, previewFilter: selectedPreviewFilter, performer: selectedPerformer, tags: selectedTags, mode: newValue)
        case .pics:
            break
        }
    }

    @ViewBuilder
    private var loadingStateView: some View {
        StandardLoadingView(message: "Loading feeds...")
    }

    @ViewBuilder
    private var errorStateView: some View {
        VStack {
            Spacer()
            ConnectionErrorView(onRetry: {
                applySettings(sortBy: selectedSortOption, filter: selectedFilter, performer: selectedPerformer, tags: selectedTags)
            }, isDark: true)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private func advanceToNextItem(from item: ReelItemData) {
        let items = currentReelItems
        guard let currentIndex = items.firstIndex(where: { $0.id == item.id }) else { return }
        let nextIndex = currentIndex + 1
        guard nextIndex < items.count else { return }
        currentVisibleSceneId = items[nextIndex].id
    }

    @ViewBuilder
    private func reelItemRow(index: Int, item: ReelItemData, itemCount: Int) -> some View {
        ReelItemView(
            item: item,
            currentVisibleSceneId: $currentVisibleSceneId,
            isMuted: $isMuted,
            isUIVisible: $isUIVisible,
            isPlaying: $currentItemIsPlaying,
            isUserScrolling: $isUserScrollingReels,
            showRatingOverlay: $currentItemShowRatingOverlay,
            scrubberState: scrubberState,
            onPerformerTap: { performer in
                applySettings(sortBy: selectedSortOption, filter: selectedFilter, performer: performer, tags: selectedTags)
            },
            onTagTap: { tag in
                // Add tag to existing selection (or toggle off if already selected)
                var newTags = selectedTags
                if newTags.contains(where: { $0.id == tag.id }) {
                    newTags.removeAll { $0.id == tag.id }
                } else {
                    newTags.append(tag)
                }
                applySettings(sortBy: selectedSortOption, filter: selectedFilter, performer: selectedPerformer, tags: newTags)
            },
            onRatingChanged: { rating in
                self.handleRatingChange(item: item, newRating: rating)
            },
            onOCounterChanged: { newCount in
                self.handleOCounterChange(item: item, newCount: newCount)
            },
            onPlayCountChanged: { newCount in
                self.handlePlayCountChange(item: item, newCount: newCount)
            },
            onVideoEnded: {
                self.advanceToNextItem(from: item)
            },
            viewModel: viewModel,
            playTrigger: playTrigger,
            isMenuOpen: $isMenuOpen,
            isZoomed: $isMediaZoomed,
            isRotating: $isRotating,
            onInteraction: { }
        )
        .scrollDisabled(isMediaZoomed)
        .containerRelativeFrame([.horizontal, .vertical])
        .background(Color.black)
        .id(item.id)
        .onAppear {
            if index == itemCount - 2 {
                switch reelsMode {
                case .scenes: viewModel.loadMoreScenes()
                case .markers: viewModel.loadMoreMarkers()
                case .clips: viewModel.loadMoreClips()
                case .previews: viewModel.loadMorePreviews()
                case .pics: break
                }
            }
        }
    }

    @ViewBuilder
    private func reelsListView() -> some View {
        let items = currentReelItems

        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        reelItemRow(index: index, item: item, itemCount: items.count)
                    }
                }
                .scrollTargetLayout()
            }
            .focusable(false)
            .focusEffectDisabled()
            .scrollTargetBehavior(.paging)
            .scrollDisabled(isMenuOpen)
            .scrollPosition(id: scrollPositionBinding)
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .onScrollPhaseChange { _, newPhase in
                isUserScrollingReels = (newPhase != .idle)
                if newPhase != .idle {
                    currentItemIsPlaying = false
                    ReelsPlayerRegistry.pauseAll()
                    NotificationCenter.default.post(name: .reelsPauseAllPlayers, object: nil)
                }
            }
            .onChange(of: items.count) { _, _ in
                continuePagedRestoreIfNeeded()
                snapToPendingRestoreIfLoaded(using: proxy)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
                withAnimation(.easeInOut(duration: 0.3)) { isRotating = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    withAnimation { isRotating = false }
                }
            }
        }
    }

    /// Scrolls to pending restore target once it's present in the list. No overlay,
    /// no blocking — UI already shows first item. Just a single scroll-snap.
    private func snapToPendingRestoreIfLoaded(using proxy: ScrollViewProxy) {
        guard let target = pendingRestoreId else { return }
        guard currentReelItems.contains(where: { $0.id == target }) else { return }

        pendingRestoreId = nil
        ReelsPlayerRegistry.pauseAll()
        currentVisibleSceneId = target

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(nil) {
                proxy.scrollTo(target, anchor: .top)
            }
            if self.reelsMode != .pics {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.currentItemIsPlaying = true
                }
            }
        }
    }


    @ViewBuilder
    private var reelsNavBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(reelsMode.rawValue)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .frame(width: 120, alignment: .leading)

                let enabledModes = tabManager.enabledReelsModes.map { ReelsMode(from: $0) }
                HStack(spacing: 8) {
                    ForEach(enabledModes, id: \.self) { mode in
                        let isActive = mode == reelsMode
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                reelsMode = mode
                            }
                        }) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(isActive ? .white : .white.opacity(0.6))
                                .frame(maxWidth: .infinity)
                                .frame(height: 32)
                                .background(
                                    RoundedRectangle(cornerRadius: 9)
                                        .fill(isActive ? appearanceManager.tintColor : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)

            // Active performer / tag pills
            // Always reserve space for this row so the safeAreaInset height stays constant.
            // Changing the inset height causes the paging ScrollView to re-layout,
            // which displaces the active video and kills its player.
            let hasFilters = selectedPerformer != nil || !selectedTags.isEmpty
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let performer = selectedPerformer {
                        Button(action: {
                            applySettings(sortBy: selectedSortOption, filter: selectedFilter, performer: nil, tags: selectedTags)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                                Text(performer.name).font(.system(size: 12, weight: .bold)).lineLimit(1)
                            }
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Capsule())
                        }
                    }
                    ForEach(selectedTags) { tag in
                        Button(action: {
                            var newTags = selectedTags
                            newTags.removeAll { $0.id == tag.id }
                            applySettings(sortBy: selectedSortOption, filter: selectedFilter, performer: selectedPerformer, tags: newTags)
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                                Text("#\(tag.name)").font(.system(size: 12, weight: .bold)).lineLimit(1)
                            }
                            .foregroundColor(.white.opacity(0.9))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
            .frame(height: hasFilters ? nil : 0)
            .clipped()
            .padding(.bottom, hasFilters ? 6 : 0)
            .animation(.easeInOut(duration: 0.15), value: hasFilters)

            Divider().overlay(Color.white.opacity(0.15))
        }
        .background(.bar)
        .colorScheme(.dark)
        .opacity(isUIVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: isUIVisible)
    }

    /// Only the two capsule rows — lives in safeAreaInset so it sits at the same level as other views
    @ViewBuilder
    private var reelsCapsulesBar: some View {
        let currentItem = currentReelItems.first(where: { $0.id == currentVisibleSceneId })
        // Default to true when no item matched (transitioning between filter results)
        // to avoid showing strikethrough controls during brief loading gap.
        let isVideo = currentItem == nil ? true : (currentItem?.videoURL != nil && !(currentItem?.isAnimated ?? true))

        HStack(spacing: 0) {
            // Left Group
            HStack(spacing: 12) {
                sortMenu
                filterMenu
            }
            .fixedSize()
            
            Spacer(minLength: 4)
            
            // O-Counter
            let oCounter = currentItem?.oCounter ?? 0
            Button {
                if let item = currentItem { handleOCounterChange(item: item, newCount: oCounter + 1) }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: oCounter > 0 ? AppearanceManager.shared.oCounterIconFilled : AppearanceManager.shared.oCounterIcon)
                        .foregroundColor(oCounter > 0 ? appearanceManager.tintColor : .white)
                    Text("\(oCounter)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }
                .opacity(oCounter == 0 ? 0.5 : 1.0)
            }
            .buttonStyle(.plain)
            
            Spacer(minLength: 4)
            
            // Rating (popup menu like sort/filter)
            if let item = currentItem {
                let rating100 = item.rating100 ?? 0
                let stars = max(0, min(5, Int(round(Double(rating100) / 20.0))))

                Menu {
                    Button(action: { handleRatingChange(item: item, newRating: 0) }) {
                        HStack {
                            Text("Clear Rating")
                            if stars == 0 { Image(systemName: "checkmark") }
                        }
                    }
                    Divider()
                    ForEach(1...5, id: \.self) { s in
                        Button(action: { handleRatingChange(item: item, newRating: s * 20) }) {
                            HStack {
                                Text(String(repeating: "★", count: s))
                                if stars == s { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .foregroundColor(.white.opacity(stars > 0 ? 1.0 : 0.7))
                        Text("\(stars)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .opacity(stars == 0 ? 0.5 : 1.0)
                }
                .buttonStyle(.plain)
                .fixedSize()
            }
            
            Spacer(minLength: 4)
            
            // Right Group
            HStack(spacing: 16) {
                Button {
                    if isVideo { isMuted.toggle() }
                } label: {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .foregroundColor(isVideo ? .white : .white.opacity(0.5))
                        .overlay(
                            Group {
                                if !isVideo {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.8))
                                        .frame(width: 20, height: 1.5)
                                        .rotationEffect(.degrees(-45))
                                }
                            }
                        )
                }
                .disabled(!isVideo)

                Button {
                    if isVideo { currentItemIsPlaying.toggle() }
                } label: {
                    Image(systemName: currentItemIsPlaying ? "pause.fill" : "play.fill")
                        .foregroundColor(isVideo ? .white : .white.opacity(0.5))
                        .overlay(
                            Group {
                                if !isVideo {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.8))
                                        .frame(width: 20, height: 1.5)
                                        .rotationEffect(.degrees(-45))
                                }
                            }
                        )
                }
                .disabled(!isVideo)
            }
            .fixedSize()
        }
        .font(.system(size: 17))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 16)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        )
        .overlay(
            Capsule()
                .stroke(Color.primary.opacity(0.07), lineWidth: 0.5)
        )
        .frame(height: 36)
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .colorScheme(.dark)
        .opacity(isUIVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: isUIVisible)
    }

    // MARK: - Scrubber bar (below capsules)
    @ViewBuilder
    private var reelsScrubberBar: some View {
        let currentItem = currentReelItems.first(where: { $0.id == currentVisibleSceneId })
        if let item = currentItem {
            if item.isAnimated {
                // GIFs don't have a scrubber; don't reserve scrubber space (it pushed the overlay too high).
                EmptyView()
            } else {
                IsolatedScrubberBar(state: scrubberState, isUIVisible: isUIVisible)
            }
        }
    }

    /// Info overlay, positioned above the capsule bar
    @ViewBuilder
    private var reelsInfoOverlay: some View {
        let currentItem = currentReelItems.first(where: { $0.id == currentVisibleSceneId })
        VStack(alignment: .leading, spacing: 0) {
            if let item = currentItem {
                HStack(alignment: .top, spacing: 10) {
                    if let performer = item.performers.first {
                        Button(action: {
                            applySettings(sortBy: selectedSortOption, filter: selectedFilter, performer: performer, tags: selectedTags)
                        }) {
                            performerThumbnail(performer)
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        // Performer - Title
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            if let performer = item.performers.first {
                                Button(action: {
                                    applySettings(sortBy: selectedSortOption, filter: selectedFilter, performer: performer, tags: selectedTags)
                                }) {
                                    Text(performer.name)
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundColor(.white)
                                }
                                .buttonStyle(.plain)
                                .layoutPriority(1)
                                Text("-")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                            if let title = item.title, !title.isEmpty {
                                if let scene = item.underlyingScene {
                                    NavigationLink(destination: SceneDetailView(scene: scene)) {
                                        Text(title)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(.white.opacity(0.85))
                                            .lineLimit(1)
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    Text(title)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(.white.opacity(0.85))
                                        .lineLimit(1)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Hashtags
                        let tags = item.tags
                        Group {
                            if !tags.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(tags) { tag in
                                            Button(action: {
                                                var newTags = selectedTags
                                                if newTags.contains(where: { $0.id == tag.id }) {
                                                    newTags.removeAll { $0.id == tag.id }
                                                } else {
                                                    newTags.append(tag)
                                                }
                                                applySettings(sortBy: selectedSortOption, filter: selectedFilter, performer: selectedPerformer, tags: newTags)
                                            }) {
                                                Text("#\(tag.name)")
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .foregroundColor(.white.opacity(0.8))
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 3)
                                                    .background(Color.black.opacity(0.3))
                                                    .clipShape(Capsule())
                                                    .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            } else {
                                // Reserve space so the title row doesn't drop for items without tags (e.g. Clips/GIFs).
                                Color.clear.opacity(0)
                            }
                        }
                        .frame(height: 20)
                    }
                }
                .padding(.horizontal, 12)


            }
        }
        // Sit directly above the capsule bar
        .padding(.bottom, -6)
        .colorScheme(.dark)
        .opacity(isUIVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: isUIVisible)
        .allowsHitTesting(!isMenuOpen)
    }

    @ViewBuilder
    private func performerThumbnail(_ performer: ScenePerformer) -> some View {
        let size: CGFloat = 36
        Circle()
            .fill(appearanceManager.tintColor.opacity(0.2))
            .frame(width: size, height: size)
            .overlay {
                if let url = performer.thumbnailURL {
                    CustomAsyncImage(url: url) { loader in
                        if let img = loader.image {
                            img.resizable().scaledToFill()
                        } else {
                            Image(systemName: "person.fill")
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                } else {
                    Image(systemName: "person.fill")
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .clipShape(Circle())
            .overlay(Circle().stroke(appearanceManager.tintColor, lineWidth: 2))
    }

    @ToolbarContentBuilder
    private var reelsToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button(action: {
                // Navigate back to the first visible tab (home)
                if let firstTab = TabManager.shared.visibleTabs.first {
                    coordinator.selectedTab = firstTab
                }
            }) {
                Image(systemName: "chevron.left")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Color.black.opacity(0.01)) // Ensure hit area is detected
                    .contentShape(Rectangle())
            }
        }
            
            if !(isListEmpty && viewModel.errorMessage != nil) {
                ToolbarItem(placement: .principal) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            if let performer = selectedPerformer {
                                Button(action: {
                                    applySettings(sortBy: selectedSortOption, filter: selectedFilter, performer: nil, tags: selectedTags)
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 10, weight: .bold))
                                        Text(performer.name)
                                            .font(.system(size: 12, weight: .bold))
                                            .lineLimit(1)
                                    }
                                    .foregroundColor(.white.opacity(0.9))
                                    .padding(Edge.Set.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(Color.black.opacity(DesignTokens.Opacity.badge))
                                    .clipShape(Capsule())
                                }
                            }
                            
                            ForEach(selectedTags) { tag in
                                Button(action: {
                                    var newTags = selectedTags
                                    newTags.removeAll { $0.id == tag.id }
                                    applySettings(sortBy: selectedSortOption, filter: selectedFilter, performer: selectedPerformer, tags: newTags)
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 10, weight: .bold))
                                        Text("#\(tag.name)")
                                            .font(.system(size: 12, weight: .bold))
                                            .lineLimit(1)
                                    }
                                    .foregroundColor(.white.opacity(0.9))
                                    .padding(Edge.Set.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(Color.black.opacity(DesignTokens.Opacity.badge))
                                    .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    modeMenu
                    sortMenu
                    filterMenu
                }
            }
        }

    private var filterColor: Color {
        selectedFilter != nil ? appearanceManager.tintColor : .white
    }

    @ViewBuilder
    private var modeMenu: some View {
        Menu {
            Picker("Mode", selection: $reelsMode) {
                ForEach(tabManager.enabledReelsModes, id: \.self) { modeType in
                    let mode = ReelsMode(from: modeType)
                    Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: reelsMode.icon)
                    .fontWeight(.semibold)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundColor(.white)
        }
    }

    @ViewBuilder
    private var sortMenu: some View {
        Menu {
            switch reelsMode {
            case .scenes:
                sceneSortOptions
            case .markers:
                markerSortOptions
            case .clips:
                clipSortOptions
            case .previews:
                previewSortOptions
            case .pics:
                EmptyView()
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
        }
    }

    @ViewBuilder
    private var sceneSortOptions: some View {
        // Random
        Button(action: {
            applySettings(
                sortBy: .random,
                filter: selectedFilter,
                performer: selectedPerformer,
                tags: selectedTags,
                rerollRandom: selectedSortOption == .random
            )
        }) {
            HStack {
                Text("Random")
                if selectedSortOption == .random { Image(systemName: "checkmark") }
            }
        }
        
        Divider()
        
        // Date
        Menu {
            Button(action: { applySettings(sortBy: .dateDesc, filter: selectedFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("Newest First")
                    if selectedSortOption == .dateDesc { Image(systemName: "checkmark") }
                }
            }
            Button(action: { applySettings(sortBy: .dateAsc, filter: selectedFilter, performer: selectedPerformer, tags: selectedTags) }) {
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
            Button(action: { applySettings(sortBy: .titleAsc, filter: selectedFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("A → Z")
                    if selectedSortOption == .titleAsc { Image(systemName: "checkmark") }
                }
            }
            Button(action: { applySettings(sortBy: .titleDesc, filter: selectedFilter, performer: selectedPerformer, tags: selectedTags) }) {
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
            Button(action: { applySettings(sortBy: .durationDesc, filter: selectedFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("Longest First")
                    if selectedSortOption == .durationDesc { Image(systemName: "checkmark") }
                }
            }
            Button(action: { applySettings(sortBy: .durationAsc, filter: selectedFilter, performer: selectedPerformer, tags: selectedTags) }) {
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
        
        // Play Count
        Menu {
            Button(action: { applySettings(sortBy: .playCountDesc, filter: selectedFilter, performer: selectedPerformer) }) {
                HStack {
                    Text("Most Viewed")
                    if selectedSortOption == .playCountDesc { Image(systemName: "checkmark") }
                }
            }
            Button(action: { applySettings(sortBy: .playCountAsc, filter: selectedFilter, performer: selectedPerformer) }) {
                HStack {
                    Text("Least Viewed")
                    if selectedSortOption == .playCountAsc { Image(systemName: "checkmark") }
                }
            }
        } label: {
            HStack {
                Text("Views")
                if selectedSortOption == .playCountAsc || selectedSortOption == .playCountDesc { Image(systemName: "checkmark") }
            }
        }
        
        // Last Played
        Menu {
            Button(action: { applySettings(sortBy: .lastPlayedAtDesc, filter: selectedFilter, performer: selectedPerformer) }) {
                HStack {
                    Text("Recently Played")
                    if selectedSortOption == .lastPlayedAtDesc { Image(systemName: "checkmark") }
                }
            }
            Button(action: { applySettings(sortBy: .lastPlayedAtAsc, filter: selectedFilter, performer: selectedPerformer) }) {
                HStack {
                    Text("Least Recently")
                    if selectedSortOption == .lastPlayedAtAsc { Image(systemName: "checkmark") }
                }
            }
        } label: {
            HStack {
                Text("Last Played")
                if selectedSortOption == .lastPlayedAtAsc || selectedSortOption == .lastPlayedAtDesc { Image(systemName: "checkmark") }
            }
        }
        
        // Created
        Menu {
            Button(action: { applySettings(sortBy: .createdAtDesc, filter: selectedFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("Newest First")
                    if selectedSortOption == .createdAtDesc { Image(systemName: "checkmark") }
                }
            }
            Button(action: { applySettings(sortBy: .createdAtAsc, filter: selectedFilter, performer: selectedPerformer, tags: selectedTags) }) {
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
        
        // Counter (O-Counter)
        Menu {
            Button(action: { applySettings(sortBy: .oCounterDesc, filter: selectedFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("High → Low")
                    if selectedSortOption == .oCounterDesc { Image(systemName: "checkmark") }
                }
            }
            Button(action: { applySettings(sortBy: .oCounterAsc, filter: selectedFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("Low → High")
                    if selectedSortOption == .oCounterAsc { Image(systemName: "checkmark") }
                }
            }
        } label: {
            HStack {
                Text("O-Counter")
                if selectedSortOption == .oCounterAsc || selectedSortOption == .oCounterDesc { Image(systemName: "checkmark") }
            }
        }
        
        // Rating
        Menu {
            Button(action: { applySettings(sortBy: .ratingDesc, filter: selectedFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("High → Low")
                    if selectedSortOption == .ratingDesc { Image(systemName: "checkmark") }
                }
            }
            Button(action: { applySettings(sortBy: .ratingAsc, filter: selectedFilter, performer: selectedPerformer, tags: selectedTags) }) {
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
    }

    @ViewBuilder
    private var markerSortOptions: some View {
        // Random
        Button(action: {
            applySettings(
                markerSortBy: .random,
                filter: selectedFilter,
                performer: selectedPerformer,
                tags: selectedTags,
                rerollRandom: selectedMarkerSortOption == .random
            )
        }) {
            HStack {
                Text("Random")
                if selectedMarkerSortOption == .random { Image(systemName: "checkmark") }
            }
        }
        
        Divider()
        
        // Created
        Menu {
            Button(action: { applySettings(markerSortBy: .createdAtDesc, filter: selectedFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("Newest First")
                    if selectedMarkerSortOption == .createdAtDesc { Image(systemName: "checkmark") }
                }
            }
            Button(action: { applySettings(markerSortBy: .createdAtAsc, filter: selectedFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("Oldest First")
                    if selectedMarkerSortOption == .createdAtAsc { Image(systemName: "checkmark") }
                }
            }
        } label: {
            HStack {
                Text("Created")
                if selectedMarkerSortOption == .createdAtAsc || selectedMarkerSortOption == .createdAtDesc { Image(systemName: "checkmark") }
            }
        }
        
        // Title
        Menu {
            Button(action: { applySettings(markerSortBy: .titleAsc, filter: selectedFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("A → Z")
                    if selectedMarkerSortOption == .titleAsc { Image(systemName: "checkmark") }
                }
            }
            Button(action: { applySettings(markerSortBy: .titleDesc, filter: selectedFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("Z → A")
                    if selectedMarkerSortOption == .titleDesc { Image(systemName: "checkmark") }
                }
            }
        } label: {
            HStack {
                Text("Title")
                if selectedMarkerSortOption == .titleAsc || selectedMarkerSortOption == .titleDesc { Image(systemName: "checkmark") }
            }
        }
        
        // Time
        Menu {
            Button(action: { applySettings(markerSortBy: .secondsAsc, filter: selectedFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("Start Time")
                    if selectedMarkerSortOption == .secondsAsc { Image(systemName: "checkmark") }
                }
            }
            Button(action: { applySettings(markerSortBy: .secondsDesc, filter: selectedFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("End Time")
                    if selectedMarkerSortOption == .secondsDesc { Image(systemName: "checkmark") }
                }
            }
        } label: {
            HStack {
                Text("Time")
                if selectedMarkerSortOption == .secondsAsc || selectedMarkerSortOption == .secondsDesc { Image(systemName: "checkmark") }
            }
        }
    }
    
    @ViewBuilder
    private var previewSortOptions: some View {
        // Previews are scenes — same sort options as sceneSortOptions
        Button(action: {
            applySettings(
                previewSortBy: .random,
                filter: selectedFilter,
                previewFilter: selectedPreviewFilter,
                performer: selectedPerformer,
                tags: selectedTags,
                rerollRandom: selectedSortOption == .random
            )
        }) {
            HStack {
                Text("Random")
                if selectedSortOption == .random { Image(systemName: "checkmark") }
            }
        }

        Divider()

        // Date
        Menu {
            Button(action: { applySettings(previewSortBy: .dateDesc, filter: selectedFilter, previewFilter: selectedPreviewFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("Newest First")
                    if selectedSortOption == .dateDesc { Image(systemName: "checkmark") }
                }
            }
            Button(action: { applySettings(previewSortBy: .dateAsc, filter: selectedFilter, previewFilter: selectedPreviewFilter, performer: selectedPerformer, tags: selectedTags) }) {
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
            Button(action: { applySettings(previewSortBy: .titleAsc, filter: selectedFilter, previewFilter: selectedPreviewFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("A → Z")
                    if selectedSortOption == .titleAsc { Image(systemName: "checkmark") }
                }
            }
            Button(action: { applySettings(previewSortBy: .titleDesc, filter: selectedFilter, previewFilter: selectedPreviewFilter, performer: selectedPerformer, tags: selectedTags) }) {
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
            Button(action: { applySettings(previewSortBy: .durationDesc, filter: selectedFilter, previewFilter: selectedPreviewFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("Longest First")
                    if selectedSortOption == .durationDesc { Image(systemName: "checkmark") }
                }
            }
            Button(action: { applySettings(previewSortBy: .durationAsc, filter: selectedFilter, previewFilter: selectedPreviewFilter, performer: selectedPerformer, tags: selectedTags) }) {
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

        // Last Played
        Menu {
            Button(action: { applySettings(previewSortBy: .lastPlayedAtDesc, filter: selectedFilter, previewFilter: selectedPreviewFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("Recently Played")
                    if selectedSortOption == .lastPlayedAtDesc { Image(systemName: "checkmark") }
                }
            }
            Button(action: { applySettings(previewSortBy: .lastPlayedAtAsc, filter: selectedFilter, previewFilter: selectedPreviewFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("Least Recently")
                    if selectedSortOption == .lastPlayedAtAsc { Image(systemName: "checkmark") }
                }
            }
        } label: {
            HStack {
                Text("Last Played")
                if selectedSortOption == .lastPlayedAtAsc || selectedSortOption == .lastPlayedAtDesc { Image(systemName: "checkmark") }
            }
        }

        // Created
        Menu {
            Button(action: { applySettings(previewSortBy: .createdAtDesc, filter: selectedFilter, previewFilter: selectedPreviewFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("Newest First")
                    if selectedSortOption == .createdAtDesc { Image(systemName: "checkmark") }
                }
            }
            Button(action: { applySettings(previewSortBy: .createdAtAsc, filter: selectedFilter, previewFilter: selectedPreviewFilter, performer: selectedPerformer, tags: selectedTags) }) {
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

        // O-Counter
        Menu {
            Button(action: { applySettings(previewSortBy: .oCounterDesc, filter: selectedFilter, previewFilter: selectedPreviewFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("High → Low")
                    if selectedSortOption == .oCounterDesc { Image(systemName: "checkmark") }
                }
            }
            Button(action: { applySettings(previewSortBy: .oCounterAsc, filter: selectedFilter, previewFilter: selectedPreviewFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("Low → High")
                    if selectedSortOption == .oCounterAsc { Image(systemName: "checkmark") }
                }
            }
        } label: {
            HStack {
                Text("O-Counter")
                if selectedSortOption == .oCounterAsc || selectedSortOption == .oCounterDesc { Image(systemName: "checkmark") }
            }
        }

        // Rating
        Menu {
            Button(action: { applySettings(previewSortBy: .ratingDesc, filter: selectedFilter, previewFilter: selectedPreviewFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("High → Low")
                    if selectedSortOption == .ratingDesc { Image(systemName: "checkmark") }
                }
            }
            Button(action: { applySettings(previewSortBy: .ratingAsc, filter: selectedFilter, previewFilter: selectedPreviewFilter, performer: selectedPerformer, tags: selectedTags) }) {
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
    }
    
    @ViewBuilder
    private var clipSortOptions: some View {
        // Random
        Button(action: {
            applySettings(
                clipSortBy: .random,
                filter: nil,
                clipFilter: selectedClipFilter,
                performer: selectedPerformer,
                tags: selectedTags,
                rerollRandom: selectedClipSortOption == .random
            )
        }) {
            HStack {
                Text("Random")
                if selectedClipSortOption == .random { Image(systemName: "checkmark") }
            }
        }
        
        Divider()
        
        // Date
        Menu {
            Button(action: { applySettings(clipSortBy: .dateDesc, filter: nil, clipFilter: selectedClipFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("Newest First")
                    if selectedClipSortOption == .dateDesc { Image(systemName: "checkmark") }
                }
            }
            Button(action: { applySettings(clipSortBy: .dateAsc, filter: nil, clipFilter: selectedClipFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("Oldest First")
                    if selectedClipSortOption == .dateAsc { Image(systemName: "checkmark") }
                }
            }
        } label: {
            HStack {
                Text("Date")
                if selectedClipSortOption == .dateAsc || selectedClipSortOption == .dateDesc { Image(systemName: "checkmark") }
            }
        }
        
        // Title
        Menu {
            Button(action: { applySettings(clipSortBy: .titleAsc, filter: nil, clipFilter: selectedClipFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("A → Z")
                    if selectedClipSortOption == .titleAsc { Image(systemName: "checkmark") }
                }
            }
            Button(action: { applySettings(clipSortBy: .titleDesc, filter: nil, clipFilter: selectedClipFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("Z → A")
                    if selectedClipSortOption == .titleDesc { Image(systemName: "checkmark") }
                }
            }
        } label: {
            HStack {
                Text("Title")
                if selectedClipSortOption == .titleAsc || selectedClipSortOption == .titleDesc { Image(systemName: "checkmark") }
            }
        }
        
        // Rating
        Menu {
            Button(action: { applySettings(clipSortBy: .ratingDesc, filter: nil, clipFilter: selectedClipFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("Highest First")
                    if selectedClipSortOption == .ratingDesc { Image(systemName: "checkmark") }
                }
            }
            Button(action: { applySettings(clipSortBy: .ratingAsc, filter: nil, clipFilter: selectedClipFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("Lowest First")
                    if selectedClipSortOption == .ratingAsc { Image(systemName: "checkmark") }
                }
            }
        } label: {
            HStack {
                Text("Rating")
                if selectedClipSortOption == .ratingAsc || selectedClipSortOption == .ratingDesc { Image(systemName: "checkmark") }
            }
        }

        // Created
        Menu {
            Button(action: { applySettings(clipSortBy: .createdAtDesc, filter: nil, clipFilter: selectedClipFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("Newest First")
                    if selectedClipSortOption == .createdAtDesc { Image(systemName: "checkmark") }
                }
            }
            Button(action: { applySettings(clipSortBy: .createdAtAsc, filter: nil, clipFilter: selectedClipFilter, performer: selectedPerformer, tags: selectedTags) }) {
                HStack {
                    Text("Oldest First")
                    if selectedClipSortOption == .createdAtAsc { Image(systemName: "checkmark") }
                }
            }
        } label: {
            HStack {
                Text("Created")
                if selectedClipSortOption == .createdAtAsc || selectedClipSortOption == .createdAtDesc { Image(systemName: "checkmark") }
            }
        }
    }

    @ViewBuilder
    private var filterMenu: some View {
        Menu {
            if reelsMode == .clips {
                // Clips uses image filters
                Button(action: {
                    selectedClipFilter = nil
                    applySettings(filter: nil, clipFilter: nil, performer: selectedPerformer, tags: selectedTags, mode: .clips, clearClipFilter: true)
                }) {
                    HStack {
                        Text("No Filter")
                        if selectedClipFilter == nil { Image(systemName: "checkmark") }
                    }
                }
                
                let imageFilters = viewModel.savedFilters.values
                    .filter { $0.mode == .images && $0.id != "reels_temp" && $0.id != "reels_merged" }
                    .sorted { $0.name < $1.name }
                
                ForEach(imageFilters) { filter in
                    Button(action: {
                        selectedClipFilter = filter
                        applySettings(filter: nil, clipFilter: filter, performer: selectedPerformer, tags: selectedTags, mode: .clips)
                    }) {
                        HStack {
                            Text(filter.name)
                            if selectedClipFilter?.id == filter.id { Image(systemName: "checkmark") }
                        }
                    }
                }
            } else {
                // Scenes/Markers share scene or sceneMarker filters
                Button(action: {
                    applySettings(filter: nil, performer: selectedPerformer, tags: selectedTags)
                }) {
                    HStack {
                        Text("No Filter")
                        if selectedFilter == nil { Image(systemName: "checkmark") }
                    }
                }

                let mode: StashDBViewModel.FilterMode = (reelsMode == .scenes || reelsMode == .previews) ? .scenes : .sceneMarkers
                let activeFilters = viewModel.savedFilters.values
                    .filter { $0.mode == mode && $0.id != "reels_temp" && $0.id != "reels_merged" }
                    .sorted { $0.name < $1.name }

                ForEach(activeFilters) { filter in
                    Button(action: {
                        applySettings(filter: filter, performer: selectedPerformer, tags: selectedTags)
                    }) {
                        HStack {
                            Text(filter.name)
                            if selectedFilter?.id == filter.id { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
        } label: {
            let hasActiveFilter = (reelsMode == .clips ? selectedClipFilter != nil : selectedFilter != nil)
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(hasActiveFilter ? appearanceManager.tintColor : .white)
        }
    }
}

struct ReelItemView: View {
    let item: ReelsView.ReelItemData
    @Binding var currentVisibleSceneId: String?
    
    var isActive: Bool {
        item.id == currentVisibleSceneId
    }
    
    @State private var player: AVPlayer?
    @State private var looper: Any?
    @State private var animationAdvanceTimer: Timer?
    @ObservedObject var tabManager = TabManager.shared
    
    // Playback State
    @Binding var isMuted: Bool
    @Binding var isUIVisible: Bool
    @Binding var isPlaying: Bool
    @Binding var isUserScrolling: Bool
    @Binding var showRatingOverlay: Bool
    let scrubberState: ScrubberState
    var onPerformerTap: (ScenePerformer) -> Void
    var onTagTap: (Tag) -> Void
    var onRatingChanged: (Int?) -> Void
    var onOCounterChanged: (Int) -> Void
    var onPlayCountChanged: (Int) -> Void
    var onVideoEnded: () -> Void = {}
    @ObservedObject var viewModel: StashDBViewModel
    var playTrigger: Int
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @State private var timeObserver: Any?
    /// Bumped on each `setupPlayer` / `cleanupPlayer` so in-flight `fetchSceneStreams`
    /// completions cannot attach a new `AVPlayerItem` after the user has scrolled away.
    @State private var playerSetupGeneration: Int = 0
    @State private var showTagsOverlay = false
    @Binding var isMenuOpen: Bool
    @Binding var isZoomed: Bool
    @Binding var isRotating: Bool
    @State private var showStashSyncSheet = false
    @State private var isFastForwarding = false
    var onInteraction: () -> Void

    private var shouldFill: Bool {
        // Only fill if the setting is enabled
        guard tabManager.reelsFillHeight else { return false }
        
        let isPortraitDevice = UIScreen.main.bounds.height > UIScreen.main.bounds.width
        if isPortraitDevice {
            // In portrait device: fill if item is portrait
            return item.isPortrait
        } else {
            // In landscape device: fill if item is landscape (exclude GIFs which might look bad stretched too much)
            return !item.isPortrait
        }
    }

    
    
    var body: some View {
        applyModifiers(mainContent)
    }

    @ViewBuilder
    private var mainContent: some View {
        ZStack(alignment: .bottom) {
            mediaLayer
            fastForwardOverlay
            playButtonOverlay
            bottomBarOverlay
        }
    }
}

extension ReelItemView {
    func applyModifiers<V: View>(_ content: V) -> some View {
        let v1 = applyBasicModifiers(content)
        let v2 = applyPlaybackLifecycleModifiers(v1)
        let v4 = applyOverlayModifiers(v2)
        return applyStashSyncModifiers(v4)
    }

    @ViewBuilder
    private func applyBasicModifiers<V: View>(_ content: V) -> some View {
        content
            .buttonStyle(.plain)
            .background(Color.black)
            .focusable(false)
            .focusEffectDisabled()
    }

    @ViewBuilder
    private func applyPlaybackLifecycleModifiers<V: View>(_ content: V) -> some View {
        content
            .onAppear {
                // Critical: do **not** call `setupPlayer()` for off-screen rows. During
                // fast scroll every flashed cell would otherwise spawn HLS + a
                // `fetchSceneStreams` round-trip — that saturates Stash/ffmpeg.
                if isActive {
                    setupPlayer()
                    onInteraction()
                    if item.isAnimated { startAnimationAdvanceTimer() }
                } else {
                    // Deferred autoplay: after a filter change, onAppear can run before
                    // `currentVisibleSceneId` is set. Retry shortly if this row became active.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        if isActive && isPlaying && !isRotating {
                            if player == nil { setupPlayer() }
                            player?.play()
                        }
                    }
                }
            }
            .onDisappear {
                cleanupPlayer()
                cancelAnimationAdvanceTimer()
            }
            .onReceive(NotificationCenter.default.publisher(for: .reelsPauseAllPlayers)) { _ in
                // Robust pause: when paging/scrolling starts, pause immediately even if
                // `currentVisibleSceneId` (and thus `isActive`) hasn't updated yet.
                player?.pause()
            }
            .onChange(of: isMuted) { _, newValue in
                player?.isMuted = newValue
            }
            .onChange(of: isActive) { _, newValue in
                if newValue {
                    if player == nil { setupPlayer() } else { refreshTimeObserver() }
                    if isPlaying && !isRotating { player?.play() }
                    onInteraction()
                    if item.isAnimated { startAnimationAdvanceTimer() }
                    // Deferred play: ensure player starts even if isPlaying binding
                    // hasn't propagated yet (e.g. after filter change resets state).
                    DispatchQueue.main.async {
                        if self.isActive && self.isPlaying && !self.isRotating {
                            self.player?.play()
                        }
                    }
                } else {
                    cleanupPlayer()
                    cancelAnimationAdvanceTimer()
                }
            }
            .onChange(of: tabManager.reelsContinuousPlay) { _, enabled in
                if item.isAnimated {
                    if enabled && isActive {
                        startAnimationAdvanceTimer()
                    } else {
                        cancelAnimationAdvanceTimer()
                    }
                }
            }
            .onChange(of: playTrigger) { _, _ in
                // Fired by autoSelectFirstItem after setting currentVisibleSceneId.
                // At this point isActive should be true for the correct item.
                guard isActive else { return }
                if player == nil { setupPlayer() }
                if isPlaying && !isRotating {
                    player?.play()
                }
            }
            .onChange(of: isRotating) { _, newValue in
                if !newValue && isActive && isPlaying {
                    player?.play()
                } else if newValue {
                    player?.pause()
                }
            }
    }

    @ViewBuilder
    private func applyOverlayModifiers<V: View>(_ content: V) -> some View {
        content
            .onChange(of: showRatingOverlay) { _, newValue in
                isMenuOpen = newValue || showTagsOverlay
            }
            .onChange(of: showTagsOverlay) { _, newValue in
                isMenuOpen = newValue || showRatingOverlay
            }
            .onChange(of: isPlaying) { _, playing in
                guard isActive else { return }
                if playing {
                    if !isRotating { player?.play() }
                } else {
                    player?.pause()
                }
            }
            .onReceive(scrubberState.$seekTarget) { target in
                guard let t = target else { return }
                seek(to: t)
                DispatchQueue.main.async {
                    if scrubberState.seekTarget != nil {
                        scrubberState.seekTarget = nil
                    }
                }
            }
            .onReceive(scrubberState.$seeking) { seeking in
                guard isActive else { return }
                if seeking {
                    player?.pause()
                } else if isPlaying {
                    player?.play()
                    onInteraction()
                }
            }
    }


    @ViewBuilder
    private func applyStashSyncModifiers<V: View>(_ content: V) -> some View {
        content
            .modifier(StashSyncManagerModifier(isActive: isActive, isPlaying: isPlaying, player: player))
    }

    

    @ViewBuilder
    private var mediaLayer: some View {
        ZoomableScrollView(isZoomed: $isZoomed, onTap: handleMediaTap, onLongPress: handleLongPress) {
            ZStack {
                Group {
                    if item.isAnimated {
                        CustomAsyncImage(url: item.videoURL) { loader in
                            if let data = loader.imageData, isAnimatedData(data) {
                                AnimatedWebView(data: data, fillMode: shouldFill)
                            } else if let img = loader.image {
                                img
                                    .resizable()
                                    .aspectRatio(contentMode: shouldFill ? .fill : .fit)
                            } else if loader.isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(.white)
                            }
                        }
                    } else if let player = player {
                        FullScreenVideoPlayer(player: player, videoGravity: shouldFill ? .resizeAspectFill : .resizeAspect)
                    } else {
                        thumbnailPlaceholder
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .focusable(false)
        .focusEffectDisabled()
    }

    @ViewBuilder
    private var thumbnailPlaceholder: some View {
        if let url = item.thumbnailURL {
            CustomAsyncImage(url: url) { loader in
                if let image = loader.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: shouldFill ? .fill : .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView().tint(.white)
                }
            }
        }
    }

    private func handleMediaTap(at location: CGPoint) {
        let screenHeight = UIScreen.main.bounds.height
        // Ignore taps in the top navigation area and bottom floating bar area
        if location.y > 0 && location.y < 120 { return }
        if location.y > 0 && location.y > screenHeight - 180 { return }
        
        guard !isMenuOpen else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isUIVisible.toggle()
        }
        onInteraction()
    }

    private func handleLongPress(_ isPressed: Bool) {
        guard !item.isAnimated, let player = player else { return }
        
        if isPressed {
            #if !os(tvOS)
            HapticManager.selection()
            #endif
            player.rate = 2.0
            withAnimation {
                isFastForwarding = true
            }
        } else {
            player.rate = 1.0
            withAnimation {
                isFastForwarding = false
            }
        }
        onInteraction()
    }

    @ViewBuilder
    private var fastForwardOverlay: some View {
        if isFastForwarding {
            VStack {
                Image(systemName: "chevron.right.2")
                    .font(.system(size: 32, weight: .black))
                    .foregroundColor(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    .background(Color.black.opacity(DesignTokens.Opacity.badge))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
                    .padding(.top, 130)
                Spacer()
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var playButtonOverlay: some View {
        if !item.isAnimated && !isPlaying && isUIVisible && !isUserScrolling {
            CenterPlayButton {
                isPlaying = true
                if !isRotating { player?.play() }
                onInteraction()
            }
        }
    }

    @ViewBuilder
    private var bottomBarOverlay: some View {
        if isUIVisible {
            bottomOverlay
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var bottomOverlay: some View {
        VStack(spacing: 0) {
            // Rating overlay (expands upward)
            if showRatingOverlay {
                    let rating = item.rating100 ?? 0
                    HStack {
                        StarRatingView(
                            rating100: rating,
                            isInteractive: true,
                            size: 28,
                            spacing: 10,
                            isVertical: false
                        ) { newRating in
                            onRatingChanged(newRating)
                            onInteraction()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    showRatingOverlay = false
                                }
                            }
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(Edge.Set.horizontal, 16)
                    .background(Color.black.opacity(DesignTokens.Opacity.badge))
                    .clipShape(Capsule())
                    .padding(Edge.Set.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                

                // 3. Full-width progress bar moved to reelsFloatingBar
            }
        .sheet(isPresented: $showStashSyncSheet) {
            #if !os(tvOS)
            StashSyncSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            #endif
        }
    }
    

    @ViewBuilder
    private func performerLabel(for item: ReelsView.ReelItemData) -> some View {

        if let performer = item.performers.first {
            Button(action: { onPerformerTap(performer) }) {
                Text(performer.name)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func titleLabel(for item: ReelsView.ReelItemData) -> some View {
        if let title = item.title, !title.isEmpty {
            Group {
                if let scene = item.underlyingScene {
                    NavigationLink(destination: SceneDetailView(scene: scene)) {
                        titleText(title, item: item)
                    }
                    .buttonStyle(.plain)
                } else {
                    titleText(title, item: item)
                }
            }
        }
    }

    @ViewBuilder
    private func titleText(_ title: String, item: ReelsView.ReelItemData) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
                .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
            
            // Download Indicator
            let sceneId: String? = {
                if case .scene(let s) = item { return s.id }
                if case .marker(let m) = item { return m.scene?.id }
                if case .preview(let s) = item { return s.id }
                return nil
            }()
            
            if let sId = sceneId, DownloadManager.shared.isDownloaded(id: sId) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .padding(3)
                    .background(Color.green)
                    .clipShape(Circle())
                    .shadow(radius: 2)
            }
        }
    }
    
    
    func setupPlayer() {
        // Animations don't need AVPlayer
        guard !item.isAnimated else { return }

        playerSetupGeneration &+= 1
        let generation = playerSetupGeneration
        
        guard item.sceneID != nil else {
            if let url = item.videoURL { initPlayer(with: url, generation: generation) }
            return
        }
        
        // 1. Start with the immediate URL (legacy or cached) for instant playback
        if let url = item.videoURL {
            initPlayer(with: url, generation: generation)
        }
        
        // 2. Fetch best stream (MP4/HLS) only for the **active** reel — never for
        //    rows that only flashed past (those no longer call `setupPlayer`).
        updateBestStream(generation: generation)
    }
    
    private func updateBestStream(generation: Int) {
        guard let sid = item.sceneID else { return }
        
        // Optimization: If we are already using a local file, don't bother fetching streams
        // Local files are already the "best" possible quality/performance.
        if let currentURL = item.videoURL, !currentURL.absoluteString.hasPrefix("http") {
            print("📂 Reels: Scene \(sid) is local, skipping best stream fetch.")
            return
        }
        
        // Background fetch for the "best" stream (MP4/HLS)
        viewModel.fetchSceneStreams(sceneId: sid) { streams in
            guard generation == self.playerSetupGeneration else { return }
            guard !streams.isEmpty else { return }
            
            let quality = ServerConfigManager.shared.activeConfig?.reelsQuality ?? .sd
            
            // Re-evaluate the best URL now that we have the full stream list
            let bestURL: URL?
            switch item {
            case .scene(let s):
                bestURL = s.withStreams(streams).bestStream(for: quality)
            case .marker(let m):
                bestURL = m.scene?.withStreams(streams).bestStream(for: quality)
            case .clip:
                bestURL = nil  // Clips don't use scene streams
            case .preview(let s):
                bestURL = s.previewURL
            }
            
            if let targetURL = bestURL {
                // Only switch if the target is significantly different from current (e.g. not just apikey diff)
                let currentURL = (player?.currentItem?.asset as? AVURLAsset)?.url
                if currentURL?.path != targetURL.path {
                    // Priority: Upgrade to MP4 if current is legacy, or better HLS if current is HLS
                    self.initPlayer(with: targetURL, generation: generation)
                }
            }
        }
    }
    
    private func initPlayer(with streamURL: URL, generation: Int) {
        guard generation == playerSetupGeneration else { return }
        let headers = ["ApiKey": ServerConfigManager.shared.activeConfig?.secureApiKey ?? ""]
        let authenticatedURL = signedURL(streamURL) ?? streamURL
        let asset = AVURLAsset(url: authenticatedURL, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let newItem = AVPlayerItem(asset: asset)
        
        let startTime = item.startTime
        
        if let existingPlayer = self.player {
            // Smooth Upgrade: Preserve state for active items
            let wasPlaying = existingPlayer.timeControlStatus == .playing
            let currentTime = existingPlayer.currentTime()
            
            // Reuse existing player for smoothness and to prevent VideoPlayer re-renders
            if let observer = timeObserver {
                existingPlayer.removeTimeObserver(observer)
                self.timeObserver = nil
            }
            NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: existingPlayer.currentItem)
            
            existingPlayer.replaceCurrentItem(with: newItem)
            
            // Resume playback if this is the active item and the user intends to play.
            // Use isPlaying (binding = user intent) in addition to wasPlaying (AVPlayer state)
            // because the player may still be buffering (.waitingToPlayAtSpecifiedRate)
            // when the stream upgrade arrives.
            if isActive && (wasPlaying || isPlaying) {
                existingPlayer.seek(to: currentTime, toleranceBefore: .zero, toleranceAfter: .zero)
                existingPlayer.play()
            }
        } else {
            // First time player creation
            self.player = createPlayer(for: streamURL) // createPlayer handles AVAudioSession
        }
        
        guard let player = self.player else { return }
        ReelsPlayerRegistry.register(player)
        
        player.isMuted = isMuted
        if isPlaying && isActive && !isRotating { 
            player.play() 
        } else {
            player.pause()
        }
        
        if startTime > 0 {
            player.seek(to: CMTime(seconds: startTime, preferredTimescale: 600))
        }
        
        // Initial duration guess from model
        if let d = item.duration, d > 0 {
            if isActive { scrubberState.duration = d }
        }
        
        // Loop or Auto-Advance (Scenes and Clips)
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { _ in
            if TabManager.shared.reelsContinuousPlay {
                self.onVideoEnded()
                return
            }
            if case .scene = self.item {
                if startTime > 0 {
                    player.seek(to: CMTime(seconds: startTime, preferredTimescale: 600))
                } else {
                    player.seek(to: .zero)
                }
                player.play()
                incrementPlayCount()
            } else if case .clip = self.item {
                player.seek(to: .zero)
                player.play()
            } else if case .marker = self.item {
                let start = self.item.startTime
                player.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                player.play()
            } else if case .preview = self.item {
                player.seek(to: .zero)
                player.play()
            }
        }
        
        // Time Observer
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak player] time in
            guard let player = player else { return }
            if self.isActive && !self.scrubberState.seeking {
                self.scrubberState.time = time.seconds
            }
            
            // Media duration update
            if self.isActive, let d = player.currentItem?.duration.seconds, d > 0, !d.isNaN {
                self.scrubberState.duration = d
            }
        }
        
        // Increment play count (initial)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            incrementPlayCount()
        }
    }
    
    func incrementPlayCount() {
        if let currentCount = item.playCount {
            onPlayCountChanged(currentCount + 1)
        }
    }
    
    func cleanupPlayer() {
        playerSetupGeneration &+= 1
        player?.pause()
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        
        // Remove end of time observer
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: player?.currentItem)
        
        // Aggressively release resources
        if let p = player {
            ReelsPlayerRegistry.unregister(p)
            p.replaceCurrentItem(with: nil)
        }
        player = nil
        print("🎬 Reels: Player cleaned up for item \(item.id)")
    }

    /// Re-creates the periodic time observer so it captures the current `self`
    /// (with the correct `currentTime` / `duration` bindings). Called when the
    /// item becomes the active (visible) one after already having a player.
    func refreshTimeObserver() {
        if let old = timeObserver {
            player?.removeTimeObserver(old)
            timeObserver = nil
        }
        guard let player = player else { return }
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak player] time in
            guard let player = player else { return }
            if self.isActive && !self.scrubberState.seeking {
                self.scrubberState.time = time.seconds
            }
            if self.isActive, let d = player.currentItem?.duration.seconds, d > 0, !d.isNaN {
                self.scrubberState.duration = d
            }
        }
    }

    func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime)
    }

    private func startAnimationAdvanceTimer() {
        // Only advance if continuous play is enabled
        guard tabManager.reelsContinuousPlay else { return }
        cancelAnimationAdvanceTimer()
        let duration = item.duration ?? 5.0
        animationAdvanceTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { _ in
            onVideoEnded()
        }
    }

    private func cancelAnimationAdvanceTimer() {
        animationAdvanceTimer?.invalidate()
        animationAdvanceTimer = nil
    }
}

struct StashSyncManagerModifier: ViewModifier {
    let isActive: Bool
    let isPlaying: Bool
    let player: AVPlayer?
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                initialSync()
            }
            .onChange(of: isActive) { _, active in
                if active { initialSync() }
            }
            .onChange(of: StashSyncManager.shared.isActive) { _, active in
                if active { initialSync() }
            }
            .onChange(of: player?.currentItem) { _, newItem in
                if StashSyncManager.shared.isActive {
                                        ensureVideoAnalysis(for: newItem)
                }
            }
            .onChange(of: HandyManager.shared.isStashSyncMode) { _, isStash in
                if isStash && isActive { 
                                        ensureVideoAnalysis(for: player?.currentItem)
                    StashSyncManager.shared.isActive = true
                    if isPlaying { HandyManager.shared.play(at: player?.currentTime().seconds ?? 0) }
                } else if !isStash {
                    checkAndStopStashSync()
                }
            }
            .onChange(of: ButtplugManager.shared.isStashSyncMode) { _, isStash in
                if isStash && isActive { 
                                        ensureVideoAnalysis(for: player?.currentItem)
                    StashSyncManager.shared.isActive = true
                    if isPlaying { ButtplugManager.shared.play(at: player?.currentTime().seconds ?? 0) }
                } else if !isStash {
                    checkAndStopStashSync()
                }
            }
            .onChange(of: LoveSpouseManager.shared.isStashSyncMode) { _, isStash in
                if isStash && isActive { 
                                        ensureVideoAnalysis(for: player?.currentItem)
                    StashSyncManager.shared.isActive = true
                    if isPlaying { LoveSpouseManager.shared.play(at: player?.currentTime().seconds ?? 0) }
                } else if !isStash {
                    checkAndStopStashSync()
                }
            }
            .onChange(of: isPlaying) { _, playing in
                if StashSyncManager.shared.isActive && isActive {
                    let currentTime = player?.currentTime().seconds ?? 0
                    if playing {
                        if HandyManager.shared.isStashSyncMode { HandyManager.shared.play(at: currentTime) }
                        if ButtplugManager.shared.isStashSyncMode { ButtplugManager.shared.play(at: currentTime) }
                        if LoveSpouseManager.shared.isStashSyncMode { LoveSpouseManager.shared.play(at: currentTime) }
                    } else {
                        if HandyManager.shared.isStashSyncMode { HandyManager.shared.pause() }
                        if ButtplugManager.shared.isStashSyncMode { ButtplugManager.shared.pause() }
                        if LoveSpouseManager.shared.isStashSyncMode { LoveSpouseManager.shared.pause() }
                    }
                }
            }
            .onChange(of: isActive) { _, active in
                if active && StashSyncManager.shared.isActive {
                    let currentTime = player?.currentTime().seconds ?? 0
                    if isPlaying {
                        if HandyManager.shared.isStashSyncMode { HandyManager.shared.play(at: currentTime) }
                        if ButtplugManager.shared.isStashSyncMode { ButtplugManager.shared.play(at: currentTime) }
                        if LoveSpouseManager.shared.isStashSyncMode { LoveSpouseManager.shared.play(at: currentTime) }
                    } else {
                        if HandyManager.shared.isStashSyncMode { HandyManager.shared.pause() }
                        if ButtplugManager.shared.isStashSyncMode { ButtplugManager.shared.pause() }
                        if LoveSpouseManager.shared.isStashSyncMode { LoveSpouseManager.shared.pause() }
                    }
                }
            }
    }
    

    private func initialSync() {
        guard isActive && StashSyncManager.shared.isActive else {
            print("🎬 ReelsView: initialSync check failed - isActive: \(isActive), StashSync: \(StashSyncManager.shared.isActive)")
            return
        }
        print("🎬 ReelsView: Performing initial sync for manager states...")
                ensureVideoAnalysis(for: player?.currentItem)
        
        if isPlaying {
            let currentTime = player?.currentTime().seconds ?? 0
            print("🎬 ReelsView: Resuming StashSync signals at \(currentTime)s")
            if HandyManager.shared.isStashSyncMode { HandyManager.shared.play(at: currentTime) }
            if ButtplugManager.shared.isStashSyncMode { ButtplugManager.shared.play(at: currentTime) }
            if LoveSpouseManager.shared.isStashSyncMode { LoveSpouseManager.shared.play(at: currentTime) }
        }
    }
    // MARK: - Helper Methods
    
    

    
    private func ensureVideoAnalysis(for item: AVPlayerItem?) {
        guard let item = item else { return }
        if HandyManager.shared.isStashSyncMode || ButtplugManager.shared.isStashSyncMode || LoveSpouseManager.shared.isStashSyncMode {
            print("🎬 ReelsView: Ensuring Video Analysis is setup for current item")
            StashVideoSyncManager.shared.setup(for: item)
            StashVideoSyncManager.shared.isActive = true
        }
    }
    
    private func checkAndStopStashSync() {
        if !HandyManager.shared.isStashSyncMode && 
           !ButtplugManager.shared.isStashSyncMode && 
           !LoveSpouseManager.shared.isStashSyncMode {
            StashSyncManager.shared.isActive = false
                        checkAndStopVideoAnalysis()
        }
    }
    
    private func checkAndStopVideoAnalysis() {
        if !ButtplugManager.shared.isStashSyncMode && !LoveSpouseManager.shared.isStashSyncMode {
            StashVideoSyncManager.shared.stop()
        }
    }
    
}

// MARK: - Scrubber Isolation
class ScrubberState: ObservableObject {
    @Published var time: Double = 0.0
    @Published var duration: Double = 1.0
    @Published var seeking: Bool = false
    @Published var seekTarget: Double? = nil
}

struct IsolatedScrubberBar: View {
    @ObservedObject var state: ScrubberState
    var isUIVisible: Bool
    
    var body: some View {
        CustomVideoScrubber(
            value: Binding(
                get: { state.time },
                set: { val in
                    state.time = val
                    state.seekTarget = val
                }
            ),
            total: state.duration,
            onEditingChanged: { editing in
                state.seeking = editing
            }
        )
        // Keep a bit more space below the scrubber so it sits ~5px higher.
        .padding(.bottom, 11)
        .colorScheme(.dark)
        .opacity(isUIVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: isUIVisible)
    }
}
#endif
