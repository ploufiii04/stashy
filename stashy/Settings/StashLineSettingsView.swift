//
//  StashLineSettingsView.swift
//  stashy

#if !os(tvOS)
import SwiftUI

struct StashLineSettingsView: View {
    @ObservedObject var tabManager = TabManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @StateObject private var viewModel = StashDBViewModel()

    private var sortBinding: Binding<StashDBViewModel.ImageSortOption> {
        Binding(
            get: { StashDBViewModel.ImageSortOption(rawValue: tabManager.getPersistentSortOption(for: .stashline) ?? "") ?? .dateDesc },
            set: { tabManager.setPersistentSortOption(for: .stashline, option: $0.rawValue) }
        )
    }

    private var isEnabled: Bool {
        tabManager.tabs.first(where: { $0.id == .stashline })?.isVisible ?? true
    }

    var body: some View {
        List {
            Section {
                Toggle(isOn: Binding(
                    get: { isEnabled },
                    set: { _ in tabManager.toggle(.stashline) }
                )) {
                    Label("Show StashLine Tab", systemImage: "camera.fill")
                }
                .tint(appearanceManager.tintColor)
            }
            .listRowBackground(Color.secondaryAppBackground)

            Section {
                HStack {
                    Label("Sorting", systemImage: "arrow.up.arrow.down")
                    Spacer()
                    Menu {
                        Button(action: { sortBinding.wrappedValue = .random }) {
                            HStack { Text("Random"); if sortBinding.wrappedValue == .random { Image(systemName: "checkmark") } }
                        }
                        Divider()
                        Menu {
                            Button(action: { sortBinding.wrappedValue = .dateDesc }) {
                                HStack { Text("Newest First"); if sortBinding.wrappedValue == .dateDesc { Image(systemName: "checkmark") } }
                            }
                            Button(action: { sortBinding.wrappedValue = .dateAsc }) {
                                HStack { Text("Oldest First"); if sortBinding.wrappedValue == .dateAsc { Image(systemName: "checkmark") } }
                            }
                        } label: {
                            HStack { Text("Date"); if sortBinding.wrappedValue == .dateAsc || sortBinding.wrappedValue == .dateDesc { Image(systemName: "checkmark") } }
                        }
                        Menu {
                            Button(action: { sortBinding.wrappedValue = .ratingDesc }) {
                                HStack { Text("High → Low"); if sortBinding.wrappedValue == .ratingDesc { Image(systemName: "checkmark") } }
                            }
                            Button(action: { sortBinding.wrappedValue = .ratingAsc }) {
                                HStack { Text("Low → High"); if sortBinding.wrappedValue == .ratingAsc { Image(systemName: "checkmark") } }
                            }
                        } label: {
                            HStack { Text("Rating"); if sortBinding.wrappedValue == .ratingAsc || sortBinding.wrappedValue == .ratingDesc { Image(systemName: "checkmark") } }
                        }
                        Menu {
                            Button(action: { sortBinding.wrappedValue = .createdAtDesc }) {
                                HStack { Text("Newest First"); if sortBinding.wrappedValue == .createdAtDesc { Image(systemName: "checkmark") } }
                            }
                            Button(action: { sortBinding.wrappedValue = .createdAtAsc }) {
                                HStack { Text("Oldest First"); if sortBinding.wrappedValue == .createdAtAsc { Image(systemName: "checkmark") } }
                            }
                        } label: {
                            HStack { Text("Created"); if sortBinding.wrappedValue == .createdAtAsc || sortBinding.wrappedValue == .createdAtDesc { Image(systemName: "checkmark") } }
                        }
                        Menu {
                            Button(action: { sortBinding.wrappedValue = .updatedAtDesc }) {
                                HStack { Text("Recently Updated"); if sortBinding.wrappedValue == .updatedAtDesc { Image(systemName: "checkmark") } }
                            }
                            Button(action: { sortBinding.wrappedValue = .updatedAtAsc }) {
                                HStack { Text("Least Recently"); if sortBinding.wrappedValue == .updatedAtAsc { Image(systemName: "checkmark") } }
                            }
                        } label: {
                            HStack { Text("Updated"); if sortBinding.wrappedValue == .updatedAtAsc || sortBinding.wrappedValue == .updatedAtDesc { Image(systemName: "checkmark") } }
                        }
                    } label: {
                        Text(sortBinding.wrappedValue.displayName).foregroundColor(.secondary)
                    }
                }
            } header: {
                Text("Sorting")
            }
            .listRowBackground(Color.secondaryAppBackground)

            Section {
                filterPicker
            } header: {
                Text("Default Filter")
            }
            .listRowBackground(Color.secondaryAppBackground)
        }
        .listStyle(.insetGrouped)
        .navigationTitle("StashLine")
        .navigationBarTitleDisplayMode(.inline)
        .applyAppBackground()
        .scrollContentBackground(.hidden)
        .toolbar {
            if viewModel.isLoadingSavedFilters {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .shimmer()
                }
            }
        }
        .onAppear {
            viewModel.fetchSavedFilters()
        }
    }

    @ViewBuilder
    private var filterPicker: some View {
        let filters = viewModel.savedFilters.values
            .filter { $0.mode == .images }
            .sorted { $0.name < $1.name }

        let currentId = tabManager.getDefaultFilterId(for: .stashline)
        let currentName = tabManager.getDefaultFilterName(for: .stashline)

        HStack {
            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
            Spacer()

            if filters.isEmpty && !viewModel.isLoadingSavedFilters {
                Text("No filters found")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
            } else {
                Menu {
                    Button(action: {
                        tabManager.setDefaultFilter(for: .stashline, filterId: nil, filterName: nil)
                    }) {
                        HStack { Text("None"); if currentId == nil { Image(systemName: "checkmark") } }
                    }
                    Divider()
                    ForEach(filters) { filter in
                        Button(action: {
                            tabManager.setDefaultFilter(for: .stashline, filterId: filter.id, filterName: filter.name)
                        }) {
                            HStack { Text(filter.name); if currentId == filter.id { Image(systemName: "checkmark") } }
                        }
                    }
                } label: {
                    Text(currentName ?? "None").foregroundColor(.secondary)
                }
            }
        }
    }
}
#endif
