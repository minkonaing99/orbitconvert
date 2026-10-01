import AppKit
import SwiftUI

struct WatchMenuView: View {
    @Environment(WatchedFoldersController.self) private var watcher
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppIdentity.name).font(.headline)
            Text(watcher.watcherSummary).foregroundStyle(.secondary)
            if !watcher.unavailableIDs.isEmpty {
                Label("Some folders need attention in Settings", systemImage: "exclamationmark.triangle")
                    .font(.caption)
            }
            if watcher.outstandingJobCount > 0 {
                Text("\(watcher.activeJobs.count) active · \(watcher.queuedJobs.count) waiting")
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(watcher.activeJobs + Array(watcher.queuedJobs.prefix(10))) { job in
                            OptimizationJobRow(job: job)
                        }
                        if watcher.queuedJobs.count > 10 {
                            Text("\(watcher.queuedJobs.count - 10) more waiting").foregroundStyle(.secondary)
                        }
                    }
                }.frame(height: 190)
            }
            session
            if !watcher.activity.isEmpty {
                Divider()
                Text("Recent Activity").font(.subheadline.bold())
                ForEach(watcher.activity.prefix(5)) { event in
                    WatchResultRow(event: event)
                }
                Button("View All Activity") { openWindow(id: "activity") }
            }
            Divider()
            Button(watcher.paused ? "Resume Watching" : "Pause Watching") {
                watcher.setPaused(!watcher.paused)
            }
            Button(watcher.clipboard.enabled ? "Pause Clipboard Optimization" : "Enable Clipboard Optimization") {
                watcher.clipboard.enabled.toggle()
            }
            if !watcher.clipboard.results.isEmpty {
                Text("Clipboard Results: \(watcher.clipboard.results.count)")
                HStack {
                    Button("Copy All") { watcher.clipboard.copy(watcher.clipboard.results) }
                    Button("Save All") { watcher.clipboard.save(watcher.clipboard.results) }
                    Button("Clear") { watcher.clipboard.clearResults() }
                }
            }
            if let message = watcher.clipboard.message { Text(message).font(.caption) }
            Button("Open OrbitConvert") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            SettingsLink { Text("Settings...") }
            Button("Quit OrbitConvert") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
        .padding(16)
        }
        .frame(width: 350, height: popupHeight)
    }

    // MenuBarExtra needs a definite height; a ScrollView has no intrinsic height.
    private var popupHeight: CGFloat {
        watcher.outstandingJobCount == 0 && watcher.activity.isEmpty &&
        watcher.sessionStatistics.totalProcessed == 0 ? 340 : 560
    }

    @ViewBuilder private var session: some View {
        let stats = watcher.sessionStatistics
        if stats.totalProcessed > 0 {
            Divider()
            Text(watcher.outstandingJobCount == 0 && stats.failed == 0 && stats.skipped == 0
                 ? "All files optimized" : "This Session").font(.subheadline.bold())
            Text("\(stats.totalProcessed) processed · \(stats.successful) optimized")
            if stats.skipped > 0 || stats.failed > 0 {
                Text("\(stats.skipped) skipped · \(stats.failed) failed").foregroundStyle(.secondary)
            }
            if stats.successful > 0 {
                Text("\(size(stats.originalBytes)) to \(size(stats.optimizedBytes))")
                Text("Saved \(size(stats.bytesSaved))").fontWeight(.medium)
            }
        }
    }

    private func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

struct OptimizationJobRow: View {
    let job: OptimizationJobStatus
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(job.fileName).lineLimit(1).truncationMode(.middle)
                Text(job.phase.rawValue).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if job.phase != .waiting {
                ProgressView().controlSize(.small).accessibilityLabel(job.phase.rawValue)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct WatchResultRow: View {
    let event: WatchActivity
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(event.fileName, systemImage: symbol)
                .lineLimit(1).truncationMode(.middle)
            if event.outcome == .optimized {
                Text("\(size(event.originalBytes)) to \(size(event.outputBytes))")
                    .font(.caption).foregroundStyle(.secondary)
                if event.originalBytes > 0 {
                    let saved = max(event.originalBytes - event.outputBytes, 0)
                    Text("Saved \(size(saved)) (\(Int(Double(saved) / Double(event.originalBytes) * 100))%)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(event.message.isEmpty ? event.outcome.rawValue.capitalized : event.message)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }.accessibilityElement(children: .combine)
    }
    private var symbol: String {
        switch event.outcome {
        case .optimized: "checkmark"
        case .skipped: "minus"
        case .failed: "exclamationmark.triangle"
        }
    }
    private func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

struct WatchActivityView: View {
    @Environment(WatchedFoldersController.self) private var watcher
    var body: some View {
        List(watcher.activity) { event in
            WatchResultRow(event: event).padding(.vertical, 4)
        }.frame(minWidth: 400, minHeight: 300)
    }
}
