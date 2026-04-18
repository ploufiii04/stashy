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
    @State private var lastMainListPosition: String?
    @State private var currentItemIsPlaying = true
    @State private var currentItemShowRatingOverlay = false
    @State private var showStashSyncSheet = false
    @State private var currentItemTime: Double = 0.0
    @State private var currentItemDuration: Double = 1.0
    @State private var currentItemSeeking = false
    @State private var currentItemSeekTarget: Double? = nil

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
        
        var icon: String {
            switch self {
            case .scenes: return "film"
            case .markers: return "bookmark.fill"
            case .clips: return "photo.on.rectangle.angled"
            case .previews: return "play.rectangle.on.rectangle.fill"
            }
        }
        
        var toModeType: ReelsModeType {
            switch self {
            case .scenes: return .scenes
            case .markers: return .markers
            case .clips: return .clips
            case .previews: return .previews
            }
        }
        
        init(from type: ReelsModeType) {
            switch type {
            case .scenes: self = .scenes
            case .markers: self = .markers
            case .clips: self = .clips
            case .previews: self = .previews
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
            switch self {
            case .scene(let s): return s.title
            case .marker(let m): return m.scene?.title
            case .clip(let c): return c.title
            case .preview(let s): return s.title
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
        }
    }

    

    private func applySettings(sortBy: StashDBViewModel.SceneSortOption? = nil, markerSortBy: StashDBViewModel.SceneMarkerSortOption? = nil, clipSortBy: StashDBViewModel.ImageSortOption? = nil, previewSortBy: StashDBViewModel.SceneSortOption? = nil, filter: StashDBViewModel.SavedFilter?, clipFilter: StashDBViewModel.SavedFilter? = nil, previewFilter: StashDBViewModel.SavedFilter? = nil, performer: ScenePerformer? = nil, tags: [Tag] = [], mode: ReelsMode? = nil, clearClipFilter: Bool = false, clearPreviewFilter: Bool = false) {
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
                currentVisibleSceneId = nil // Start at top for filter results
            } else if !isClearingFilters {
                // Already filtered, just reset for new filter results
                currentVisibleSceneId = nil
            }
        }

        // Update local state and handle random re-roll
        // Don't override a just-restored position with nil
        if let sortBy = sortBy {
            if sortBy == .random && selectedSortOption == .random && reelsMode == .scenes {
                viewModel.refreshRandomSeed()
            }
            selectedSortOption = sortBy
            if restoredPosition == nil { currentVisibleSceneId = nil }
        }

        if let markerSortBy = markerSortBy {
            if markerSortBy == .random && selectedMarkerSortOption == .random && reelsMode == .markers {
                viewModel.refreshRandomSeed()
            }
            selectedMarkerSortOption = markerSortBy
            if restoredPosition == nil { currentVisibleSceneId = nil }
        }

        if let clipSortBy = clipSortBy {
            if clipSortBy == .random && selectedClipSortOption == .random && reelsMode == .clips {
                viewModel.refreshRandomSeed()
            }
            selectedClipSortOption = clipSortBy
            if restoredPosition == nil { currentVisibleSceneId = nil }
        }

        if let previewSortBy = previewSortBy {
            if previewSortBy == .random && selectedSortOption == .random && reelsMode == .previews {
                viewModel.refreshRandomSeed()
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

        switch reelsMode {
        case .scenes:
            viewModel.fetchScenes(sortBy: selectedSortOption, filter: mergedFilter)
        case .markers:
            viewModel.fetchSceneMarkers(sortBy: selectedMarkerSortOption, filter: mergedFilter)
        case .clips:
            viewModel.fetchClips(sortBy: selectedClipSortOption, filter: mergedClipFilter, isInitialLoad: true)
        case .previews:
            viewModel.fetchPreviews(sortBy: selectedSortOption, isInitialLoad: true, filter: mergedPreviewFilter)
        }
    }
    
    private func autoSelectFirstItem() {
        // Only auto-select if nothing is selected OR if the selected ID belongs to another mode
        let currentPrefix = currentVisibleSceneId?.split(separator: "-").first.map(String.init)
        let expectedPrefix: String
        switch reelsMode {
        case .scenes: expectedPrefix = "scene"
        case .markers: expectedPrefix = "marker"
        case .clips: expectedPrefix = "clip"
        case .previews: expectedPrefix = "preview"
        }

        // Only auto-select if nothing is selected AND we aren't restoring a position
        if (currentVisibleSceneId == nil || currentPrefix != expectedPrefix) && lastMainListPosition == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                switch reelsMode {
                case .scenes:
                    if let firstId = viewModel.scenes.first?.id {
                        currentVisibleSceneId = "scene-\(firstId)"
                    }
                case .markers:
                    if let firstId = viewModel.sceneMarkers.first?.id {
                        currentVisibleSceneId = "marker-\(firstId)"
                    }
                case .clips:
                    if let firstId = viewModel.clips.first?.id {
                        currentVisibleSceneId = "clip-\(firstId)"
                    }
                case .previews:
                    if let firstId = viewModel.previews.first?.id {
                        currentVisibleSceneId = "preview-\(firstId)"
                    }
                }
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
        }
    }

    var body: some View {
        premiumContent
    }


    @ViewBuilder
    private var premiumContent: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            let isLoading = viewModel.isLoading && isListEmpty

            if isLoading {
                loadingStateView
            } else if isListEmpty && viewModel.errorMessage != nil {
                errorStateView
            } else {
                reelsListView()
            }
        }
        .ignoresSafeArea(.all)
        .navigationBarHidden(true)
        .safeAreaInset(edge: .top, spacing: 0) {
            reelsNavBar
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                reelsInfoOverlay
                reelsCapsulesBar
            }
        }
        .toolbar(isUIVisible ? .visible : .hidden, for: .tabBar)
        .sheet(isPresented: $showStashSyncSheet) {
            #if !os(tvOS)
            StashSyncSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            #endif
        }
        .onChange(of: reelsMode) { _, newValue in handleModeChange(newValue) }
        .onChange(of: currentVisibleSceneId) { _, _ in
            currentItemIsPlaying = true
            currentItemShowRatingOverlay = false
            currentItemTime = 0.0
            currentItemDuration = 1.0
            currentItemSeeking = false
            currentItemSeekTarget = nil
        }
        .onChange(of: viewModel.scenes.first?.id) { _, _ in autoSelectFirstItem() }
        .onChange(of: viewModel.sceneMarkers.first?.id) { _, _ in autoSelectFirstItem() }
        .onChange(of: viewModel.clips.first?.id) { _, _ in autoSelectFirstItem() }
        .onChange(of: viewModel.previews.first?.id) { _, _ in autoSelectFirstItem() }
        .onAppear { handleOnAppear() }
        .onChange(of: isMenuOpen) { _, _ in }
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
                }
            }
        }
        .onChange(of: viewModel.savedFilters) { _, newValue in
            // Backfill selectedFilter with the default if filters just arrived and we still have no base filter.
            // This ensures removing a performer/tag pill reverts to the default rather than nil.
            if selectedFilter == nil && reelsMode != .clips && !newValue.isEmpty {
                if let defId = TabManager.shared.getDefaultFilterId(for: .reels), let filter = newValue[defId] {
                    selectedFilter = filter
                }
            }

            // Only apply initial load if we are empty and no specific navigation context was provided
            let isCurrentlyEmpty: Bool = {
                switch reelsMode {
                case .scenes: return viewModel.scenes.isEmpty
                case .markers: return viewModel.sceneMarkers.isEmpty
                case .clips: return viewModel.clips.isEmpty
                case .previews: return viewModel.previews.isEmpty
                }
            }()

            let noCriteriaSet = (reelsMode == .clips ? selectedClipFilter == nil : selectedFilter == nil) && selectedPerformer == nil && selectedTags.isEmpty

            if noCriteriaSet && isCurrentlyEmpty && !newValue.isEmpty {
                print("✅ ReelsView: Saved filters arrived, triggering initial load...")
                let defaultId: String? = {
                    switch reelsMode {
                    case .scenes: return TabManager.shared.getDefaultFilterId(for: .reels)
                    case .markers: return TabManager.shared.getDefaultMarkerFilterId(for: .reels)
                    case .clips: return TabManager.shared.getDefaultClipFilterId(for: .reels)
                    case .previews: return TabManager.shared.getDefaultPreviewFilterId(for: .reels)
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
                    }
                } else {
                    // No default filter, just load unfiltered with saved sort
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
                    }
                }
            }
        }
    }

    private func handleOnAppear() {
        UIApplication.shared.isIdleTimerDisabled = true
        
        // Audio Optimization: Ensure session is active once for Reels
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("🎬 Reels: Audio setup error: \(error)")
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
        
        autoSelectFirstItem()
        
        // 1. Initialize reelsMode ONLY if current mode is disabled in settings
        let enabledTypes = tabManager.enabledReelsModes
        if !enabledTypes.contains(reelsMode.toModeType) {
            if let first = enabledTypes.first {
                reelsMode = ReelsMode(from: first)
            }
        }
        
        // Determine initial state from coordinator
        let initialPerformer: ScenePerformer? = coordinator.reelsPerformer
        let initialTags: [Tag] = coordinator.reelsTags
        
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

            applySettings(sortBy: savedSort, filter: baseFilter, performer: initialPerformer, tags: initialTags)
        } else {
            let isCurrentlyEmpty: Bool = {
                switch reelsMode {
                case .scenes: return viewModel.scenes.isEmpty
                case .markers: return viewModel.sceneMarkers.isEmpty
                case .clips: return viewModel.clips.isEmpty
                case .previews: return viewModel.previews.isEmpty
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
                    }
                }
            }
        }
    }

    private func handleModeChange(_ newValue: ReelsMode) {
        switch newValue {
        case .markers:
            if let defaultId = TabManager.shared.getDefaultMarkerFilterId(for: .reels),
               let filter = viewModel.savedFilters[defaultId] {
                applySettings(filter: filter, performer: selectedPerformer, tags: selectedTags, mode: newValue)
            } else {
                applySettings(filter: nil, performer: selectedPerformer, tags: selectedTags, mode: newValue)
            }
        case .scenes:
            if let defaultId = TabManager.shared.getDefaultFilterId(for: .reels),
               let filter = viewModel.savedFilters[defaultId] {
                applySettings(filter: filter, performer: selectedPerformer, tags: selectedTags, mode: newValue)
            } else {
                applySettings(filter: nil, performer: selectedPerformer, tags: selectedTags, mode: newValue)
            }
        case .clips:
            if let defaultId = TabManager.shared.getDefaultClipFilterId(for: .reels),
               let filter = viewModel.savedFilters[defaultId] {
                applySettings(filter: nil, clipFilter: filter, performer: selectedPerformer, tags: selectedTags, mode: newValue)
            } else {
                // Maintain current selectedClipFilter when switching modes if no default
                applySettings(filter: nil, clipFilter: selectedClipFilter, performer: selectedPerformer, tags: selectedTags, mode: newValue)
            }
        case .previews:
            let savedPreviewSort = StashDBViewModel.SceneSortOption(rawValue: TabManager.shared.getReelsDefaultSort(for: .previews) ?? "") ?? .random
            if let defaultId = TabManager.shared.getDefaultPreviewFilterId(for: .reels),
               let filter = viewModel.savedFilters[defaultId] {
                applySettings(previewSortBy: savedPreviewSort, filter: nil, previewFilter: filter, performer: selectedPerformer, tags: selectedTags, mode: newValue)
            } else {
                applySettings(previewSortBy: savedPreviewSort, filter: nil, previewFilter: selectedPreviewFilter, performer: selectedPerformer, tags: selectedTags, mode: newValue)
            }
        }
    }

    @ViewBuilder
    private var loadingStateView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.white)
            Text("Loading StashTok...")
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
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
            isActive: item.id == currentVisibleSceneId,
            isMuted: $isMuted,
            isUIVisible: $isUIVisible,
            isPlaying: item.id == currentVisibleSceneId ? $currentItemIsPlaying : .constant(true),
            showRatingOverlay: item.id == currentVisibleSceneId ? $currentItemShowRatingOverlay : .constant(false),
            currentTime: item.id == currentVisibleSceneId ? $currentItemTime : .constant(0.0),
            duration: item.id == currentVisibleSceneId ? $currentItemDuration : .constant(1.0),
            isSeeking: item.id == currentVisibleSceneId ? $currentItemSeeking : .constant(false),
            seekTarget: item.id == currentVisibleSceneId ? $currentItemSeekTarget : .constant(nil),
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
                }
            }
        }
    }

    @ViewBuilder
    private func reelsListView() -> some View {
        let items = currentReelItems
        
        ScrollView(.vertical, showsIndicators: false) {
            ScrollViewReader { proxy in
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        reelItemRow(index: index, item: item, itemCount: items.count)
                    }
                }
                .scrollTargetLayout()
            }
        }
        .focusable(false)
        .focusEffectDisabled()
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: scrollPositionBinding)
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .onScrollPhaseChange { _, _ in }
        .background(Color.black)
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            // Just update state for UI adjustments, no force rebuilds
            withAnimation(.easeInOut(duration: 0.3)) {
                isRotating = true
            }
            
            // Allow system rotation animation to complete before un-pausing
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation {
                    isRotating = false
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
                ForEach(enabledModes, id: \.self) { mode in
                    let isActive = mode == reelsMode
                    Button(action: { reelsMode = mode }) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(isActive ? .white : .white.opacity(0.5))
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
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)

            // Active performer / tag pills
            let hasFilters = selectedPerformer != nil || !selectedTags.isEmpty
            if hasFilters {
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
                .padding(.bottom, 6)
            }

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
        let isVideo = currentItem?.videoURL != nil && !(currentItem?.isAnimated ?? true)

        HStack(spacing: 8) {
            // Left capsule (fixed): sort + filter
            HStack(spacing: 16) {
                sortMenu.simultaneousGesture(TapGesture().onEnded { isMenuOpen = true })
                filterMenu.simultaneousGesture(TapGesture().onEnded { isMenuOpen = true })
            }
            .font(.system(size: 17))
            .frame(width: 88, height: 36)
            .background(Capsule().fill(.ultraThinMaterial).shadow(color: .black.opacity(0.3), radius: 6, y: 2))
            .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))

            // Middle capsule: o-counter left, stars + scene link right
            HStack(spacing: 8) {
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
                }
                .buttonStyle(.plain)
                .fixedSize()

                Spacer()

                let rating = currentItem?.rating100 ?? 0
                if let item = currentItem {
                    StarRatingView(rating100: rating, isInteractive: true, size: 14, spacing: 3, isVertical: false) { newRating in
                        handleRatingChange(item: item, newRating: newRating)
                    }
                    .fixedSize()
                }


            }
            .font(.system(size: 17))
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .padding(.horizontal, 16)
            .background(Capsule().fill(.ultraThinMaterial).shadow(color: .black.opacity(0.3), radius: 6, y: 2))
            .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))

            // Right capsule (fixed): mute + play/pause (videos only)
            if isVideo {
                HStack(spacing: 16) {
                    Button { isMuted.toggle() } label: {
                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .foregroundColor(.white)
                    }
                    Button { currentItemIsPlaying.toggle() } label: {
                        Image(systemName: currentItemIsPlaying ? "pause.fill" : "play.fill")
                            .foregroundColor(.white)
                    }
                }
                .font(.system(size: 17))
                .frame(width: 88, height: 36)
                .background(Capsule().fill(.ultraThinMaterial).shadow(color: .black.opacity(0.3), radius: 6, y: 2))
                .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .colorScheme(.dark)
        .opacity(isUIVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: isUIVisible)
    }

    /// Info + scrubber overlay, positioned just above the capsule bar
    @ViewBuilder
    private var reelsInfoOverlay: some View {
        let currentItem = currentReelItems.first(where: { $0.id == currentVisibleSceneId })
        VStack(alignment: .leading, spacing: 0) {
            if let item = currentItem {
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
                    .padding(.horizontal, 20)

                    // Hashtags
                    let tags = item.tags
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
                            .padding(.horizontal, 20)
                        }
                        .frame(height: 20)
                    }
                }

                // Scrubber — no horizontal padding
                if !item.isAnimated {
                    CustomVideoScrubber(
                        value: Binding(
                            get: { currentItemTime },
                            set: { val in
                                currentItemTime = val
                                currentItemSeekTarget = val
                            }
                        ),
                        total: currentItemDuration,
                        onEditingChanged: { editing in
                            currentItemSeeking = editing
                        }
                    )
                    .padding(.top, 0)
                    .padding(.bottom, 6)
                }
            }
        }
        // Sit directly above the capsule bar
        .colorScheme(.dark)
        .opacity(isUIVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: isUIVisible)
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
                        .simultaneousGesture(TapGesture().onEnded { isMenuOpen = true })
                    sortMenu
                        .simultaneousGesture(TapGesture().onEnded { isMenuOpen = true })
                    filterMenu
                        .simultaneousGesture(TapGesture().onEnded { isMenuOpen = true })
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
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down.circle")
                .foregroundColor(.white)
        }
    }

    @ViewBuilder
    private var sceneSortOptions: some View {
        // Random
        Button(action: { applySettings(sortBy: .random, filter: selectedFilter, performer: selectedPerformer, tags: selectedTags) }) {
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
        Button(action: { applySettings(markerSortBy: .random, filter: selectedFilter, performer: selectedPerformer, tags: selectedTags) }) {
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
        Button(action: { applySettings(previewSortBy: .random, filter: selectedFilter, previewFilter: selectedPreviewFilter, performer: selectedPerformer, tags: selectedTags) }) {
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
        Button(action: { applySettings(clipSortBy: .random, filter: nil, clipFilter: selectedClipFilter, performer: selectedPerformer, tags: selectedTags) }) {
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
            Image(systemName: hasActiveFilter ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                .foregroundColor(hasActiveFilter ? appearanceManager.tintColor : .white)
        }
    }
}

struct ReelItemView: View {
    let item: ReelsView.ReelItemData
    let isActive: Bool
    @State private var player: AVPlayer?
    @State private var looper: Any?
    @State private var animationAdvanceTimer: Timer?
    @ObservedObject var tabManager = TabManager.shared
    
    // Playback State
    @Binding var isMuted: Bool
    @Binding var isUIVisible: Bool
    @Binding var isPlaying: Bool
    @Binding var showRatingOverlay: Bool
    @Binding var currentTime: Double
    @Binding var duration: Double
    @Binding var isSeeking: Bool
    @Binding var seekTarget: Double?
    var onPerformerTap: (ScenePerformer) -> Void
    var onTagTap: (Tag) -> Void
    var onRatingChanged: (Int?) -> Void
    var onOCounterChanged: (Int) -> Void
    var onPlayCountChanged: (Int) -> Void
    var onVideoEnded: () -> Void = {}
    @ObservedObject var viewModel: StashDBViewModel
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @State private var timeObserver: Any?
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
                setupPlayer()
                if isActive {
                    onInteraction()
                    if item.isAnimated { startAnimationAdvanceTimer() }
                }
            }
            .onDisappear {
                cleanupPlayer()
                cancelAnimationAdvanceTimer()
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
            .onChange(of: seekTarget) { _, target in
                guard let t = target else { return }
                seek(to: t)
                seekTarget = nil
            }
            .onChange(of: isSeeking) { _, seeking in
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

    private func handleMediaTap() {
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
        if !item.isAnimated && !isPlaying && isUIVisible {
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
        
        guard item.sceneID != nil else {
            if let url = item.videoURL { initPlayer(with: url) }
            return
        }
        
        // 1. Start with the immediate URL (legacy or cached) for instant playback
        if let url = item.videoURL {
            initPlayer(with: url)
        }
        
        // 2. Performance: Fetch best stream immediately (optimized for preloading)
        updateBestStream()
    }
    
    private func updateBestStream() {
        guard let sid = item.sceneID else { return }
        
        // Optimization: If we are already using a local file, don't bother fetching streams
        // Local files are already the "best" possible quality/performance.
        if let currentURL = item.videoURL, !currentURL.absoluteString.hasPrefix("http") {
            print("📂 Reels: Scene \(sid) is local, skipping best stream fetch.")
            return
        }
        
        // Background fetch for the "best" stream (MP4/HLS)
        viewModel.fetchSceneStreams(sceneId: sid) { streams in
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
                    initPlayer(with: targetURL)
                }
            }
        }
    }
    
    private func initPlayer(with streamURL: URL) {
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
            
            // If this is the active item and it was already playing, ensure it continues smoothly
            if isActive && wasPlaying {
                existingPlayer.seek(to: currentTime, toleranceBefore: .zero, toleranceAfter: .zero)
                existingPlayer.play()
            }
        } else {
            // First time player creation
            self.player = createPlayer(for: streamURL) // createPlayer handles AVAudioSession
        }
        
        guard let player = self.player else { return }
        
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
            self.duration = d
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
            if !self.isSeeking {
                self.currentTime = time.seconds
            }
            
            // Media duration update
            if let d = player.currentItem?.duration.seconds, d > 0, !d.isNaN {
                self.duration = d
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
        player?.pause()
        if let timeObserver = timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        
        // Remove end of time observer
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: player?.currentItem)
        
        // Aggressively release resources
        player?.replaceCurrentItem(with: nil)
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
            if !self.isSeeking {
                self.currentTime = time.seconds
            }
            if let d = player.currentItem?.duration.seconds, d > 0, !d.isNaN {
                self.duration = d
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
#endif
