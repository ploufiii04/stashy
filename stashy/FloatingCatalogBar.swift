#if !os(tvOS)
import SwiftUI

// MARK: - Footer-Bar bei Verbindungsfehler (einheitlich für Katalog- und Detail-Listen)

/// Eingaben für die gemeinsame Regel: Floating-Bar aus, wenn kein Server aktiv ist oder die aktuelle Liste leer ist
/// und ein Fehler angezeigt wird (typisch `ConnectionErrorView`).
struct CatalogFloatingChromeState: Equatable {
    var hasActiveServerConfig: Bool
    var primaryListIsEmpty: Bool
    var errorMessage: String?
    var imageFindListError: String? = nil

    /// `isPresented`: z. B. `showsFloatingFilterButton` — wird zusätzlich zur Fehlerlogik ausgewertet.
    func floatingBarVisible(isPresented: Bool) -> Bool {
        guard isPresented else { return false }
        guard hasActiveServerConfig else { return false }
        if primaryListIsEmpty, errorMessage != nil || imageFindListError != nil {
            return false
        }
        return true
    }
}

struct FloatingActionBar<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
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
            .padding(.horizontal, 24)
            .padding(.bottom, 6)
    }
}

extension View {
    /// Floating-Bar über `safeAreaInset`. Mit `catalogChrome` wird sie bei fehlendem Server / leerer Liste + Fehler ausgeblendet.
    func floatingActionBar<Content: View>(
        isPresented: Bool = true,
        catalogChrome: CatalogFloatingChromeState? = nil,
        @ViewBuilder _ content: @escaping () -> Content
    ) -> some View {
        let showBar = catalogChrome?.floatingBarVisible(isPresented: isPresented) ?? isPresented
        return Group {
            if showBar {
                self.safeAreaInset(edge: .bottom, spacing: 0) {
                    FloatingActionBar(content: content)
                }
            } else {
                self
            }
        }
    }

    /// Kurzform ohne Fehler-Logik (z. B. rein dekorative Bars).
    func floatingActionBar<Content: View>(@ViewBuilder _ content: @escaping () -> Content) -> some View {
        floatingActionBar(isPresented: true, catalogChrome: nil, content)
    }
}

// MARK: - Category row (in-navbar style, horizontal)

private let catalogRowVisibleMax = 4

struct CatalogCategoryRow: View {
    let tabs: [CatalogsView.CatalogsTab]
    @Binding var selection: CatalogsView.CatalogsTab

    @ObservedObject private var appearance = AppearanceManager.shared

    private var visibleTabs: [CatalogsView.CatalogsTab] { Array(tabs.prefix(catalogRowVisibleMax)) }
    private var overflowTabs: [CatalogsView.CatalogsTab] { tabs.count > catalogRowVisibleMax ? Array(tabs.dropFirst(catalogRowVisibleMax)) : [] }
    private var overflowIsActive: Bool { overflowTabs.contains(selection) }

    var body: some View {
        HStack(spacing: 8) {
            // Fixed-width title label for active tab
            Text(selection.rawValue)
                .font(.system(size: 18, weight: .semibold))
                .lineLimit(1)
                .frame(width: 120, alignment: .leading)

            ForEach(visibleTabs, id: \.self) { tab in
                button(for: tab)
            }
            if !overflowTabs.isEmpty {
                Menu {
                    ForEach(overflowTabs, id: \.self) { tab in
                        Button(action: { selection = tab }) {
                            HStack {
                                Label(tab.rawValue, systemImage: tab.icon)
                                Spacer()
                                if tab == selection {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: overflowIsActive ? "ellipsis.circle.fill" : "ellipsis.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(overflowIsActive ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 9)
                                .fill(overflowIsActive ? appearance.tintColor : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func button(for tab: CatalogsView.CatalogsTab) -> some View {
        let isActive = tab == selection
        Button(action: { selection = tab }) {
            Image(systemName: tab.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(isActive ? .white : .primary)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(isActive ? appearance.tintColor : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.rawValue)
    }
}
#endif
