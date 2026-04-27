//
//  TVSearchView.swift
//  stashyTV
//
//  Search for tvOS — Netflix style
//

import SwiftUI

@MainActor
struct TVSearchView: View {
    @StateObject private var viewModel = StashDBViewModel()

    @State private var searchQuery: String = ""
    @State private var hasSearched: Bool = false
    @FocusState private var isSearchFieldFocused: Bool
    @State private var searchDebounceTask: Task<Void, Never>?

    private var isSearchBusy: Bool {
        viewModel.isLoadingScenes || viewModel.isLoadingPerformers
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 44) {
                searchBar

                if isSearchBusy {
                    loadingBlock
                } else if hasSearched && viewModel.scenes.isEmpty && viewModel.performers.isEmpty {
                    emptyResultsBlock
                } else if hasSearched {
                    if !viewModel.scenes.isEmpty {
                        scenesResultSection
                    }
                    if !viewModel.performers.isEmpty {
                        performersResultSection
                    }
                } else {
                    placeholderBlock
                }
            }
            .padding(.vertical, 48)
            .padding(.horizontal, 40)
        }
        .background(Color.appBackground)
        .onAppear {
            // Kurz verzögern, damit die Fokus-Engine den Tab gewählt hat.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isSearchFieldFocused = true
            }
        }
        .onChange(of: searchQuery) { _, newValue in
            scheduleDebouncedSearch(newValue)
        }
        .onDisappear {
            searchDebounceTask?.cancel()
            searchDebounceTask = nil
        }
    }

    // MARK: - Search bar (eigenes Feld: Fokus bleibt erreichbar, kein „Festfrieren“ hinter .searchable)

    private var searchBar: some View {
        HStack(alignment: .center, spacing: 28) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)

            TextField("Szenen, Performer …", text: $searchQuery)
                .font(.title3)
                .foregroundStyle(.primary)
                .focused($isSearchFieldFocused)
                .submitLabel(.search)
                .onSubmit { commitSearchImmediately() }

            if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    searchDebounceTask?.cancel()
                    searchQuery = ""
                    hasSearched = false
                    viewModel.clearSearchResults()
                    isSearchFieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Eingabe löschen")
            }
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 28)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var loadingBlock: some View {
        HStack {
            Spacer()
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                Text("Suche läuft …")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.4))
            }
            Spacer()
        }
        .padding(.top, 40)
    }

    private var emptyResultsBlock: some View {
        HStack {
            Spacer()
            VStack(spacing: 20) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 56))
                    .foregroundColor(.white.opacity(0.12))
                Text("Keine Treffer für „\(searchQuery)“")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.4))
                Button("Suche anpassen") {
                    isSearchFieldFocused = true
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        }
        .padding(.top, 40)
    }

    private var placeholderBlock: some View {
        HStack {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 56))
                    .foregroundColor(.white.opacity(0.12))
                Text("Stash-Bibliothek durchsuchen")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.4))
                Text("Mindestens zwei Zeichen, Remote oder Diktat.")
                    .font(.callout)
                    .foregroundColor(.white.opacity(0.25))
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(.top, 60)
    }

    // MARK: - Debounce & ausführen

    private func scheduleDebouncedSearch(_ raw: String) {
        searchDebounceTask?.cancel()
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 2 {
            viewModel.clearSearchResults()
            hasSearched = false
            return
        }
        searchDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled else { return }
            runSearch(trimmed: trimmed)
        }
    }

    private func commitSearchImmediately() {
        searchDebounceTask?.cancel()
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            viewModel.clearSearchResults()
            hasSearched = false
            return
        }
        runSearch(trimmed: trimmed)
    }

    private func runSearch(trimmed: String) {
        hasSearched = true
        viewModel.fetchScenes(sortBy: StashDBViewModel.SceneSortOption.dateDesc, searchQuery: trimmed)
        viewModel.fetchPerformers(sortBy: StashDBViewModel.PerformerSortOption.nameAsc, searchQuery: trimmed)
    }

    // MARK: - Scenes Results

    private var scenesResultSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "film.fill")
                    .font(.title3)
                    .foregroundColor(AppearanceManager.shared.tintColor)
                Text("Szenen")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Text("\(viewModel.scenes.count)")
                    .font(.callout)
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 50)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 30) {
                    ForEach(viewModel.scenes) { scene in
                        VStack(alignment: .leading, spacing: 10) {
                            NavigationLink(value: TVSceneLink(sceneId: scene.id)) {
                                TVSceneCardView(scene: scene)
                            }
                            .buttonStyle(.card)

                            TVSceneCardTitleView(scene: scene)
                        }
                        .frame(width: 400)
                    }
                }
                .padding(.horizontal, 50)
                .padding(.vertical, 20)
            }
        }
    }

    // MARK: - Performers Results

    private var performersResultSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "person.2.fill")
                    .font(.title3)
                    .foregroundColor(AppearanceManager.shared.tintColor)
                Text("Performer")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Text("\(viewModel.performers.count)")
                    .font(.callout)
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.horizontal, 50)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 30) {
                    ForEach(viewModel.performers) { performer in
                        NavigationLink(value: TVPerformerLink(id: performer.id, name: performer.name)) {
                            TVPerformerCardView(performer: performer)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(.horizontal, 50)
                .padding(.vertical, 20)
            }
        }
    }
}
