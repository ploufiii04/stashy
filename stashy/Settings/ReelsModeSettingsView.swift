//
//  ReelsModeSettingsView.swift
//  stashy
//
//  Created by Daniel Goletz on 06.02.26.
//

#if !os(tvOS)
import SwiftUI

struct ReelsModeSettingsView: View {
    @ObservedObject var tabManager = TabManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @StateObject private var viewModel = StashDBViewModel()

    @ViewBuilder
    private func reelsSettingRow(title: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 0) {
            Text(title)
                .foregroundColor(.secondary)
                .font(.subheadline)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(minHeight: 36)
    }

    private var isEnabled: Bool {
        tabManager.tabs.first(where: { $0.id == .reels })?.isVisible ?? true
    }

    var body: some View {
        List {
            Section {
                Toggle(isOn: Binding(
                    get: { isEnabled },
                    set: { _ in tabManager.toggle(.reels) }
                )) {
                    Label("Show Feeds Tab", systemImage: "play.rectangle.on.rectangle")
                }
                .tint(appearanceManager.tintColor)
            }
            .listRowBackground(Color.secondaryAppBackground)

            Section {
                Toggle("Immersive Video Scaling", isOn: $tabManager.reelsFillHeight)
                    .tint(appearanceManager.tintColor)
                Toggle("Continuous Play", isOn: $tabManager.reelsContinuousPlay)
                    .tint(appearanceManager.tintColor)
            } footer: {
                Text("Immersive Scaling stretches content to fill the full screen when orientation matches the video. Continuous Play automatically advances to the next video instead of looping.")
            }
            .listRowBackground(Color.secondaryAppBackground)
            
            Section {
                ForEach(tabManager.reelsModes) { modeConfig in
                    VStack(alignment: .leading, spacing: 0) {
                        // Header
                        HStack {
                            Label(modeConfig.type.defaultTitle, systemImage: modeConfig.type.icon)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(appearanceManager.tintColor)

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: { modeConfig.isEnabled },
                                set: { _ in tabManager.toggleReelsMode(modeConfig.type) }
                            ))
                            .labelsHidden()
                            .tint(appearanceManager.tintColor)
                        }

                        if modeConfig.isEnabled {
                            Divider()
                                .padding(.vertical, 8)

                            // Default Sort
                            reelsSettingRow(title: "Default Sort") {
                                sortPicker(for: modeConfig.type)
                            }

                            // Default Filter
                            reelsSettingRow(title: "Default Filter") {
                                filterPicker(for: modeConfig.type)
                            }
                            .padding(.top, 4)

                            if modeConfig.type == .pics {
                                reelsSettingRow(title: "Crop to 4:5 / 16:9") {
                                    Toggle("", isOn: Binding(
                                        get: { UserDefaults.standard.object(forKey: "stashline_crop_enabled") as? Bool ?? true },
                                        set: { UserDefaults.standard.set($0, forKey: "stashline_crop_enabled") }
                                    ))
                                    .labelsHidden()
                                    .tint(appearanceManager.tintColor)
                                }
                                .padding(.top, 4)

                                reelsSettingRow(title: "Load Full Images") {
                                    Toggle("", isOn: Binding(
                                        get: { UserDefaults.standard.object(forKey: "stashline_load_full_images") as? Bool ?? true },
                                        set: { UserDefaults.standard.set($0, forKey: "stashline_load_full_images") }
                                    ))
                                    .labelsHidden()
                                    .tint(appearanceManager.tintColor)
                                }
                                .padding(.top, 4)

                                reelsSettingRow(title: "Group by Orientation") {
                                    Toggle("", isOn: Binding(
                                        get: { UserDefaults.standard.object(forKey: "stashline_group_by_orientation") as? Bool ?? true },
                                        set: { UserDefaults.standard.set($0, forKey: "stashline_group_by_orientation") }
                                    ))
                                    .labelsHidden()
                                    .tint(appearanceManager.tintColor)
                                }
                                .padding(.top, 4)
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    .listRowSeparator(.hidden)
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.small)
                            .fill(Color.secondaryAppBackground)
                            .padding(.vertical, 4)
                    )
                }
                .onMove { indices, newOffset in
                    tabManager.moveReelsMode(from: indices, to: newOffset)
                }
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.active))
        .deleteDisabled(true)
        .navigationTitle("Feeds")
        .applyAppBackground()
        .onAppear {
            viewModel.fetchSavedFilters()
        }
    }

    @ViewBuilder
    private func sortPicker(for type: ReelsModeType) -> some View {
        switch type {
        case .scenes:
            let current = StashDBViewModel.SceneSortOption(rawValue: tabManager.getReelsDefaultSort(for: .scenes) ?? "") ?? .random
            Menu {
                ForEach(StashDBViewModel.SceneSortOption.allCases, id: \.self) { option in
                    Button(action: { tabManager.setReelsDefaultSort(for: .scenes, option: option.rawValue) }) {
                        HStack { Text(option.displayName); if option == current { Image(systemName: "checkmark") } }
                    }
                }
            } label: {
                pickerLabelText(current.displayName)
            }

        case .markers:
            let current = StashDBViewModel.SceneMarkerSortOption(rawValue: tabManager.getReelsDefaultSort(for: .markers) ?? "") ?? .random
            Menu {
                ForEach(StashDBViewModel.SceneMarkerSortOption.allCases, id: \.self) { option in
                    Button(action: { tabManager.setReelsDefaultSort(for: .markers, option: option.rawValue) }) {
                        HStack { Text(option.displayName); if option == current { Image(systemName: "checkmark") } }
                    }
                }
            } label: {
                pickerLabelText(current.displayName)
            }

        case .clips:
            let current = StashDBViewModel.ImageSortOption(rawValue: tabManager.getReelsDefaultSort(for: .clips) ?? "") ?? .random
            Menu {
                ForEach(StashDBViewModel.ImageSortOption.allCases, id: \.self) { option in
                    Button(action: { tabManager.setReelsDefaultSort(for: .clips, option: option.rawValue) }) {
                        HStack { Text(option.displayName); if option == current { Image(systemName: "checkmark") } }
                    }
                }
            } label: {
                pickerLabelText(current.displayName)
            }

        case .previews:
            let current = StashDBViewModel.SceneSortOption(rawValue: tabManager.getReelsDefaultSort(for: .previews) ?? "") ?? .random
            Menu {
                ForEach(StashDBViewModel.SceneSortOption.allCases, id: \.self) { option in
                    Button(action: { tabManager.setReelsDefaultSort(for: .previews, option: option.rawValue) }) {
                        HStack { Text(option.displayName); if option == current { Image(systemName: "checkmark") } }
                    }
                }
            } label: {
                pickerLabelText(current.displayName)
            }

        case .pics:
            let current = StashDBViewModel.ImageSortOption(rawValue: tabManager.getPersistentSortOption(for: .stashline) ?? "") ?? .dateDesc
            Menu {
                ForEach(StashDBViewModel.ImageSortOption.allCases, id: \.self) { option in
                    Button(action: { tabManager.setPersistentSortOption(for: .stashline, option: option.rawValue) }) {
                        HStack { Text(option.displayName); if option == current { Image(systemName: "checkmark") } }
                    }
                }
            } label: {
                pickerLabelText(current.displayName)
            }
        }
    }

    // Menu-style Pickers tend to wrap the label in tight HStacks (List rows).
    // Provide an explicit label view with single-line truncation + min width.
    private func pickerLabelText(_ text: String) -> some View {
        Text(text)
            .foregroundColor(.secondary)
            .font(.subheadline)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    @ViewBuilder
    private func filterPicker(for type: ReelsModeType) -> some View {
        let filterMode: StashDBViewModel.FilterMode = {
            switch type {
            case .scenes, .markers: return .scenes
            case .clips: return .images
            case .previews: return .scenes
            case .pics: return .images
            }
        }()

        let filters = viewModel.savedFilters.values
            .filter { $0.mode == filterMode }
            .sorted { $0.name < $1.name }

        if filters.isEmpty && !viewModel.isLoadingSavedFilters {
            Text("No filters found")
                .foregroundColor(.secondary)
                .font(.subheadline)
        } else {
            switch type {
            case .scenes, .markers:
                // Markers use the same saved scene filters and the same reels default as Scenes (not `sceneMarkers` / `defaultMarkerFilterId`).
                Picker("", selection: Binding(
                    get: { tabManager.getDefaultFilterId(for: .reels) ?? "" },
                    set: { newId in
                        if newId.isEmpty {
                            tabManager.setDefaultFilter(for: .reels, filterId: nil, filterName: nil)
                        } else if let filter = filters.first(where: { $0.id == newId }) {
                            tabManager.setDefaultFilter(for: .reels, filterId: filter.id, filterName: filter.name)
                        }
                    }
                )) {
                    Text("None").tag("")
                    ForEach(filters) { filter in
                        Text(filter.name).tag(filter.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

            case .clips:
                Picker("", selection: Binding(
                    get: { tabManager.getDefaultClipFilterId(for: .reels) ?? "" },
                    set: { newId in
                        if newId.isEmpty {
                            tabManager.setDefaultClipFilter(for: .reels, filterId: nil, filterName: nil)
                        } else if let filter = filters.first(where: { $0.id == newId }) {
                            tabManager.setDefaultClipFilter(for: .reels, filterId: filter.id, filterName: filter.name)
                        }
                    }
                )) {
                    Text("None").tag("")
                    ForEach(filters) { filter in
                        Text(filter.name).tag(filter.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

            case .previews:
                Picker("", selection: Binding(
                    get: { tabManager.getDefaultPreviewFilterId(for: .reels) ?? "" },
                    set: { newId in
                        if newId.isEmpty {
                            tabManager.setDefaultPreviewFilter(for: .reels, filterId: nil, filterName: nil)
                        } else if let filter = filters.first(where: { $0.id == newId }) {
                            tabManager.setDefaultPreviewFilter(for: .reels, filterId: filter.id, filterName: filter.name)
                        }
                    }
                )) {
                    Text("None").tag("")
                    ForEach(filters) { filter in
                        Text(filter.name).tag(filter.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()

            case .pics:
                Picker("", selection: Binding(
                    get: { tabManager.getDefaultFilterId(for: .stashline) ?? "" },
                    set: { newId in
                        if newId.isEmpty {
                            tabManager.setDefaultFilter(for: .stashline, filterId: nil, filterName: nil)
                        } else if let filter = filters.first(where: { $0.id == newId }) {
                            tabManager.setDefaultFilter(for: .stashline, filterId: filter.id, filterName: filter.name)
                        }
                    }
                )) {
                    Text("None").tag("")
                    ForEach(filters) { filter in
                        Text(filter.name).tag(filter.id)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
        }
    }
}
#endif
