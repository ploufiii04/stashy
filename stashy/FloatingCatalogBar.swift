#if !os(tvOS)
import SwiftUI

// MARK: - Floating action bar (bottom inset, avoids tab bar)

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
    /// Adds a floating action bar above the tab bar using safeAreaInset.
    func floatingActionBar<Content: View>(isPresented: Bool = true, @ViewBuilder _ content: @escaping () -> Content) -> some View {
        Group {
            if isPresented {
                self.safeAreaInset(edge: .bottom, spacing: 0) {
                    FloatingActionBar(content: content)
                }
            } else {
                self
            }
        }
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
