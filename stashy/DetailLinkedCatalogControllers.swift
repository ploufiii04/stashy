//
//  DetailLinkedCatalogControllers.swift
//  stashy
//
//  Reusable filter/sort + preset state for performer/tag/studio lists embedded in detail screens
//  (studio → performers/tags/sub-studios, performer → studios/tags, group → …, tag → studios).
//

#if !os(tvOS)
import Combine
import SwiftUI

// MARK: - Performers (scoped to studio / tag / group)

enum DetailLinkedPerformersScope: Equatable {
    case studio(String)
    case tag(String)
    case group(String)
}

@MainActor
final class DetailLinkedPerformersFilterModel: ObservableObject {
    let scope: DetailLinkedPerformersScope

    @Published var showFilterSortSheet = false
    @Published var catalogPresetRowSelection = ""
    @Published var localCatalogPresets: [PerformerListLiveFilterPreset] = PerformerListLiveFilterPresetStore.loadPresets()
    @Published var showSaveAsCatalogPresetAlert = false
    @Published var catalogPresetNameInput = ""
    @Published var showRenameCatalogPresetAlert = false
    @Published var renameCatalogPresetInput = ""
    @Published var showDeleteCatalogPresetAlert = false

    @Published var selectedSortOption: StashDBViewModel.PerformerSortOption
    @Published var selectedFilter: StashDBViewModel.SavedFilter?

    @Published var liveFilterAgeRange: String?
    @Published var liveFilterHairColor: String?
    @Published var liveFilterGender: String?
    @Published var liveFilterCountry: String?
    @Published var liveFilterImplants: Bool?
    @Published var liveFilterFavorite: Bool?
    @Published var liveFilterMissingField: String?

    init(scope: DetailLinkedPerformersScope, initialSort: StashDBViewModel.PerformerSortOption = .nameAsc) {
        self.scope = scope
        self.selectedSortOption = initialSort
        self.selectedFilter = nil
    }

    private var isLiveFilterActive: Bool {
        liveFilterAgeRange != nil || liveFilterHairColor != nil || liveFilterGender != nil
            || liveFilterCountry != nil || liveFilterImplants != nil || liveFilterFavorite != nil
            || liveFilterMissingField != nil
    }

    var catalogFilterSortFABActive: Bool {
        selectedFilter != nil || isLiveFilterActive
    }

    func sortedServerPerformerFilters(viewModel: StashDBViewModel) -> [StashDBViewModel.SavedFilter] {
        viewModel.savedFilters.values
            .filter { $0.mode == .performers }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var performerLiveChipRowsVisible: Bool {
        CatalogLiveChipFilterSupport.performerSavedFilterSupportsLiveEditor(selectedFilter)
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
        if let missingField = liveFilterMissingField, !missingField.isEmpty {
            dict.removeValue(forKey: "has_image")
            dict["is_missing"] = missingField
        }
        return dict
    }

    func refetchPerformers(viewModel: StashDBViewModel, initial: Bool) {
        let live = isLiveFilterActive ? activeLiveFilterDict : nil
        switch scope {
        case .studio(let id):
            viewModel.fetchDetailPerformers(studioId: id, sortBy: selectedSortOption, isInitialLoad: initial, filter: selectedFilter, liveFilter: live)
        case .tag(let id):
            viewModel.fetchDetailPerformers(tagId: id, sortBy: selectedSortOption, isInitialLoad: initial, filter: selectedFilter, liveFilter: live)
        case .group(let id):
            viewModel.fetchDetailPerformers(groupId: id, sortBy: selectedSortOption, isInitialLoad: initial, filter: selectedFilter, liveFilter: live)
        }
    }

    func applyLiveFilter(viewModel: StashDBViewModel) {
        refetchPerformers(viewModel: viewModel, initial: true)
    }

    func refreshLocalPresets() {
        localCatalogPresets = PerformerListLiveFilterPresetStore.loadPresets()
    }

    func clearLiveChipsOnly() {
        liveFilterAgeRange = nil
        liveFilterHairColor = nil
        liveFilterGender = nil
        liveFilterCountry = nil
        liveFilterImplants = nil
        liveFilterFavorite = nil
        liveFilterMissingField = nil
    }

    func mapLiveFragmentToChips(_ frag: [String: Any]) {
        clearLiveChipsOnly()
        if let fav = frag["filter_favorites"] as? Bool {
            liveFilterFavorite = fav
        }
        if let hair = frag["hair_color"] as? [String: Any], let v = hair["value"] as? String {
            liveFilterHairColor = v
        }
        if let g = frag["gender"] as? [String: Any], let v = g["value"] as? String {
            liveFilterGender = v
        }
        if let c = frag["country"] as? [String: Any] {
            let mod = (c["modifier"] as? String) ?? ""
            if mod == "NOT_EQUALS", (c["value"] as? String) == "US" {
                liveFilterCountry = "NOT_US"
            } else if let v = c["value"] as? String {
                liveFilterCountry = v
            }
        }
        if let ft = frag["fake_tits"] as? [String: Any], let v = ft["value"] as? String {
            liveFilterImplants = (v == "FAKE")
        }
        if let m = frag["is_missing"] as? String {
            liveFilterMissingField = m
        }
    }

    func changeSortOption(to newOption: StashDBViewModel.PerformerSortOption, viewModel: StashDBViewModel) {
        if newOption == .random && selectedSortOption == .random {
            viewModel.refreshRandomSeed()
        }
        selectedSortOption = newOption
        refetchPerformers(viewModel: viewModel, initial: true)
    }

    func applyCatalogPreset(_ preset: PerformerListLiveFilterPreset, viewModel: StashDBViewModel) {
        if preset.sort != selectedSortOption {
            if preset.sort == .random && selectedSortOption == .random {
                viewModel.refreshRandomSeed()
            }
            selectedSortOption = preset.sort
        }
        if let fid = preset.baseSavedFilterId, let f = viewModel.savedFilters[fid] {
            selectedFilter = f
        } else {
            selectedFilter = nil
        }
        if CatalogLiveChipFilterSupport.performerSavedFilterSupportsLiveEditor(selectedFilter) {
            mapLiveFragmentToChips(preset.liveFragment)
        } else {
            clearLiveChipsOnly()
        }
        applyLiveFilter(viewModel: viewModel)
    }

    func applyServerSavedFilter(_ f: StashDBViewModel.SavedFilter, viewModel: StashDBViewModel) {
        if let meta = f.stashyCatalogPresetMetadata {
            if let bid = meta.baseSavedFilterId, let base = viewModel.savedFilters[bid] {
                selectedFilter = base
            } else {
                selectedFilter = nil
            }
            if CatalogLiveChipFilterSupport.performerSavedFilterSupportsLiveEditor(selectedFilter) {
                mapLiveFragmentToChips(meta.liveFragment)
            } else {
                clearLiveChipsOnly()
            }
            if let sr = meta.sortRaw, let parsed = StashDBViewModel.PerformerSortOption(rawValue: sr), parsed != selectedSortOption {
                if parsed == .random && selectedSortOption == .random {
                    viewModel.refreshRandomSeed()
                }
                selectedSortOption = parsed
            }
        } else {
            selectedFilter = f
            if CatalogLiveChipFilterSupport.performerSavedFilterSupportsLiveEditor(f), let raw = f.filterDict {
                mapLiveFragmentToChips(raw)
            } else {
                clearLiveChipsOnly()
            }
        }
        applyLiveFilter(viewModel: viewModel)
    }

    func handlePresetSelection(_ newId: String, viewModel: StashDBViewModel) {
        guard showFilterSortSheet else { return }
        if newId.isEmpty {
            selectedFilter = nil
            clearLiveChipsOnly()
            applyLiveFilter(viewModel: viewModel)
            return
        }
        if let sid = ListLivePresetTag.parseServerId(newId), let f = viewModel.savedFilters[sid] {
            applyServerSavedFilter(f, viewModel: viewModel)
            return
        }
        if let ls = ListLivePresetTag.parseLocalUUIDString(newId),
           let uuid = UUID(uuidString: ls),
           let preset = localCatalogPresets.first(where: { $0.id == uuid }) {
            applyCatalogPreset(preset, viewModel: viewModel)
        }
    }

    func applyCatalogPresetSelectionFromSheetIfNeeded(viewModel: StashDBViewModel) {
        let newId = catalogPresetRowSelection
        guard !newId.isEmpty else { return }
        if let sid = ListLivePresetTag.parseServerId(newId), let f = viewModel.savedFilters[sid] {
            applyServerSavedFilter(f, viewModel: viewModel)
            return
        }
        if let ls = ListLivePresetTag.parseLocalUUIDString(newId),
           let uuid = UUID(uuidString: ls),
           let preset = localCatalogPresets.first(where: { $0.id == uuid }) {
            applyCatalogPreset(preset, viewModel: viewModel)
            return
        }
        if let uuid = UUID(uuidString: newId),
           let preset = localCatalogPresets.first(where: { $0.id == uuid }) {
            catalogPresetRowSelection = ListLivePresetTag.localRow(uuid)
            applyCatalogPreset(preset, viewModel: viewModel)
        }
    }

    func deletePresetConfirmationText(viewModel: StashDBViewModel) -> String {
        if let sid = ListLivePresetTag.parseServerId(catalogPresetRowSelection),
           let f = viewModel.savedFilters[sid] {
            return "Remove “\(f.name)” from Stash? Other devices will lose this saved filter."
        }
        if let ls = ListLivePresetTag.parseLocalUUIDString(catalogPresetRowSelection),
           let uuid = UUID(uuidString: ls),
           let p = localCatalogPresets.first(where: { $0.id == uuid }) {
            return "Remove “\(p.name)” from this device? This cannot be undone."
        }
        return "Remove this filter? This cannot be undone."
    }

    func savePresetOverwrite(viewModel: StashDBViewModel) {
        let sel = catalogPresetRowSelection
        if let sid = ListLivePresetTag.parseServerId(sel) {
            let name = viewModel.savedFilters[sid]?.name ?? "Filter"
            viewModel.saveCatalogSavedFilter(
                mode: .performers,
                randomSeedKind: .performers,
                existingId: sid,
                name: name,
                sortRaw: selectedSortOption.rawValue,
                sortField: selectedSortOption.sortField,
                sortDirection: selectedSortOption.direction,
                baseFilter: selectedFilter,
                liveFragment: activeLiveFilterDict
            ) { _ in }
            return
        }
        guard let ls = ListLivePresetTag.parseLocalUUIDString(sel),
              let uuid = UUID(uuidString: ls),
              let index = localCatalogPresets.firstIndex(where: { $0.id == uuid }) else { return }
        let old = localCatalogPresets[index]
        let updated = PerformerListLiveFilterPreset(
            id: old.id,
            name: old.name,
            createdAt: old.createdAt,
            sort: selectedSortOption,
            baseSavedFilterId: selectedFilter?.id,
            liveFragment: activeLiveFilterDict
        )
        PerformerListLiveFilterPresetStore.upsert(updated)
        refreshLocalPresets()
    }

    func savePresetAs(name: String, viewModel: StashDBViewModel) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        viewModel.saveCatalogSavedFilter(
            mode: .performers,
            randomSeedKind: .performers,
            existingId: nil,
            name: trimmed,
            sortRaw: selectedSortOption.rawValue,
            sortField: selectedSortOption.sortField,
            sortDirection: selectedSortOption.direction,
            baseFilter: selectedFilter,
            liveFragment: activeLiveFilterDict
        ) { [weak self] result in
            guard let self else { return }
            if case .success(let saved) = result {
                self.catalogPresetRowSelection = ListLivePresetTag.serverRow(saved.id)
                self.showSaveAsCatalogPresetAlert = false
            }
        }
    }

    func renamePreset(to newName: String, viewModel: StashDBViewModel) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let sel = catalogPresetRowSelection
        if let sid = ListLivePresetTag.parseServerId(sel) {
            viewModel.saveCatalogSavedFilter(
                mode: .performers,
                randomSeedKind: .performers,
                existingId: sid,
                name: trimmed,
                sortRaw: selectedSortOption.rawValue,
                sortField: selectedSortOption.sortField,
                sortDirection: selectedSortOption.direction,
                baseFilter: selectedFilter,
                liveFragment: activeLiveFilterDict
            ) { [weak self] result in
                if case .success = result { self?.showRenameCatalogPresetAlert = false }
            }
            return
        }
        guard let ls = ListLivePresetTag.parseLocalUUIDString(sel),
              let uuid = UUID(uuidString: ls),
              let preset = localCatalogPresets.first(where: { $0.id == uuid }) else { return }
        PerformerListLiveFilterPresetStore.upsert(preset.renamed(trimmed))
        refreshLocalPresets()
        showRenameCatalogPresetAlert = false
    }

    func deletePreset(viewModel: StashDBViewModel) {
        let sel = catalogPresetRowSelection
        if let sid = ListLivePresetTag.parseServerId(sel) {
            viewModel.destroySavedSceneFilter(id: sid) { [weak self] result in
                guard let self else { return }
                if case .success = result {
                    if self.selectedFilter?.id == sid { self.selectedFilter = nil }
                    self.catalogPresetRowSelection = ""
                    self.showDeleteCatalogPresetAlert = false
                    self.refetchPerformers(viewModel: viewModel, initial: true)
                }
            }
            return
        }
        guard let ls = ListLivePresetTag.parseLocalUUIDString(sel),
              let uuid = UUID(uuidString: ls) else { return }
        PerformerListLiveFilterPresetStore.remove(id: uuid)
        refreshLocalPresets()
        catalogPresetRowSelection = ""
        showDeleteCatalogPresetAlert = false
    }
}

// MARK: - Tags (scoped to performer / studio / group)

enum DetailLinkedTagsScope: Equatable {
    case performer(String)
    case studio(String)
    case group(String)
}

@MainActor
final class DetailLinkedTagsFilterModel: ObservableObject {
    let scope: DetailLinkedTagsScope

    @Published var showFilterSortSheet = false
    @Published var catalogPresetRowSelection = ""
    @Published var localCatalogPresets: [TagListLiveFilterPreset] = TagListLiveFilterPresetStore.loadPresets()
    @Published var showSaveAsCatalogPresetAlert = false
    @Published var catalogPresetNameInput = ""
    @Published var showRenameCatalogPresetAlert = false
    @Published var renameCatalogPresetInput = ""
    @Published var showDeleteCatalogPresetAlert = false

    @Published var selectedSortOption: StashDBViewModel.TagSortOption
    @Published var selectedFilter: StashDBViewModel.SavedFilter?
    @Published var liveFilterFavorite: Bool?
    @Published var liveFilterHasScenes: Bool = false

    init(scope: DetailLinkedTagsScope, initialSort: StashDBViewModel.TagSortOption = .sceneCountDesc) {
        self.scope = scope
        self.selectedSortOption = initialSort
        self.selectedFilter = nil
    }

    private var isLiveFilterActive: Bool {
        liveFilterFavorite != nil || liveFilterHasScenes
    }

    var catalogFilterSortFABActive: Bool {
        selectedFilter != nil || isLiveFilterActive
    }

    func sortedServerTagFilters(viewModel: StashDBViewModel) -> [StashDBViewModel.SavedFilter] {
        viewModel.savedFilters.values
            .filter { $0.mode == .tags }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var tagLiveChipRowsVisible: Bool {
        CatalogLiveChipFilterSupport.tagSavedFilterSupportsLiveEditor(selectedFilter)
    }

    private var activeLiveFilterDict: [String: Any] {
        var dict: [String: Any] = [:]
        if let fav = liveFilterFavorite { dict["favorite"] = fav }
        if liveFilterHasScenes { dict["scene_count"] = ["value": 0, "modifier": "GREATER_THAN"] }
        return dict
    }

    func refetchTags(viewModel: StashDBViewModel, initial: Bool) {
        let live = isLiveFilterActive ? activeLiveFilterDict : nil
        switch scope {
        case .performer(let id):
            viewModel.fetchDetailTags(performerId: id, sortBy: selectedSortOption, isInitialLoad: initial, filter: selectedFilter, liveFilter: live)
        case .studio(let id):
            viewModel.fetchDetailTags(studioId: id, sortBy: selectedSortOption, isInitialLoad: initial, filter: selectedFilter, liveFilter: live)
        case .group(let id):
            viewModel.fetchDetailTags(groupId: id, sortBy: selectedSortOption, isInitialLoad: initial, filter: selectedFilter, liveFilter: live)
        }
    }

    func applyLiveFilter(viewModel: StashDBViewModel) {
        refetchTags(viewModel: viewModel, initial: true)
    }

    func refreshLocalPresets() {
        localCatalogPresets = TagListLiveFilterPresetStore.loadPresets()
    }

    func clearLiveChipsOnly() {
        liveFilterFavorite = nil
        liveFilterHasScenes = false
    }

    func mapLiveFragmentToChips(_ frag: [String: Any]) {
        clearLiveChipsOnly()
        if let fav = frag["favorite"] as? Bool {
            liveFilterFavorite = fav
        }
        if let sc = frag["scene_count"] as? [String: Any], let mod = sc["modifier"] as? String, mod == "GREATER_THAN" {
            liveFilterHasScenes = true
        }
    }

    func changeSortOption(to newOption: StashDBViewModel.TagSortOption, viewModel: StashDBViewModel) {
        if newOption == .random && selectedSortOption == .random {
            viewModel.refreshRandomSeed()
        }
        selectedSortOption = newOption
        refetchTags(viewModel: viewModel, initial: true)
    }

    func applyCatalogPreset(_ preset: TagListLiveFilterPreset, viewModel: StashDBViewModel) {
        if preset.sort != selectedSortOption {
            if preset.sort == .random && selectedSortOption == .random {
                viewModel.refreshRandomSeed()
            }
            selectedSortOption = preset.sort
        }
        if let fid = preset.baseSavedFilterId, let f = viewModel.savedFilters[fid] {
            selectedFilter = f
        } else {
            selectedFilter = nil
        }
        if CatalogLiveChipFilterSupport.tagSavedFilterSupportsLiveEditor(selectedFilter) {
            mapLiveFragmentToChips(preset.liveFragment)
        } else {
            clearLiveChipsOnly()
        }
        applyLiveFilter(viewModel: viewModel)
    }

    func applyServerSavedFilter(_ f: StashDBViewModel.SavedFilter, viewModel: StashDBViewModel) {
        if let meta = f.stashyCatalogPresetMetadata {
            if let bid = meta.baseSavedFilterId, let base = viewModel.savedFilters[bid] {
                selectedFilter = base
            } else {
                selectedFilter = nil
            }
            if CatalogLiveChipFilterSupport.tagSavedFilterSupportsLiveEditor(selectedFilter) {
                mapLiveFragmentToChips(meta.liveFragment)
            } else {
                clearLiveChipsOnly()
            }
            if let sr = meta.sortRaw, let parsed = StashDBViewModel.TagSortOption(rawValue: sr), parsed != selectedSortOption {
                if parsed == .random && selectedSortOption == .random {
                    viewModel.refreshRandomSeed()
                }
                selectedSortOption = parsed
            }
        } else {
            selectedFilter = f
            if CatalogLiveChipFilterSupport.tagSavedFilterSupportsLiveEditor(f), let raw = f.filterDict {
                mapLiveFragmentToChips(raw)
            } else {
                clearLiveChipsOnly()
            }
        }
        applyLiveFilter(viewModel: viewModel)
    }

    func handlePresetSelection(_ newId: String, viewModel: StashDBViewModel) {
        guard showFilterSortSheet else { return }
        if newId.isEmpty {
            selectedFilter = nil
            clearLiveChipsOnly()
            applyLiveFilter(viewModel: viewModel)
            return
        }
        if let sid = ListLivePresetTag.parseServerId(newId), let f = viewModel.savedFilters[sid] {
            applyServerSavedFilter(f, viewModel: viewModel)
            return
        }
        if let ls = ListLivePresetTag.parseLocalUUIDString(newId),
           let uuid = UUID(uuidString: ls),
           let preset = localCatalogPresets.first(where: { $0.id == uuid }) {
            applyCatalogPreset(preset, viewModel: viewModel)
        }
    }

    func applyCatalogPresetSelectionFromSheetIfNeeded(viewModel: StashDBViewModel) {
        let newId = catalogPresetRowSelection
        guard !newId.isEmpty else { return }
        if let sid = ListLivePresetTag.parseServerId(newId), let f = viewModel.savedFilters[sid] {
            applyServerSavedFilter(f, viewModel: viewModel)
            return
        }
        if let ls = ListLivePresetTag.parseLocalUUIDString(newId),
           let uuid = UUID(uuidString: ls),
           let preset = localCatalogPresets.first(where: { $0.id == uuid }) {
            applyCatalogPreset(preset, viewModel: viewModel)
            return
        }
        if let uuid = UUID(uuidString: newId),
           let preset = localCatalogPresets.first(where: { $0.id == uuid }) {
            catalogPresetRowSelection = ListLivePresetTag.localRow(uuid)
            applyCatalogPreset(preset, viewModel: viewModel)
        }
    }

    func deletePresetConfirmationText(viewModel: StashDBViewModel) -> String {
        if let sid = ListLivePresetTag.parseServerId(catalogPresetRowSelection),
           let f = viewModel.savedFilters[sid] {
            return "Remove “\(f.name)” from Stash? Other devices will lose this saved filter."
        }
        if let ls = ListLivePresetTag.parseLocalUUIDString(catalogPresetRowSelection),
           let uuid = UUID(uuidString: ls),
           let p = localCatalogPresets.first(where: { $0.id == uuid }) {
            return "Remove “\(p.name)” from this device? This cannot be undone."
        }
        return "Remove this filter? This cannot be undone."
    }

    func savePresetOverwrite(viewModel: StashDBViewModel) {
        let sel = catalogPresetRowSelection
        if let sid = ListLivePresetTag.parseServerId(sel) {
            let name = viewModel.savedFilters[sid]?.name ?? "Filter"
            viewModel.saveCatalogSavedFilter(
                mode: .tags,
                randomSeedKind: .tags,
                existingId: sid,
                name: name,
                sortRaw: selectedSortOption.rawValue,
                sortField: selectedSortOption.sortField,
                sortDirection: selectedSortOption.direction,
                baseFilter: selectedFilter,
                liveFragment: activeLiveFilterDict
            ) { _ in }
            return
        }
        guard let ls = ListLivePresetTag.parseLocalUUIDString(sel),
              let uuid = UUID(uuidString: ls),
              let index = localCatalogPresets.firstIndex(where: { $0.id == uuid }) else { return }
        let old = localCatalogPresets[index]
        let updated = TagListLiveFilterPreset(
            id: old.id,
            name: old.name,
            createdAt: old.createdAt,
            sort: selectedSortOption,
            baseSavedFilterId: selectedFilter?.id,
            liveFragment: activeLiveFilterDict
        )
        TagListLiveFilterPresetStore.upsert(updated)
        refreshLocalPresets()
    }

    func savePresetAs(name: String, viewModel: StashDBViewModel) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        viewModel.saveCatalogSavedFilter(
            mode: .tags,
            randomSeedKind: .tags,
            existingId: nil,
            name: trimmed,
            sortRaw: selectedSortOption.rawValue,
            sortField: selectedSortOption.sortField,
            sortDirection: selectedSortOption.direction,
            baseFilter: selectedFilter,
            liveFragment: activeLiveFilterDict
        ) { [weak self] result in
            guard let self else { return }
            if case .success(let saved) = result {
                self.catalogPresetRowSelection = ListLivePresetTag.serverRow(saved.id)
                self.showSaveAsCatalogPresetAlert = false
            }
        }
    }

    func renamePreset(to newName: String, viewModel: StashDBViewModel) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let sel = catalogPresetRowSelection
        if let sid = ListLivePresetTag.parseServerId(sel) {
            viewModel.saveCatalogSavedFilter(
                mode: .tags,
                randomSeedKind: .tags,
                existingId: sid,
                name: trimmed,
                sortRaw: selectedSortOption.rawValue,
                sortField: selectedSortOption.sortField,
                sortDirection: selectedSortOption.direction,
                baseFilter: selectedFilter,
                liveFragment: activeLiveFilterDict
            ) { [weak self] result in
                if case .success = result { self?.showRenameCatalogPresetAlert = false }
            }
            return
        }
        guard let ls = ListLivePresetTag.parseLocalUUIDString(sel),
              let uuid = UUID(uuidString: ls),
              let preset = localCatalogPresets.first(where: { $0.id == uuid }) else { return }
        TagListLiveFilterPresetStore.upsert(preset.renamed(trimmed))
        refreshLocalPresets()
        showRenameCatalogPresetAlert = false
    }

    func deletePreset(viewModel: StashDBViewModel) {
        let sel = catalogPresetRowSelection
        if let sid = ListLivePresetTag.parseServerId(sel) {
            viewModel.destroySavedSceneFilter(id: sid) { [weak self] result in
                guard let self else { return }
                if case .success = result {
                    if self.selectedFilter?.id == sid { self.selectedFilter = nil }
                    self.catalogPresetRowSelection = ""
                    self.showDeleteCatalogPresetAlert = false
                    self.refetchTags(viewModel: viewModel, initial: true)
                }
            }
            return
        }
        guard let ls = ListLivePresetTag.parseLocalUUIDString(sel),
              let uuid = UUID(uuidString: ls) else { return }
        TagListLiveFilterPresetStore.remove(id: uuid)
        refreshLocalPresets()
        catalogPresetRowSelection = ""
        showDeleteCatalogPresetAlert = false
    }
}

// MARK: - Studios (scoped to performer / tag / parent studio / group)

enum DetailLinkedStudiosScope: Equatable {
    case performer(String)
    case tag(String)
    case parentStudio(String)
    case group(String)
}

@MainActor
final class DetailLinkedStudiosFilterModel: ObservableObject {
    let scope: DetailLinkedStudiosScope

    @Published var showFilterSortSheet = false
    @Published var catalogPresetRowSelection = ""
    @Published var localCatalogPresets: [StudioListLiveFilterPreset] = StudioListLiveFilterPresetStore.loadPresets()
    @Published var showSaveAsCatalogPresetAlert = false
    @Published var catalogPresetNameInput = ""
    @Published var showRenameCatalogPresetAlert = false
    @Published var renameCatalogPresetInput = ""
    @Published var showDeleteCatalogPresetAlert = false

    @Published var selectedSortOption: StashDBViewModel.StudioSortOption
    @Published var selectedFilter: StashDBViewModel.SavedFilter?
    @Published var liveFilterFavorite: Bool?
    @Published var liveFilterMinRating: Int = 0
    @Published var liveFilterScenes: String?

    init(scope: DetailLinkedStudiosScope, initialSort: StashDBViewModel.StudioSortOption = .nameAsc) {
        self.scope = scope
        self.selectedSortOption = initialSort
        self.selectedFilter = nil
    }

    private var isLiveFilterActive: Bool {
        liveFilterFavorite != nil || liveFilterMinRating > 0 || liveFilterScenes != nil
    }

    var catalogFilterSortFABActive: Bool {
        selectedFilter != nil || isLiveFilterActive
    }

    func sortedServerStudioFilters(viewModel: StashDBViewModel) -> [StashDBViewModel.SavedFilter] {
        viewModel.savedFilters.values
            .filter { $0.mode == .studios }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var studioLiveChipRowsVisible: Bool {
        CatalogLiveChipFilterSupport.studioSavedFilterSupportsLiveEditor(selectedFilter)
    }

    private var activeLiveFilterDict: [String: Any] {
        var dict: [String: Any] = [:]
        if let fav = liveFilterFavorite { dict["favorite"] = fav }
        if liveFilterMinRating > 0 {
            dict["rating100"] = ["value": (liveFilterMinRating * 20), "modifier": "EQUALS"]
        }
        if liveFilterScenes == "has" { dict["scene_count"] = ["value": 0, "modifier": "GREATER_THAN"] }
        if liveFilterScenes == "none" { dict["scene_count"] = ["value": 0, "modifier": "EQUALS"] }
        return dict
    }

    func refetchStudios(viewModel: StashDBViewModel, initial: Bool) {
        let live = isLiveFilterActive ? activeLiveFilterDict : nil
        switch scope {
        case .performer(let id):
            viewModel.fetchDetailStudios(performerId: id, sortBy: selectedSortOption, isInitialLoad: initial, filter: selectedFilter, liveFilter: live)
        case .tag(let id):
            viewModel.fetchDetailStudios(tagId: id, sortBy: selectedSortOption, isInitialLoad: initial, filter: selectedFilter, liveFilter: live)
        case .parentStudio(let id):
            viewModel.fetchDetailStudios(parentStudioId: id, sortBy: selectedSortOption, isInitialLoad: initial, filter: selectedFilter, liveFilter: live)
        case .group(let id):
            viewModel.fetchDetailStudios(groupId: id, sortBy: selectedSortOption, isInitialLoad: initial, filter: selectedFilter, liveFilter: live)
        }
    }

    func applyLiveFilter(viewModel: StashDBViewModel) {
        refetchStudios(viewModel: viewModel, initial: true)
    }

    func refreshLocalPresets() {
        localCatalogPresets = StudioListLiveFilterPresetStore.loadPresets()
    }

    func clearLiveChipsOnly() {
        liveFilterFavorite = nil
        liveFilterMinRating = 0
        liveFilterScenes = nil
    }

    func mapLiveFragmentToChips(_ frag: [String: Any]) {
        clearLiveChipsOnly()
        if let fav = frag["favorite"] as? Bool {
            liveFilterFavorite = fav
        }
        if let r = frag["rating100"] as? [String: Any], let raw = r["value"] {
            let v: Int? = {
                if let i = raw as? Int { return i }
                if let d = raw as? Double { return Int(d) }
                if let n = raw as? NSNumber { return n.intValue }
                return nil
            }()
            if let v {
                liveFilterMinRating = max(0, min(5, v / 20))
            }
        }
        if let sc = frag["scene_count"] as? [String: Any], let mod = sc["modifier"] as? String {
            if mod == "GREATER_THAN" {
                liveFilterScenes = "has"
            } else if mod == "EQUALS" {
                liveFilterScenes = "none"
            }
        }
    }

    func changeSortOption(to newOption: StashDBViewModel.StudioSortOption, viewModel: StashDBViewModel) {
        if newOption == .random && selectedSortOption == .random {
            viewModel.refreshRandomSeed()
        }
        selectedSortOption = newOption
        refetchStudios(viewModel: viewModel, initial: true)
    }

    func applyCatalogPreset(_ preset: StudioListLiveFilterPreset, viewModel: StashDBViewModel) {
        if preset.sort != selectedSortOption {
            if preset.sort == .random && selectedSortOption == .random {
                viewModel.refreshRandomSeed()
            }
            selectedSortOption = preset.sort
        }
        if let fid = preset.baseSavedFilterId, let f = viewModel.savedFilters[fid] {
            selectedFilter = f
        } else {
            selectedFilter = nil
        }
        if CatalogLiveChipFilterSupport.studioSavedFilterSupportsLiveEditor(selectedFilter) {
            mapLiveFragmentToChips(preset.liveFragment)
        } else {
            clearLiveChipsOnly()
        }
        applyLiveFilter(viewModel: viewModel)
    }

    func applyServerSavedFilter(_ f: StashDBViewModel.SavedFilter, viewModel: StashDBViewModel) {
        if let meta = f.stashyCatalogPresetMetadata {
            if let bid = meta.baseSavedFilterId, let base = viewModel.savedFilters[bid] {
                selectedFilter = base
            } else {
                selectedFilter = nil
            }
            if CatalogLiveChipFilterSupport.studioSavedFilterSupportsLiveEditor(selectedFilter) {
                mapLiveFragmentToChips(meta.liveFragment)
            } else {
                clearLiveChipsOnly()
            }
            if let sr = meta.sortRaw, let parsed = StashDBViewModel.StudioSortOption(rawValue: sr), parsed != selectedSortOption {
                if parsed == .random && selectedSortOption == .random {
                    viewModel.refreshRandomSeed()
                }
                selectedSortOption = parsed
            }
        } else {
            selectedFilter = f
            if CatalogLiveChipFilterSupport.studioSavedFilterSupportsLiveEditor(f), let raw = f.filterDict {
                mapLiveFragmentToChips(raw)
            } else {
                clearLiveChipsOnly()
            }
        }
        applyLiveFilter(viewModel: viewModel)
    }

    func handlePresetSelection(_ newId: String, viewModel: StashDBViewModel) {
        guard showFilterSortSheet else { return }
        if newId.isEmpty {
            selectedFilter = nil
            clearLiveChipsOnly()
            applyLiveFilter(viewModel: viewModel)
            return
        }
        if let sid = ListLivePresetTag.parseServerId(newId), let f = viewModel.savedFilters[sid] {
            applyServerSavedFilter(f, viewModel: viewModel)
            return
        }
        if let ls = ListLivePresetTag.parseLocalUUIDString(newId),
           let uuid = UUID(uuidString: ls),
           let preset = localCatalogPresets.first(where: { $0.id == uuid }) {
            applyCatalogPreset(preset, viewModel: viewModel)
        }
    }

    func applyCatalogPresetSelectionFromSheetIfNeeded(viewModel: StashDBViewModel) {
        let newId = catalogPresetRowSelection
        guard !newId.isEmpty else { return }
        if let sid = ListLivePresetTag.parseServerId(newId), let f = viewModel.savedFilters[sid] {
            applyServerSavedFilter(f, viewModel: viewModel)
            return
        }
        if let ls = ListLivePresetTag.parseLocalUUIDString(newId),
           let uuid = UUID(uuidString: ls),
           let preset = localCatalogPresets.first(where: { $0.id == uuid }) {
            applyCatalogPreset(preset, viewModel: viewModel)
            return
        }
        if let uuid = UUID(uuidString: newId),
           let preset = localCatalogPresets.first(where: { $0.id == uuid }) {
            catalogPresetRowSelection = ListLivePresetTag.localRow(uuid)
            applyCatalogPreset(preset, viewModel: viewModel)
        }
    }

    func deletePresetConfirmationText(viewModel: StashDBViewModel) -> String {
        if let sid = ListLivePresetTag.parseServerId(catalogPresetRowSelection),
           let f = viewModel.savedFilters[sid] {
            return "Remove “\(f.name)” from Stash? Other devices will lose this saved filter."
        }
        if let ls = ListLivePresetTag.parseLocalUUIDString(catalogPresetRowSelection),
           let uuid = UUID(uuidString: ls),
           let p = localCatalogPresets.first(where: { $0.id == uuid }) {
            return "Remove “\(p.name)” from this device? This cannot be undone."
        }
        return "Remove this filter? This cannot be undone."
    }

    func savePresetOverwrite(viewModel: StashDBViewModel) {
        let sel = catalogPresetRowSelection
        if let sid = ListLivePresetTag.parseServerId(sel) {
            let name = viewModel.savedFilters[sid]?.name ?? "Filter"
            viewModel.saveCatalogSavedFilter(
                mode: .studios,
                randomSeedKind: .studios,
                existingId: sid,
                name: name,
                sortRaw: selectedSortOption.rawValue,
                sortField: selectedSortOption.sortField,
                sortDirection: selectedSortOption.direction,
                baseFilter: selectedFilter,
                liveFragment: activeLiveFilterDict
            ) { _ in }
            return
        }
        guard let ls = ListLivePresetTag.parseLocalUUIDString(sel),
              let uuid = UUID(uuidString: ls),
              let index = localCatalogPresets.firstIndex(where: { $0.id == uuid }) else { return }
        let old = localCatalogPresets[index]
        let updated = StudioListLiveFilterPreset(
            id: old.id,
            name: old.name,
            createdAt: old.createdAt,
            sort: selectedSortOption,
            baseSavedFilterId: selectedFilter?.id,
            liveFragment: activeLiveFilterDict
        )
        StudioListLiveFilterPresetStore.upsert(updated)
        refreshLocalPresets()
    }

    func savePresetAs(name: String, viewModel: StashDBViewModel) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        viewModel.saveCatalogSavedFilter(
            mode: .studios,
            randomSeedKind: .studios,
            existingId: nil,
            name: trimmed,
            sortRaw: selectedSortOption.rawValue,
            sortField: selectedSortOption.sortField,
            sortDirection: selectedSortOption.direction,
            baseFilter: selectedFilter,
            liveFragment: activeLiveFilterDict
        ) { [weak self] result in
            guard let self else { return }
            if case .success(let saved) = result {
                self.catalogPresetRowSelection = ListLivePresetTag.serverRow(saved.id)
                self.showSaveAsCatalogPresetAlert = false
            }
        }
    }

    func renamePreset(to newName: String, viewModel: StashDBViewModel) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let sel = catalogPresetRowSelection
        if let sid = ListLivePresetTag.parseServerId(sel) {
            viewModel.saveCatalogSavedFilter(
                mode: .studios,
                randomSeedKind: .studios,
                existingId: sid,
                name: trimmed,
                sortRaw: selectedSortOption.rawValue,
                sortField: selectedSortOption.sortField,
                sortDirection: selectedSortOption.direction,
                baseFilter: selectedFilter,
                liveFragment: activeLiveFilterDict
            ) { [weak self] result in
                if case .success = result { self?.showRenameCatalogPresetAlert = false }
            }
            return
        }
        guard let ls = ListLivePresetTag.parseLocalUUIDString(sel),
              let uuid = UUID(uuidString: ls),
              let preset = localCatalogPresets.first(where: { $0.id == uuid }) else { return }
        StudioListLiveFilterPresetStore.upsert(preset.renamed(trimmed))
        refreshLocalPresets()
        showRenameCatalogPresetAlert = false
    }

    func deletePreset(viewModel: StashDBViewModel) {
        let sel = catalogPresetRowSelection
        if let sid = ListLivePresetTag.parseServerId(sel) {
            viewModel.destroySavedSceneFilter(id: sid) { [weak self] result in
                guard let self else { return }
                if case .success = result {
                    if self.selectedFilter?.id == sid { self.selectedFilter = nil }
                    self.catalogPresetRowSelection = ""
                    self.showDeleteCatalogPresetAlert = false
                    self.refetchStudios(viewModel: viewModel, initial: true)
                }
            }
            return
        }
        guard let ls = ListLivePresetTag.parseLocalUUIDString(sel),
              let uuid = UUID(uuidString: ls) else { return }
        StudioListLiveFilterPresetStore.remove(id: uuid)
        refreshLocalPresets()
        catalogPresetRowSelection = ""
        showDeleteCatalogPresetAlert = false
    }
}

// MARK: - Galleries (scoped to performer / studio / tag / group)

enum DetailLinkedGalleriesScope: Equatable {
    case performer(String)
    case studio(String)
    case tag(String)
    case group(String)
}

@MainActor
final class DetailLinkedGalleriesFilterModel: ObservableObject {
    let scope: DetailLinkedGalleriesScope

    @Published var showFilterSortSheet = false
    @Published var catalogPresetRowSelection = ""
    @Published var localCatalogPresets: [GalleryListLiveFilterPreset] = GalleryListLiveFilterPresetStore.loadPresets()
    @Published var showSaveAsCatalogPresetAlert = false
    @Published var catalogPresetNameInput = ""
    @Published var showRenameCatalogPresetAlert = false
    @Published var renameCatalogPresetInput = ""
    @Published var showDeleteCatalogPresetAlert = false

    @Published var selectedSortOption: StashDBViewModel.GallerySortOption
    @Published var selectedFilter: StashDBViewModel.SavedFilter?
    @Published var liveFilterFavorite: Bool?
    @Published var liveFilterMinRating: Int = 0
    @Published var liveFilterFiles: String?

    init(scope: DetailLinkedGalleriesScope, initialSort: StashDBViewModel.GallerySortOption = .dateDesc) {
        self.scope = scope
        self.selectedSortOption = initialSort
        self.selectedFilter = nil
    }

    private var isLiveFilterActive: Bool {
        liveFilterFavorite != nil || liveFilterMinRating > 0 || liveFilterFiles != nil
    }

    var catalogFilterSortFABActive: Bool {
        selectedFilter != nil || isLiveFilterActive
    }

    func sortedServerGalleryFilters(viewModel: StashDBViewModel) -> [StashDBViewModel.SavedFilter] {
        viewModel.savedFilters.values
            .filter { $0.mode == .galleries }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var galleryLiveChipRowsVisible: Bool {
        CatalogLiveChipFilterSupport.gallerySavedFilterSupportsLiveEditor(selectedFilter)
    }

    private var activeLiveFilterDict: [String: Any] {
        var dict: [String: Any] = [:]
        if let fav = liveFilterFavorite { dict["favorite"] = fav }
        if liveFilterMinRating > 0 {
            dict["rating100"] = ["value": (liveFilterMinRating * 20), "modifier": "EQUALS"]
        }
        if liveFilterFiles == "has" { dict["file_count"] = ["value": 0, "modifier": "GREATER_THAN"] }
        if liveFilterFiles == "none" { dict["file_count"] = ["value": 0, "modifier": "EQUALS"] }
        return dict
    }

    func refetchGalleries(viewModel: StashDBViewModel, initial: Bool) {
        let live = isLiveFilterActive ? activeLiveFilterDict : nil
        switch scope {
        case .performer(let id):
            viewModel.fetchPerformerGalleries(performerId: id, sortBy: selectedSortOption, isInitialLoad: initial, filter: selectedFilter, liveFilter: live)
        case .studio(let id):
            viewModel.fetchStudioGalleries(studioId: id, sortBy: selectedSortOption, isInitialLoad: initial, filter: selectedFilter, liveFilter: live)
        case .tag(let id):
            viewModel.fetchTagGalleries(tagId: id, sortBy: selectedSortOption, isInitialLoad: initial, filter: selectedFilter, liveFilter: live)
        case .group(let id):
            viewModel.fetchGroupGalleries(groupId: id, sortBy: selectedSortOption, isInitialLoad: initial, filter: selectedFilter, liveFilter: live)
        }
    }

    func applyLiveFilter(viewModel: StashDBViewModel) {
        refetchGalleries(viewModel: viewModel, initial: true)
    }

    func refreshLocalPresets() {
        localCatalogPresets = GalleryListLiveFilterPresetStore.loadPresets()
    }

    func clearLiveChipsOnly() {
        liveFilterFavorite = nil
        liveFilterMinRating = 0
        liveFilterFiles = nil
    }

    func mapLiveFragmentToChips(_ frag: [String: Any]) {
        clearLiveChipsOnly()
        if let fav = frag["favorite"] as? Bool {
            liveFilterFavorite = fav
        }
        if let r = frag["rating100"] as? [String: Any], let raw = r["value"] {
            let v: Int? = {
                if let i = raw as? Int { return i }
                if let d = raw as? Double { return Int(d) }
                if let n = raw as? NSNumber { return n.intValue }
                return nil
            }()
            if let v {
                liveFilterMinRating = max(0, min(5, v / 20))
            }
        }
        if let fc = frag["file_count"] as? [String: Any], let mod = fc["modifier"] as? String {
            if mod == "GREATER_THAN" {
                liveFilterFiles = "has"
            } else if mod == "EQUALS" {
                liveFilterFiles = "none"
            }
        }
    }

    func changeSortOption(to newOption: StashDBViewModel.GallerySortOption, viewModel: StashDBViewModel) {
        if newOption == .random && selectedSortOption == .random {
            viewModel.refreshRandomSeed()
        }
        selectedSortOption = newOption
        refetchGalleries(viewModel: viewModel, initial: true)
    }

    func applyCatalogPreset(_ preset: GalleryListLiveFilterPreset, viewModel: StashDBViewModel) {
        if preset.sort != selectedSortOption {
            if preset.sort == .random && selectedSortOption == .random {
                viewModel.refreshRandomSeed()
            }
            selectedSortOption = preset.sort
        }
        if let fid = preset.baseSavedFilterId, let f = viewModel.savedFilters[fid] {
            selectedFilter = f
        } else {
            selectedFilter = nil
        }
        if CatalogLiveChipFilterSupport.gallerySavedFilterSupportsLiveEditor(selectedFilter) {
            mapLiveFragmentToChips(preset.liveFragment)
        } else {
            clearLiveChipsOnly()
        }
        applyLiveFilter(viewModel: viewModel)
    }

    func applyServerSavedFilter(_ f: StashDBViewModel.SavedFilter, viewModel: StashDBViewModel) {
        if let meta = f.stashyCatalogPresetMetadata {
            if let bid = meta.baseSavedFilterId, let base = viewModel.savedFilters[bid] {
                selectedFilter = base
            } else {
                selectedFilter = nil
            }
            if CatalogLiveChipFilterSupport.gallerySavedFilterSupportsLiveEditor(selectedFilter) {
                mapLiveFragmentToChips(meta.liveFragment)
            } else {
                clearLiveChipsOnly()
            }
            if let sr = meta.sortRaw, let parsed = StashDBViewModel.GallerySortOption(rawValue: sr), parsed != selectedSortOption {
                if parsed == .random && selectedSortOption == .random {
                    viewModel.refreshRandomSeed()
                }
                selectedSortOption = parsed
            }
        } else {
            selectedFilter = f
            if CatalogLiveChipFilterSupport.gallerySavedFilterSupportsLiveEditor(f), let raw = f.filterDict {
                mapLiveFragmentToChips(raw)
            } else {
                clearLiveChipsOnly()
            }
        }
        applyLiveFilter(viewModel: viewModel)
    }

    func handlePresetSelection(_ newId: String, viewModel: StashDBViewModel) {
        guard showFilterSortSheet else { return }
        if newId.isEmpty {
            selectedFilter = nil
            clearLiveChipsOnly()
            applyLiveFilter(viewModel: viewModel)
            return
        }
        if let sid = ListLivePresetTag.parseServerId(newId), let f = viewModel.savedFilters[sid] {
            applyServerSavedFilter(f, viewModel: viewModel)
            return
        }
        if let ls = ListLivePresetTag.parseLocalUUIDString(newId),
           let uuid = UUID(uuidString: ls),
           let preset = localCatalogPresets.first(where: { $0.id == uuid }) {
            applyCatalogPreset(preset, viewModel: viewModel)
        }
    }

    func applyCatalogPresetSelectionFromSheetIfNeeded(viewModel: StashDBViewModel) {
        let newId = catalogPresetRowSelection
        guard !newId.isEmpty else { return }
        if let sid = ListLivePresetTag.parseServerId(newId), let f = viewModel.savedFilters[sid] {
            applyServerSavedFilter(f, viewModel: viewModel)
            return
        }
        if let ls = ListLivePresetTag.parseLocalUUIDString(newId),
           let uuid = UUID(uuidString: ls),
           let preset = localCatalogPresets.first(where: { $0.id == uuid }) {
            applyCatalogPreset(preset, viewModel: viewModel)
            return
        }
        if let uuid = UUID(uuidString: newId),
           let preset = localCatalogPresets.first(where: { $0.id == uuid }) {
            catalogPresetRowSelection = ListLivePresetTag.localRow(uuid)
            applyCatalogPreset(preset, viewModel: viewModel)
        }
    }

    func deletePresetConfirmationText(viewModel: StashDBViewModel) -> String {
        if let sid = ListLivePresetTag.parseServerId(catalogPresetRowSelection),
           let f = viewModel.savedFilters[sid] {
            return "Remove “\(f.name)” from Stash? Other devices will lose this saved filter."
        }
        if let ls = ListLivePresetTag.parseLocalUUIDString(catalogPresetRowSelection),
           let uuid = UUID(uuidString: ls),
           let p = localCatalogPresets.first(where: { $0.id == uuid }) {
            return "Remove “\(p.name)” from this device? This cannot be undone."
        }
        return "Remove this filter? This cannot be undone."
    }

    func savePresetOverwrite(viewModel: StashDBViewModel) {
        let sel = catalogPresetRowSelection
        if let sid = ListLivePresetTag.parseServerId(sel) {
            let name = viewModel.savedFilters[sid]?.name ?? "Filter"
            viewModel.saveCatalogSavedFilter(
                mode: .galleries,
                randomSeedKind: .galleries,
                existingId: sid,
                name: name,
                sortRaw: selectedSortOption.rawValue,
                sortField: selectedSortOption.sortField,
                sortDirection: selectedSortOption.direction,
                baseFilter: selectedFilter,
                liveFragment: activeLiveFilterDict
            ) { _ in }
            return
        }
        guard let ls = ListLivePresetTag.parseLocalUUIDString(sel),
              let uuid = UUID(uuidString: ls),
              let index = localCatalogPresets.firstIndex(where: { $0.id == uuid }) else { return }
        let old = localCatalogPresets[index]
        let updated = GalleryListLiveFilterPreset(
            id: old.id,
            name: old.name,
            createdAt: old.createdAt,
            sort: selectedSortOption,
            baseSavedFilterId: selectedFilter?.id,
            liveFragment: activeLiveFilterDict
        )
        GalleryListLiveFilterPresetStore.upsert(updated)
        refreshLocalPresets()
    }

    func savePresetAs(name: String, viewModel: StashDBViewModel) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        viewModel.saveCatalogSavedFilter(
            mode: .galleries,
            randomSeedKind: .galleries,
            existingId: nil,
            name: trimmed,
            sortRaw: selectedSortOption.rawValue,
            sortField: selectedSortOption.sortField,
            sortDirection: selectedSortOption.direction,
            baseFilter: selectedFilter,
            liveFragment: activeLiveFilterDict
        ) { [weak self] result in
            guard let self else { return }
            if case .success(let saved) = result {
                self.catalogPresetRowSelection = ListLivePresetTag.serverRow(saved.id)
                self.showSaveAsCatalogPresetAlert = false
            }
        }
    }

    func renamePreset(to newName: String, viewModel: StashDBViewModel) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let sel = catalogPresetRowSelection
        if let sid = ListLivePresetTag.parseServerId(sel) {
            viewModel.saveCatalogSavedFilter(
                mode: .galleries,
                randomSeedKind: .galleries,
                existingId: sid,
                name: trimmed,
                sortRaw: selectedSortOption.rawValue,
                sortField: selectedSortOption.sortField,
                sortDirection: selectedSortOption.direction,
                baseFilter: selectedFilter,
                liveFragment: activeLiveFilterDict
            ) { [weak self] result in
                if case .success = result { self?.showRenameCatalogPresetAlert = false }
            }
            return
        }
        guard let ls = ListLivePresetTag.parseLocalUUIDString(sel),
              let uuid = UUID(uuidString: ls),
              let preset = localCatalogPresets.first(where: { $0.id == uuid }) else { return }
        GalleryListLiveFilterPresetStore.upsert(preset.renamed(trimmed))
        refreshLocalPresets()
        showRenameCatalogPresetAlert = false
    }

    func deletePreset(viewModel: StashDBViewModel) {
        let sel = catalogPresetRowSelection
        if let sid = ListLivePresetTag.parseServerId(sel) {
            viewModel.destroySavedSceneFilter(id: sid) { [weak self] result in
                guard let self else { return }
                if case .success = result {
                    if self.selectedFilter?.id == sid { self.selectedFilter = nil }
                    self.catalogPresetRowSelection = ""
                    self.showDeleteCatalogPresetAlert = false
                    self.refetchGalleries(viewModel: viewModel, initial: true)
                }
            }
            return
        }
        guard let ls = ListLivePresetTag.parseLocalUUIDString(sel),
              let uuid = UUID(uuidString: ls) else { return }
        GalleryListLiveFilterPresetStore.remove(id: uuid)
        refreshLocalPresets()
        catalogPresetRowSelection = ""
        showDeleteCatalogPresetAlert = false
    }
}

// MARK: - Images (detail lists + single gallery)

enum DetailLinkedImagesScope: Equatable {
    case catalogRoot
    case performer(String)
    case studio(String)
    case tag(String)
    case group(String)
    case gallery(String)
}

@MainActor
final class DetailLinkedImagesFilterModel: ObservableObject {
    let scope: DetailLinkedImagesScope

    @Published var showFilterSortSheet = false
    @Published var catalogPresetRowSelection = ""
    @Published var localCatalogPresets: [ImageListLiveFilterPreset] = ImageListLiveFilterPresetStore.loadPresets()
    @Published var showSaveAsCatalogPresetAlert = false
    @Published var catalogPresetNameInput = ""
    @Published var showRenameCatalogPresetAlert = false
    @Published var renameCatalogPresetInput = ""
    @Published var showDeleteCatalogPresetAlert = false

    @Published var selectedSortOption: StashDBViewModel.ImageSortOption
    @Published var selectedFilter: StashDBViewModel.SavedFilter?
    @Published var liveFilterFavorite: Bool?
    @Published var liveFilterMinRating: Int = 0
    @Published var liveFilterOrganized: String?

    init(scope: DetailLinkedImagesScope, initialSort: StashDBViewModel.ImageSortOption = .dateDesc) {
        self.scope = scope
        self.selectedSortOption = initialSort
        self.selectedFilter = nil
    }

    private var isLiveFilterActive: Bool {
        liveFilterFavorite != nil || liveFilterMinRating > 0 || liveFilterOrganized != nil
    }

    var catalogFilterSortFABActive: Bool {
        selectedFilter != nil || isLiveFilterActive
    }

    func sortedServerImageFilters(viewModel: StashDBViewModel) -> [StashDBViewModel.SavedFilter] {
        viewModel.savedFilters.values
            .filter { $0.mode == .images }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var imageLiveChipRowsVisible: Bool {
        CatalogLiveChipFilterSupport.imageSavedFilterSupportsLiveEditor(selectedFilter)
    }

    private var activeLiveFilterDict: [String: Any] {
        var dict: [String: Any] = [:]
        if let fav = liveFilterFavorite { dict["favorite"] = fav }
        if liveFilterMinRating > 0 {
            dict["rating100"] = ["value": (liveFilterMinRating * 20), "modifier": "EQUALS"]
        }
        if liveFilterOrganized == "true" { dict["organized"] = true }
        if liveFilterOrganized == "false" { dict["organized"] = false }
        return dict
    }

    func refetchImages(viewModel: StashDBViewModel, initial: Bool) {
        let live = isLiveFilterActive ? activeLiveFilterDict : nil
        switch scope {
        case .catalogRoot:
            viewModel.fetchImages(
                sortBy: selectedSortOption,
                isInitialLoad: initial,
                filter: selectedFilter,
                staticPathFilter: viewModel.imageStaticPathFilter,
                performerId: viewModel.imagePerformerIdFilter,
                liveFilter: live
            )
        case .performer(let id):
            viewModel.fetchDetailImages(performerId: id, sortBy: selectedSortOption, isInitialLoad: initial, filter: selectedFilter, liveFilter: live)
        case .studio(let id):
            viewModel.fetchDetailImages(studioId: id, sortBy: selectedSortOption, isInitialLoad: initial, filter: selectedFilter, liveFilter: live)
        case .tag(let id):
            viewModel.fetchDetailImages(tagId: id, sortBy: selectedSortOption, isInitialLoad: initial, filter: selectedFilter, liveFilter: live)
        case .group(let id):
            viewModel.fetchDetailImages(groupId: id, sortBy: selectedSortOption, isInitialLoad: initial, filter: selectedFilter, liveFilter: live)
        case .gallery(let id):
            viewModel.fetchGalleryImages(galleryId: id, sortBy: selectedSortOption, isInitialLoad: initial, filter: selectedFilter, liveFilter: live)
        }
    }

    func applyLiveFilter(viewModel: StashDBViewModel) {
        refetchImages(viewModel: viewModel, initial: true)
    }

    func refreshLocalPresets() {
        localCatalogPresets = ImageListLiveFilterPresetStore.loadPresets()
    }

    func clearLiveChipsOnly() {
        liveFilterFavorite = nil
        liveFilterMinRating = 0
        liveFilterOrganized = nil
    }

    func mapLiveFragmentToChips(_ frag: [String: Any]) {
        clearLiveChipsOnly()
        if let fav = frag["favorite"] as? Bool {
            liveFilterFavorite = fav
        }
        if let r = frag["rating100"] as? [String: Any], let raw = r["value"] {
            let v: Int? = {
                if let i = raw as? Int { return i }
                if let d = raw as? Double { return Int(d) }
                if let n = raw as? NSNumber { return n.intValue }
                return nil
            }()
            if let v {
                liveFilterMinRating = max(0, min(5, v / 20))
            }
        }
        if let o = frag["organized"] as? Bool {
            liveFilterOrganized = o ? "true" : "false"
        }
    }

    func changeSortOption(to newOption: StashDBViewModel.ImageSortOption, viewModel: StashDBViewModel) {
        if newOption == .random && selectedSortOption == .random {
            viewModel.refreshRandomSeed()
        }
        selectedSortOption = newOption
        refetchImages(viewModel: viewModel, initial: true)
    }

    func applyCatalogPreset(_ preset: ImageListLiveFilterPreset, viewModel: StashDBViewModel) {
        if preset.sort != selectedSortOption {
            if preset.sort == .random && selectedSortOption == .random {
                viewModel.refreshRandomSeed()
            }
            selectedSortOption = preset.sort
        }
        if let fid = preset.baseSavedFilterId, let f = viewModel.savedFilters[fid] {
            selectedFilter = f
        } else {
            selectedFilter = nil
        }
        if CatalogLiveChipFilterSupport.imageSavedFilterSupportsLiveEditor(selectedFilter) {
            mapLiveFragmentToChips(preset.liveFragment)
        } else {
            clearLiveChipsOnly()
        }
        applyLiveFilter(viewModel: viewModel)
    }

    func applyServerSavedFilter(_ f: StashDBViewModel.SavedFilter, viewModel: StashDBViewModel) {
        if let meta = f.stashyCatalogPresetMetadata {
            if let bid = meta.baseSavedFilterId, let base = viewModel.savedFilters[bid] {
                selectedFilter = base
            } else {
                selectedFilter = nil
            }
            if CatalogLiveChipFilterSupport.imageSavedFilterSupportsLiveEditor(selectedFilter) {
                mapLiveFragmentToChips(meta.liveFragment)
            } else {
                clearLiveChipsOnly()
            }
            if let sr = meta.sortRaw, let parsed = StashDBViewModel.ImageSortOption(rawValue: sr), parsed != selectedSortOption {
                if parsed == .random && selectedSortOption == .random {
                    viewModel.refreshRandomSeed()
                }
                selectedSortOption = parsed
            }
        } else {
            selectedFilter = f
            if CatalogLiveChipFilterSupport.imageSavedFilterSupportsLiveEditor(f), let raw = f.filterDict {
                mapLiveFragmentToChips(raw)
            } else {
                clearLiveChipsOnly()
            }
        }
        applyLiveFilter(viewModel: viewModel)
    }

    func handlePresetSelection(_ newId: String, viewModel: StashDBViewModel) {
        guard showFilterSortSheet else { return }
        if newId.isEmpty {
            selectedFilter = nil
            clearLiveChipsOnly()
            applyLiveFilter(viewModel: viewModel)
            return
        }
        if let sid = ListLivePresetTag.parseServerId(newId), let f = viewModel.savedFilters[sid] {
            applyServerSavedFilter(f, viewModel: viewModel)
            return
        }
        if let ls = ListLivePresetTag.parseLocalUUIDString(newId),
           let uuid = UUID(uuidString: ls),
           let preset = localCatalogPresets.first(where: { $0.id == uuid }) {
            applyCatalogPreset(preset, viewModel: viewModel)
        }
    }

    func applyCatalogPresetSelectionFromSheetIfNeeded(viewModel: StashDBViewModel) {
        let newId = catalogPresetRowSelection
        guard !newId.isEmpty else { return }
        if let sid = ListLivePresetTag.parseServerId(newId), let f = viewModel.savedFilters[sid] {
            applyServerSavedFilter(f, viewModel: viewModel)
            return
        }
        if let ls = ListLivePresetTag.parseLocalUUIDString(newId),
           let uuid = UUID(uuidString: ls),
           let preset = localCatalogPresets.first(where: { $0.id == uuid }) {
            applyCatalogPreset(preset, viewModel: viewModel)
            return
        }
        if let uuid = UUID(uuidString: newId),
           let preset = localCatalogPresets.first(where: { $0.id == uuid }) {
            catalogPresetRowSelection = ListLivePresetTag.localRow(uuid)
            applyCatalogPreset(preset, viewModel: viewModel)
        }
    }

    func deletePresetConfirmationText(viewModel: StashDBViewModel) -> String {
        if let sid = ListLivePresetTag.parseServerId(catalogPresetRowSelection),
           let f = viewModel.savedFilters[sid] {
            return "Remove “\(f.name)” from Stash? Other devices will lose this saved filter."
        }
        if let ls = ListLivePresetTag.parseLocalUUIDString(catalogPresetRowSelection),
           let uuid = UUID(uuidString: ls),
           let p = localCatalogPresets.first(where: { $0.id == uuid }) {
            return "Remove “\(p.name)” from this device? This cannot be undone."
        }
        return "Remove this filter? This cannot be undone."
    }

    func savePresetOverwrite(viewModel: StashDBViewModel) {
        let sel = catalogPresetRowSelection
        if let sid = ListLivePresetTag.parseServerId(sel) {
            let name = viewModel.savedFilters[sid]?.name ?? "Filter"
            viewModel.saveCatalogSavedFilter(
                mode: .images,
                randomSeedKind: .images,
                existingId: sid,
                name: name,
                sortRaw: selectedSortOption.rawValue,
                sortField: selectedSortOption.sortField,
                sortDirection: selectedSortOption.direction,
                baseFilter: selectedFilter,
                liveFragment: activeLiveFilterDict
            ) { _ in }
            return
        }
        guard let ls = ListLivePresetTag.parseLocalUUIDString(sel),
              let uuid = UUID(uuidString: ls),
              let index = localCatalogPresets.firstIndex(where: { $0.id == uuid }) else { return }
        let old = localCatalogPresets[index]
        let updated = ImageListLiveFilterPreset(
            id: old.id,
            name: old.name,
            createdAt: old.createdAt,
            sort: selectedSortOption,
            baseSavedFilterId: selectedFilter?.id,
            liveFragment: activeLiveFilterDict
        )
        ImageListLiveFilterPresetStore.upsert(updated)
        refreshLocalPresets()
    }

    func savePresetAs(name: String, viewModel: StashDBViewModel) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        viewModel.saveCatalogSavedFilter(
            mode: .images,
            randomSeedKind: .images,
            existingId: nil,
            name: trimmed,
            sortRaw: selectedSortOption.rawValue,
            sortField: selectedSortOption.sortField,
            sortDirection: selectedSortOption.direction,
            baseFilter: selectedFilter,
            liveFragment: activeLiveFilterDict
        ) { [weak self] result in
            guard let self else { return }
            if case .success(let saved) = result {
                self.catalogPresetRowSelection = ListLivePresetTag.serverRow(saved.id)
                self.showSaveAsCatalogPresetAlert = false
            }
        }
    }

    func renamePreset(to newName: String, viewModel: StashDBViewModel) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let sel = catalogPresetRowSelection
        if let sid = ListLivePresetTag.parseServerId(sel) {
            viewModel.saveCatalogSavedFilter(
                mode: .images,
                randomSeedKind: .images,
                existingId: sid,
                name: trimmed,
                sortRaw: selectedSortOption.rawValue,
                sortField: selectedSortOption.sortField,
                sortDirection: selectedSortOption.direction,
                baseFilter: selectedFilter,
                liveFragment: activeLiveFilterDict
            ) { [weak self] result in
                if case .success = result { self?.showRenameCatalogPresetAlert = false }
            }
            return
        }
        guard let ls = ListLivePresetTag.parseLocalUUIDString(sel),
              let uuid = UUID(uuidString: ls),
              let preset = localCatalogPresets.first(where: { $0.id == uuid }) else { return }
        ImageListLiveFilterPresetStore.upsert(preset.renamed(trimmed))
        refreshLocalPresets()
        showRenameCatalogPresetAlert = false
    }

    func deletePreset(viewModel: StashDBViewModel) {
        let sel = catalogPresetRowSelection
        if let sid = ListLivePresetTag.parseServerId(sel) {
            viewModel.destroySavedSceneFilter(id: sid) { [weak self] result in
                guard let self else { return }
                if case .success = result {
                    if self.selectedFilter?.id == sid { self.selectedFilter = nil }
                    self.catalogPresetRowSelection = ""
                    self.showDeleteCatalogPresetAlert = false
                    self.refetchImages(viewModel: viewModel, initial: true)
                }
            }
            return
        }
        guard let ls = ListLivePresetTag.parseLocalUUIDString(sel),
              let uuid = UUID(uuidString: ls) else { return }
        ImageListLiveFilterPresetStore.remove(id: uuid)
        refreshLocalPresets()
        catalogPresetRowSelection = ""
        showDeleteCatalogPresetAlert = false
    }
}

#endif
