//
//  DashboardSettingsView.swift
//  stashy
//
//  Created by Daniel Goletz on 06.02.26.
//

#if !os(tvOS)
import SwiftUI

struct DashboardSettingsView: View {
    @ObservedObject var tabManager = TabManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @StateObject private var viewModel = StashDBViewModel()
    @State private var showingAddRowSheet = false
    @State private var selectedFilterId: String = ""
    @State private var selectedCategory: AppTab = .scenes

    var body: some View {
        List {
            Section {
                Toggle("Compact Statistics", isOn: Binding(
                    get: { tabManager.useCompactStatistics },
                    set: { tabManager.useCompactStatistics = $0 }
                ))
                .tint(appearanceManager.tintColor)
            } footer: {
                Text("Show statistics as a single compact card with a 2-column layout instead of a horizontal scrolling row.")
            }
            .listRowBackground(Color.secondaryAppBackground)

            Section {
                Toggle("Big Hero Layout", isOn: Binding(
                    get: { tabManager.dashboardHeroSize == .big },
                    set: { tabManager.dashboardHeroSize = $0 ? .big : .small }
                ))
                .tint(appearanceManager.tintColor)
            } footer: {
                Text("Enable Big Hero to show one item at a time with full-width paging. If disabled, a standard carousel will be shown.")
            }
            .listRowBackground(Color.secondaryAppBackground)
            
            Section {
                ForEach(tabManager.homeRows) { row in
                    HStack {
                        if row.type == .savedFilter {
                            Button(action: { tabManager.removeSavedFilterRow(row.id) }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Toggle(isOn: Binding(
                            get: { row.isEnabled },
                            set: { _ in tabManager.toggleHomeRow(row.id) }
                        )) {
                            VStack(alignment: .leading) {
                                Text(row.title)
                                if row.type == .savedFilter {
                                    Text(row.category?.title ?? "")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .tint(appearanceManager.tintColor)
                    }
                }
                .onMove { indices, newOffset in
                    tabManager.moveHomeRow(from: indices, to: newOffset)
                }
                
                Button(action: { showingAddRowSheet = true }) {
                    Label("Add from Saved Filters", systemImage: "plus.circle.fill")
                        .foregroundColor(appearanceManager.tintColor)
                }
            } footer: {
                Text("Enable and reorder the rows shown on the Dashboard. Standard rows can be toggled, custom filter rows can be deleted.")
            }
            .listRowBackground(Color.secondaryAppBackground)
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Dashboard")
        .applyAppBackground()
        .sheet(isPresented: $showingAddRowSheet) {
            NavigationView {
                Form {
                    Section("Category") {
                        Picker("Category", selection: $selectedCategory) {
                            Text("Scenes").tag(AppTab.scenes)
                            Text("Performers").tag(AppTab.performers)
                            Text("Studios").tag(AppTab.studios)
                            Text("Galleries").tag(AppTab.galleries)
                            Text("Images").tag(AppTab.images)
                            Text("Groups").tag(AppTab.groups)
                            Text("Reels").tag(AppTab.reels)
                        }
                    }
                    
                    Section("Filter") {
                        let filters = viewModel.savedFilters.values
                            .filter { filter in
                                switch selectedCategory {
                                case .scenes: return filter.mode == .scenes
                                case .performers: return filter.mode == .performers
                                case .studios: return filter.mode == .studios
                                case .galleries: return filter.mode == .galleries
                                case .images: return filter.mode == .images
                                case .groups: return filter.mode == .groups
                                case .reels: return filter.mode == .markers
                                default: return false
                                }
                            }
                            .sorted { $0.name < $1.name }
                        
                        if filters.isEmpty {
                            Text("No saved filters found for this category")
                                .foregroundColor(.secondary)
                        } else {
                            Picker("Filter", selection: $selectedFilterId) {
                                Text("Select a filter").tag("")
                                ForEach(filters) { filter in
                                    Text(filter.name).tag(filter.id)
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Add Dashboard Row")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") { showingAddRowSheet = false }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Add") {
                            if let filter = viewModel.savedFilters[selectedFilterId] {
                                tabManager.addSavedFilterRow(title: filter.name, filterId: filter.id, category: selectedCategory)
                                showingAddRowSheet = false
                            }
                        }
                        .disabled(selectedFilterId.isEmpty)
                    }
                }
                .onAppear {
                    viewModel.fetchSavedFilters()
                }
            }
        }
    }
}
#endif
