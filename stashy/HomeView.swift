#if !os(tvOS)
import SwiftUI
import AVKit

struct HomeView: View {
    @StateObject private var viewModel = StashDBViewModel()
    @ObservedObject var tabManager = TabManager.shared
    @ObservedObject var configManager = ServerConfigManager.shared
    @ObservedObject var appearanceManager = AppearanceManager.shared
    @EnvironmentObject var coordinator: NavigationCoordinator

    var body: some View {
        ZStack {
            if configManager.activeConfig == nil {
                ConnectionErrorView { viewModel.fetchStatistics() }
            } else if viewModel.statistics == nil && viewModel.errorMessage != nil {
                ConnectionErrorView { viewModel.fetchStatistics() }
            } else {
                dashboardContent
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard configManager.activeConfig != nil else { return }
            if viewModel.statistics == nil {
                viewModel.initializeServerConnection()
            } else {
                viewModel.fetchStatistics()
                for row in tabManager.homeRows where row.isEnabled && row.type != .statistics {
                    viewModel.refreshHomeRow(config: row, limit: 10)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ServerConfigChanged"))) { _ in
            viewModel.initializeServerConnection()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SceneResumeTimeUpdated"))) { notification in
            if let sceneId = notification.userInfo?["sceneId"] as? String,
               let resumeTime = notification.userInfo?["resumeTime"] as? Double {
                viewModel.updateSceneResumeTime(id: sceneId, newResumeTime: resumeTime)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SceneDeleted"))) { notification in
            if let sceneId = notification.userInfo?["sceneId"] as? String {
                viewModel.removeScene(id: sceneId)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DefaultFilterChanged"))) { notification in
            if let tabId = notification.userInfo?["tab"] as? String, tabId == AppTab.dashboard.rawValue {
                viewModel.initializeServerConnection()
            }
        }
    }

    @ViewBuilder
    private var dashboardContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                let activeRows = tabManager.homeRows.filter { $0.isEnabled }
                let firstRowId = activeRows.first?.id
                let firstSceneRowId = activeRows.first(where: { $0.type != .statistics })?.id
                
                ForEach(tabManager.homeRows) { row in
                    if row.isEnabled {
                        if row.type == .statistics {
                            HomeStatisticsRowView(viewModel: viewModel, isFirst: row.id == firstRowId)
                        } else {
                            HomeRowView(config: row, 
                                       viewModel: viewModel, 
                                       isLarge: row.id == firstSceneRowId,
                                       isFirst: row.id == firstRowId)
                        }
                    }
                }
            }
            .padding(.bottom, 80)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            viewModel.homeRowScenes.removeAll()
            viewModel.initializeServerConnection()
        }
    }
}
#endif
