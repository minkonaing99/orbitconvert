import Foundation

// Background work (watched folders, rules, clipboard) runs at low task priority. Helper processes do not inherit
// it, so they are launched with this QoS: background keeps them on the efficiency cores on Apple Silicon.
// Uses the base priority: awaiting a job from the main actor escalates its current priority. Without a task it
// falls back to the thread's priority (the main thread counts as interactive).
nonisolated enum HelperPriority {
    static var isBackground: Bool {
        let base = withUnsafeCurrentTask { $0?.basePriority } ?? Task.currentPriority
        return base <= .utility
    }

    static var helperQoS: QualityOfService { isBackground ? .background : .userInitiated }

    /// Background helpers run about 4x slower (measured: 5K screenshot, Oxipng level 4, 13 s vs 54 s), so their
    /// deadlines stretch by 4x; otherwise watched-folder jobs would time out depending on machine load.
    static func scaled(_ timeout: Duration) -> Duration { isBackground ? timeout * 4 : timeout }
}
