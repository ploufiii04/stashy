#if !os(tvOS)
import SwiftUI

struct EditModeSettingsView: View {
    @ObservedObject var appearanceManager = AppearanceManager.shared

    var body: some View {
        List {
            Section(footer: Text("Show edit buttons on scene detail cards for performers, studio, groups, tags, title and description.")) {
                Toggle("Enable Editing", isOn: $appearanceManager.isEditModeEnabled)
                    .tint(appearanceManager.tintColor)
            }
            .listRowBackground(
                RoundedRectangle(cornerRadius: DesignTokens.CornerRadius.card)
                    .fill(Color.secondaryAppBackground)
            )
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Editing")
        .applyAppBackground()
        .scrollContentBackground(.hidden)
    }
}
#endif
