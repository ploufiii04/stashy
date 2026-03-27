#if !os(tvOS)
import Foundation
import Combine
import SwiftUI

class StashSyncManager: ObservableObject {
    static let shared = StashSyncManager()
    
    @Published var currentIntensity: Float = 0.0
    @Published var headIntensity: Float = 0.0
    @Published var isActive: Bool = false

    var isStashSyncEnabled: Bool {
        get { StashVideoSyncManager.shared.isVideoSyncEnabled }
        set { StashVideoSyncManager.shared.isVideoSyncEnabled = newValue }
    }

    // Internal state
    private var cancellables = Set<AnyCancellable>()

    private init() {
        setupFusion()
    }

    private func setupFusion() {
        // Forward hip/body intensity (backwards-compat currentIntensity)
        Publishers.CombineLatest(
            StashVideoSyncManager.shared.$currentIntensity,
            $isActive
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] video, active in
            guard let self = self, active else {
                if !active { self?.currentIntensity = 0 }
                return
            }
            self.currentIntensity = video
        }
        .store(in: &cancellables)

        // Forward head intensity as separate channel
        Publishers.CombineLatest(
            StashVideoSyncManager.shared.$headIntensity,
            $isActive
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] head, active in
            guard let self = self, active else {
                if !active { self?.headIntensity = 0 }
                return
            }
            self.headIntensity = head
        }
        .store(in: &cancellables)
    }
    
    func start() {
        isActive = true
        StashVideoSyncManager.shared.isActive = true
    }
    
    func stop() {
        isActive = false
        currentIntensity = 0
        headIntensity = 0
    }
    
    func toggle() {
        let isCurrentlySyncing = HandyManager.shared.isStashSyncMode || ButtplugManager.shared.isStashSyncMode || LoveSpouseManager.shared.isStashSyncMode
        let newValue = !isCurrentlySyncing
        print("⚡ StashSyncManager.toggle() — newValue:\(newValue) handy.enabled:\(HandyManager.shared.isEnabled) handy.connected:\(HandyManager.shared.isConnected)")

        HandyManager.shared.isStashSyncMode = newValue
        ButtplugManager.shared.isStashSyncMode = newValue
        LoveSpouseManager.shared.isStashSyncMode = newValue

        if newValue {
            start()
        } else {
            stop()
        }
    }
}
#else
import Foundation
import SwiftUI
import Combine

class StashSyncManager: ObservableObject {
    static let shared = StashSyncManager()
    @Published var currentIntensity: Float = 0.0
    @Published var isActive: Bool = false
    
    private init() {}
    func start() {}
    func stop() {}
}
#endif
