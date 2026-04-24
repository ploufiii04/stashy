//
//  ListCatalogFilterSortModels.swift
//  stashy
//
//  Shared preset picker tags, local presets, and SavedFilter metadata for
//  Performers / Tags / Studios catalog "Filter & Sort" sheets.
//

#if !os(tvOS)
import Foundation

// MARK: - Preset picker row ids (`""` | `server:<stashId>` | `local:<uuid>`)

enum ListLivePresetTag {
    static let serverPrefix = "server:"
    static let localPrefix = "local:"

    static func serverRow(_ id: String) -> String { serverPrefix + id }
    static func localRow(_ uuid: UUID) -> String { localPrefix + uuid.uuidString }

    static func parseServerId(_ tagged: String) -> String? {
        guard tagged.hasPrefix(serverPrefix) else { return nil }
        return String(tagged.dropFirst(serverPrefix.count))
    }

    static func parseLocalUUIDString(_ tagged: String) -> String? {
        guard tagged.hasPrefix(localPrefix) else { return nil }
        return String(tagged.dropFirst(localPrefix.count))
    }

    static func migrateLegacySelection(_ selection: inout String) {
        let s = selection
        guard !s.isEmpty, !s.contains(":"), UUID(uuidString: s) != nil else { return }
        selection = localPrefix + s
    }
}

// MARK: - JSON helpers (SavedFilter ui_options)

private func catalogJsonObjectAsStringKeyedDict(_ value: Any?) -> [String: Any]? {
    guard let value else { return nil }
    if let d = value as? [String: Any] { return d }
    if let ns = value as? NSDictionary {
        var out: [String: Any] = [:]
        for (k, v) in ns {
            guard let ks = k as? String else { continue }
            out[ks] = v
        }
        return out
    }
    return nil
}

private func catalogJsonValueAsNonEmptyString(_ value: Any?) -> String? {
    if let s = value as? String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
    if let s = value as? NSString {
        let t = (s as String).trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
    return nil
}

extension StashDBViewModel.SavedFilter {
    /// Metadata written by stashy when saving a catalog list preset to the server (`ui_options.stashy`).
    struct StashyCatalogPresetMetadata {
        var baseSavedFilterId: String?
        var liveFragment: [String: Any]
        var sortRaw: String?
    }

    var stashyCatalogPresetMetadata: StashyCatalogPresetMetadata? {
        guard let ui = catalogJsonObjectAsStringKeyedDict(ui_options?.value),
              let stashy = catalogJsonObjectAsStringKeyedDict(ui["stashy"]) else { return nil }
        let base = stashy["baseSavedFilterId"] as? String
        let live = catalogJsonObjectAsStringKeyedDict(stashy["liveFragment"]) ?? [:]
        let sortRaw = catalogJsonValueAsNonEmptyString(stashy["sortRaw"])
        return StashyCatalogPresetMetadata(baseSavedFilterId: base, liveFragment: live, sortRaw: sortRaw)
    }
}

// MARK: - Performer local presets

struct PerformerListLiveFilterPreset: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var createdAt: Date
    var sortRaw: String
    var baseSavedFilterId: String?
    var liveFragmentJSON: String

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        sort: StashDBViewModel.PerformerSortOption,
        baseSavedFilterId: String?,
        liveFragment: [String: Any]
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.sortRaw = sort.rawValue
        self.baseSavedFilterId = baseSavedFilterId
        if JSONSerialization.isValidJSONObject(liveFragment),
           let data = try? JSONSerialization.data(withJSONObject: liveFragment, options: []),
           let json = String(data: data, encoding: .utf8) {
            self.liveFragmentJSON = json
        } else {
            self.liveFragmentJSON = "{}"
        }
    }

    var sort: StashDBViewModel.PerformerSortOption {
        StashDBViewModel.PerformerSortOption(rawValue: sortRaw) ?? .sceneCountDesc
    }

    var liveFragment: [String: Any] {
        guard let data = liveFragmentJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return obj
    }

    func renamed(_ newName: String) -> PerformerListLiveFilterPreset {
        PerformerListLiveFilterPreset(
            id: id,
            name: newName,
            createdAt: createdAt,
            sort: sort,
            baseSavedFilterId: baseSavedFilterId,
            liveFragment: liveFragment
        )
    }
}

enum PerformerListLiveFilterPresetStore {
    private static func storageKey(serverId: UUID) -> String {
        "stashy_performer_catalog_live_filter_presets_\(serverId.uuidString)"
    }

    static func loadPresets() -> [PerformerListLiveFilterPreset] {
        guard let serverId = ServerConfigManager.shared.activeConfig?.id else { return [] }
        let key = storageKey(serverId: serverId)
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([PerformerListLiveFilterPreset].self, from: data)) ?? []
    }

    private static func saveAll(_ presets: [PerformerListLiveFilterPreset]) {
        guard let serverId = ServerConfigManager.shared.activeConfig?.id else { return }
        let key = storageKey(serverId: serverId)
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func upsert(_ preset: PerformerListLiveFilterPreset) {
        var all = loadPresets()
        if let idx = all.firstIndex(where: { $0.id == preset.id }) {
            all[idx] = preset
        } else {
            all.append(preset)
        }
        all.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        saveAll(all)
    }

    static func remove(id: UUID) {
        var all = loadPresets()
        all.removeAll { $0.id == id }
        saveAll(all)
    }
}

// MARK: - Tag local presets

struct TagListLiveFilterPreset: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var createdAt: Date
    var sortRaw: String
    var baseSavedFilterId: String?
    var liveFragmentJSON: String

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        sort: StashDBViewModel.TagSortOption,
        baseSavedFilterId: String?,
        liveFragment: [String: Any]
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.sortRaw = sort.rawValue
        self.baseSavedFilterId = baseSavedFilterId
        if JSONSerialization.isValidJSONObject(liveFragment),
           let data = try? JSONSerialization.data(withJSONObject: liveFragment, options: []),
           let json = String(data: data, encoding: .utf8) {
            self.liveFragmentJSON = json
        } else {
            self.liveFragmentJSON = "{}"
        }
    }

    var sort: StashDBViewModel.TagSortOption {
        StashDBViewModel.TagSortOption(rawValue: sortRaw) ?? .sceneCountDesc
    }

    var liveFragment: [String: Any] {
        guard let data = liveFragmentJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return obj
    }

    func renamed(_ newName: String) -> TagListLiveFilterPreset {
        TagListLiveFilterPreset(
            id: id,
            name: newName,
            createdAt: createdAt,
            sort: sort,
            baseSavedFilterId: baseSavedFilterId,
            liveFragment: liveFragment
        )
    }
}

enum TagListLiveFilterPresetStore {
    private static func storageKey(serverId: UUID) -> String {
        "stashy_tag_catalog_live_filter_presets_\(serverId.uuidString)"
    }

    static func loadPresets() -> [TagListLiveFilterPreset] {
        guard let serverId = ServerConfigManager.shared.activeConfig?.id else { return [] }
        let key = storageKey(serverId: serverId)
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([TagListLiveFilterPreset].self, from: data)) ?? []
    }

    private static func saveAll(_ presets: [TagListLiveFilterPreset]) {
        guard let serverId = ServerConfigManager.shared.activeConfig?.id else { return }
        let key = storageKey(serverId: serverId)
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func upsert(_ preset: TagListLiveFilterPreset) {
        var all = loadPresets()
        if let idx = all.firstIndex(where: { $0.id == preset.id }) {
            all[idx] = preset
        } else {
            all.append(preset)
        }
        all.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        saveAll(all)
    }

    static func remove(id: UUID) {
        var all = loadPresets()
        all.removeAll { $0.id == id }
        saveAll(all)
    }
}

// MARK: - Studio local presets

struct StudioListLiveFilterPreset: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var createdAt: Date
    var sortRaw: String
    var baseSavedFilterId: String?
    var liveFragmentJSON: String

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        sort: StashDBViewModel.StudioSortOption,
        baseSavedFilterId: String?,
        liveFragment: [String: Any]
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.sortRaw = sort.rawValue
        self.baseSavedFilterId = baseSavedFilterId
        if JSONSerialization.isValidJSONObject(liveFragment),
           let data = try? JSONSerialization.data(withJSONObject: liveFragment, options: []),
           let json = String(data: data, encoding: .utf8) {
            self.liveFragmentJSON = json
        } else {
            self.liveFragmentJSON = "{}"
        }
    }

    var sort: StashDBViewModel.StudioSortOption {
        StashDBViewModel.StudioSortOption(rawValue: sortRaw) ?? .nameAsc
    }

    var liveFragment: [String: Any] {
        guard let data = liveFragmentJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return obj
    }

    func renamed(_ newName: String) -> StudioListLiveFilterPreset {
        StudioListLiveFilterPreset(
            id: id,
            name: newName,
            createdAt: createdAt,
            sort: sort,
            baseSavedFilterId: baseSavedFilterId,
            liveFragment: liveFragment
        )
    }
}

enum StudioListLiveFilterPresetStore {
    private static func storageKey(serverId: UUID) -> String {
        "stashy_studio_catalog_live_filter_presets_\(serverId.uuidString)"
    }

    static func loadPresets() -> [StudioListLiveFilterPreset] {
        guard let serverId = ServerConfigManager.shared.activeConfig?.id else { return [] }
        let key = storageKey(serverId: serverId)
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([StudioListLiveFilterPreset].self, from: data)) ?? []
    }

    private static func saveAll(_ presets: [StudioListLiveFilterPreset]) {
        guard let serverId = ServerConfigManager.shared.activeConfig?.id else { return }
        let key = storageKey(serverId: serverId)
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func upsert(_ preset: StudioListLiveFilterPreset) {
        var all = loadPresets()
        if let idx = all.firstIndex(where: { $0.id == preset.id }) {
            all[idx] = preset
        } else {
            all.append(preset)
        }
        all.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        saveAll(all)
    }

    static func remove(id: UUID) {
        var all = loadPresets()
        all.removeAll { $0.id == id }
        saveAll(all)
    }
}

// MARK: - When to show live chip rows vs. server-only notice

enum CatalogLiveChipFilterSupport {
    static func performerSavedFilterSupportsLiveEditor(_ filter: StashDBViewModel.SavedFilter?) -> Bool {
        guard let dict = filter?.filterDict, !dict.isEmpty else { return true }
        if dict.keys.contains(where: { $0 == "AND" || $0 == "OR" || $0 == "NOT" }) { return false }
        let allowed: Set<String> = [
            "birthdate", "hair_color", "gender", "country", "fake_tits", "filter_favorites",
            "is_missing", "has_image", "rating100", "scene_count", "tag_count", "stash_ids"
        ]
        return dict.keys.allSatisfy { allowed.contains($0) }
    }

    static func tagSavedFilterSupportsLiveEditor(_ filter: StashDBViewModel.SavedFilter?) -> Bool {
        guard let dict = filter?.filterDict, !dict.isEmpty else { return true }
        if dict.keys.contains(where: { $0 == "AND" || $0 == "OR" || $0 == "NOT" }) { return false }
        let allowed: Set<String> = ["favorite", "scene_count", "performer_count", "marker_count", "stash_ids"]
        return dict.keys.allSatisfy { allowed.contains($0) }
    }

    static func studioSavedFilterSupportsLiveEditor(_ filter: StashDBViewModel.SavedFilter?) -> Bool {
        guard let dict = filter?.filterDict, !dict.isEmpty else { return true }
        if dict.keys.contains(where: { $0 == "AND" || $0 == "OR" || $0 == "NOT" }) { return false }
        let allowed: Set<String> = ["favorite", "rating100", "scene_count", "details", "stash_ids"]
        return dict.keys.allSatisfy { allowed.contains($0) }
    }

    static func gallerySavedFilterSupportsLiveEditor(_ filter: StashDBViewModel.SavedFilter?) -> Bool {
        guard let dict = filter?.filterDict, !dict.isEmpty else { return true }
        if dict.keys.contains(where: { $0 == "AND" || $0 == "OR" || $0 == "NOT" }) { return false }
        let allowed: Set<String> = ["favorite", "rating100", "file_count", "path", "details", "stash_ids"]
        return dict.keys.allSatisfy { allowed.contains($0) }
    }

    static func imageSavedFilterSupportsLiveEditor(_ filter: StashDBViewModel.SavedFilter?) -> Bool {
        guard let dict = filter?.filterDict, !dict.isEmpty else { return true }
        if dict.keys.contains(where: { $0 == "AND" || $0 == "OR" || $0 == "NOT" }) { return false }
        let allowed: Set<String> = ["favorite", "rating100", "organized", "is_missing", "path", "stash_ids"]
        return dict.keys.allSatisfy { allowed.contains($0) }
    }
}

// MARK: - Gallery local presets

struct GalleryListLiveFilterPreset: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var createdAt: Date
    var sortRaw: String
    var baseSavedFilterId: String?
    var liveFragmentJSON: String

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        sort: StashDBViewModel.GallerySortOption,
        baseSavedFilterId: String?,
        liveFragment: [String: Any]
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.sortRaw = sort.rawValue
        self.baseSavedFilterId = baseSavedFilterId
        if JSONSerialization.isValidJSONObject(liveFragment),
           let data = try? JSONSerialization.data(withJSONObject: liveFragment, options: []),
           let json = String(data: data, encoding: .utf8) {
            self.liveFragmentJSON = json
        } else {
            self.liveFragmentJSON = "{}"
        }
    }

    var sort: StashDBViewModel.GallerySortOption {
        StashDBViewModel.GallerySortOption(rawValue: sortRaw) ?? .dateDesc
    }

    var liveFragment: [String: Any] {
        guard let data = liveFragmentJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return obj
    }

    func renamed(_ newName: String) -> GalleryListLiveFilterPreset {
        GalleryListLiveFilterPreset(
            id: id,
            name: newName,
            createdAt: createdAt,
            sort: sort,
            baseSavedFilterId: baseSavedFilterId,
            liveFragment: liveFragment
        )
    }
}

enum GalleryListLiveFilterPresetStore {
    private static func storageKey(serverId: UUID) -> String {
        "stashy_gallery_catalog_live_filter_presets_\(serverId.uuidString)"
    }

    static func loadPresets() -> [GalleryListLiveFilterPreset] {
        guard let serverId = ServerConfigManager.shared.activeConfig?.id else { return [] }
        let key = storageKey(serverId: serverId)
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([GalleryListLiveFilterPreset].self, from: data)) ?? []
    }

    private static func saveAll(_ presets: [GalleryListLiveFilterPreset]) {
        guard let serverId = ServerConfigManager.shared.activeConfig?.id else { return }
        let key = storageKey(serverId: serverId)
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func upsert(_ preset: GalleryListLiveFilterPreset) {
        var all = loadPresets()
        if let idx = all.firstIndex(where: { $0.id == preset.id }) {
            all[idx] = preset
        } else {
            all.append(preset)
        }
        all.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        saveAll(all)
    }

    static func remove(id: UUID) {
        var all = loadPresets()
        all.removeAll { $0.id == id }
        saveAll(all)
    }
}

// MARK: - Image local presets

struct ImageListLiveFilterPreset: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var createdAt: Date
    var sortRaw: String
    var baseSavedFilterId: String?
    var liveFragmentJSON: String

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        sort: StashDBViewModel.ImageSortOption,
        baseSavedFilterId: String?,
        liveFragment: [String: Any]
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.sortRaw = sort.rawValue
        self.baseSavedFilterId = baseSavedFilterId
        if JSONSerialization.isValidJSONObject(liveFragment),
           let data = try? JSONSerialization.data(withJSONObject: liveFragment, options: []),
           let json = String(data: data, encoding: .utf8) {
            self.liveFragmentJSON = json
        } else {
            self.liveFragmentJSON = "{}"
        }
    }

    var sort: StashDBViewModel.ImageSortOption {
        StashDBViewModel.ImageSortOption(rawValue: sortRaw) ?? .dateDesc
    }

    var liveFragment: [String: Any] {
        guard let data = liveFragmentJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return obj
    }

    func renamed(_ newName: String) -> ImageListLiveFilterPreset {
        ImageListLiveFilterPreset(
            id: id,
            name: newName,
            createdAt: createdAt,
            sort: sort,
            baseSavedFilterId: baseSavedFilterId,
            liveFragment: liveFragment
        )
    }
}

enum ImageListLiveFilterPresetStore {
    private static func storageKey(serverId: UUID) -> String {
        "stashy_image_catalog_live_filter_presets_\(serverId.uuidString)"
    }

    static func loadPresets() -> [ImageListLiveFilterPreset] {
        guard let serverId = ServerConfigManager.shared.activeConfig?.id else { return [] }
        let key = storageKey(serverId: serverId)
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([ImageListLiveFilterPreset].self, from: data)) ?? []
    }

    private static func saveAll(_ presets: [ImageListLiveFilterPreset]) {
        guard let serverId = ServerConfigManager.shared.activeConfig?.id else { return }
        let key = storageKey(serverId: serverId)
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func upsert(_ preset: ImageListLiveFilterPreset) {
        var all = loadPresets()
        if let idx = all.firstIndex(where: { $0.id == preset.id }) {
            all[idx] = preset
        } else {
            all.append(preset)
        }
        all.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        saveAll(all)
    }

    static func remove(id: UUID) {
        var all = loadPresets()
        all.removeAll { $0.id == id }
        saveAll(all)
    }
}
#endif
