import Foundation

nonisolated struct SystemLoad: Sendable {
    var thermalState: ProcessInfo.ThermalState
    var lowPower: Bool

    static var current: SystemLoad {
        SystemLoad(thermalState: ProcessInfo.processInfo.thermalState,
                   lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }

    var waitReason: String? {
        switch thermalState {
        case .serious, .critical: return "Mac is hot"
        case .fair: return "Mac is warm"
        default: return lowPower ? "Low Power Mode" : nil
        }
    }
}

// Holds watched-folder and rule jobs from the first warm thermal level (fair) or in Low Power Mode
// (setting, default on). Chip and battery temperatures in degrees are not public API, so macOS's thermal state is used.
// Wakes on the system's thermal and power notifications, with a slow fallback check.
@MainActor
final class LoadGate {
    static let settingKey = "pauseAutomationUnderLoad"
    // On by default in the app; off by default under XCTest so other tests do not depend on the real temperature.
    static let enabledByDefault = NSClassFromString("XCTestCase") == nil
    var current: () -> SystemLoad = { .current }
    private let defaults: UserDefaults
    private let fallback: Duration
    private var waiter: CheckedContinuation<Void, Never>?
    private var fallbackTask: Task<Void, Never>?
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    init(defaults: UserDefaults, fallback: Duration = .seconds(60)) {
        self.defaults = defaults
        self.fallback = fallback
        observers = [ProcessInfo.thermalStateDidChangeNotification, .NSProcessInfoPowerStateDidChange].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.wake() }
            }
        }
    }

    var reason: String? {
        guard defaults.object(forKey: Self.settingKey) as? Bool ?? Self.enabledByDefault else { return nil }
        return current().waitReason
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    // One waiter at a time (a previous one is released first); cancellation of the worker also releases it.
    func wait() async {
        wake()
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiter = continuation
                fallbackTask = Task { [weak self, fallback] in
                    try? await Task.sleep(for: fallback)
                    if !Task.isCancelled { self?.wake() }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.wake() }
        }
    }

    func wake() {
        fallbackTask?.cancel()
        fallbackTask = nil
        waiter?.resume()
        waiter = nil
    }
}
