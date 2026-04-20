//
//  ServerStatisticsView.swift
//  stashy
//
//  Created by Daniel Goletz on 06.02.26.
//

import SwiftUI

struct ServerStatisticsView: View {
    @ObservedObject var viewModel: StashDBViewModel
    @ObservedObject private var configManager = ServerConfigManager.shared
    @State private var hasAttemptedLoad = false
    @State private var didFailLoad = false

    var body: some View {
        Group {
            if configManager.activeConfig == nil {
                ConnectionErrorView { reload() }
            } else if viewModel.statistics != nil {
                List {
                    if let stats = viewModel.statistics {
                        Section("Catalogs") {
                            statRow("Scenes", value: "\(stats.sceneCount)")
                            statRow("Markers", value: "\(stats.sceneMarkerCount ?? 0)")
                            statRow("Studios", value: "\(stats.studioCount)")
                            statRow("Groups", value: "\(stats.groupCount)")
                            statRow("Tags", value: "\(stats.tagCount)")
                        }
                        .listRowBackground(Color.secondaryAppBackground)

                        Section("Usage") {
                            statRow("Total Size", value: formatBytes(stats.scenesSize))
                            statRow("Total Duration", value: formatDuration(stats.scenesDuration))
                            statRow("Total O-Count", value: "\(stats.totalOCount)")
                            statRow("Total Play Count", value: "\(stats.totalPlayCount)")
                            statRow("Scenes Played", value: "\(stats.scenesPlayed)")
                        }
                        .listRowBackground(Color.secondaryAppBackground)

                        Section("Performers") {
                            statRow("Total", value: "\(stats.performerCount)")

                            if viewModel.isLoadingPerformerGenderCounts {
                                HStack { Spacer(); ProgressView("Loading gender distribution..."); Spacer() }
                                    .padding(.vertical, 8)
                            } else {
                                let sorted = viewModel.performerGenderCounts
                                    .filter { $0.value > 0 }
                                    .sorted { lhs, rhs in
                                        if lhs.value != rhs.value { return lhs.value > rhs.value }
                                        return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
                                    }

                                if sorted.isEmpty {
                                    Text("No gender data available.")
                                        .foregroundColor(.secondary)
                                } else {
                                    ForEach(sorted, id: \.key) { gender, count in
                                        HStack {
                                            Text(displayGender(gender))
                                            Spacer()
                                            Text("\(count)")
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                        .listRowBackground(Color.secondaryAppBackground)
                    }
                }
                .scrollContentBackground(.hidden)
            } else if !hasAttemptedLoad || (!didFailLoad && viewModel.errorMessage == nil) {
                VStack {
                    Spacer()
                    ProgressView("Loading statistics...")
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                ConnectionErrorView { reload() }
            }
        }
        .navigationTitle("Statistics")
        .applyAppBackground()
        .onAppear { reload() }
    }

    private func reload() {
        hasAttemptedLoad = true
        didFailLoad = false
        viewModel.fetchStatistics { success in
            DispatchQueue.main.async {
                self.didFailLoad = !success
            }
        }
        viewModel.fetchPerformerGenderCounts()
    }

    private func displayGender(_ rawKey: String) -> String {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch key {
        case "FEMALE": return "Female"
        case "MALE": return "Male"
        case "TRANSGENDER_FEMALE": return "Transgender (Female)"
        case "TRANSGENDER_MALE": return "Transgender (Male)"
        case "INTERSEX": return "Intersex"
        case "NON_BINARY", "NON-BINARY", "NONBINARY": return "Non-binary"
        case "UNKNOWN", "UNSPECIFIED": return "Unknown"
        default:
            // Fallback: pretty-print unknown keys like "GENDERQUEER" / "SOME_VALUE"
            let pretty = key
                .replacingOccurrences(of: "_", with: " ")
                .lowercased()
                .capitalized
            return pretty
        }
    }

    private func statRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }

    private func formatBytes(_ bytes: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
}
