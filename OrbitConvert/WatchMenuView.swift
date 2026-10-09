import AppKit
import SwiftUI

struct WatchMenuView: View {
    @Environment(WatchedFoldersController.self) private var watcher
    @Environment(\.openWindow) private var openWindow
    @State private var contentHeight: CGFloat = 340
    @State private var jobsHeight: CGFloat = 44

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
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { jobsHeight = $0 }
                }.frame(height: min(jobsHeight, 190))
            }
            session
            if !watcher.activity.isEmpty {
                Divider()
                Text("Recent Activity").font(.subheadline.bold())
                ForEach(watcher.activity.prefix(3)) { event in
                    WatchResultRow(event: event, compact: true)
                }
            }
            Divider()
            Button("View All Activity") {
                openWindow(id: "activity")
                NSApp.activate(ignoringOtherApps: true)
            }
            Button("Open OrbitConvert") {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            SettingsLink { Text("Settings...") }
            Button("Quit OrbitConvert") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
        .padding(16)
        .frame(width: 350, alignment: .leading)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
        }
        .frame(width: 350, height: min(contentHeight, 560))
    }

    @ViewBuilder private var session: some View {
        let stats = watcher.sessionStatistics
        if stats.totalProcessed > 0 {
            Divider()
            Text(watcher.outstandingJobCount == 0 && stats.failed == 0 && stats.skipped == 0
                 ? "All files optimized" : "This Session").font(.subheadline.bold())
            HStack {
                Text("\(stats.totalProcessed) processed")
                Spacer()
                Text("Saved \(size(stats.bytesSaved))").fontWeight(.medium)
            }.font(.subheadline)
            if stats.skipped > 0 || stats.failed > 0 {
                Text("\(stats.skipped) skipped · \(stats.failed) failed").foregroundStyle(.secondary)
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
    var compact = false

    var body: some View {
        if compact {
            HStack(spacing: 8) {
                Image(systemName: symbol).frame(width: 14)
                    .accessibilityLabel(event.outcome.rawValue.capitalized)
                Text(event.fileName).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                Text(event.outcome == .optimized
                     ? "Saved \(size(event.savingsBytes))"
                     : event.outcome.rawValue.capitalized)
                    .foregroundStyle(.secondary).fixedSize()
            }
            .font(.caption)
            .help(event.message.isEmpty ? event.fileName : "\(event.fileName): \(event.message)")
            .accessibilityElement(children: .combine)
        } else {
            detailedRow
        }
    }

    private var detailedRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Label(event.fileName, systemImage: symbol)
                    .fontWeight(.medium).lineLimit(1).truncationMode(.middle)
                    .help(event.fileName)
                Spacer(minLength: 8)
                Text(event.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.caption).foregroundStyle(.secondary).fixedSize()
            }
            if event.outcome == .optimized {
                Text("Original \(size(event.originalBytes))  /  Final \(size(event.outputBytes))")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Text("Saved \(size(event.savingsBytes)) (\(event.savingsPercentage.formatted(.number.precision(.fractionLength(0...1))))%)")
                    .font(.caption).monospacedDigit()
            } else {
                Text(event.message.isEmpty ? event.outcome.rawValue.capitalized : event.message)
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Watched-folder and clipboard history").font(.headline)
            Text("Last 200 results are saved locally, including results from previous sessions.")
                .font(.caption).foregroundStyle(.secondary)
            if watcher.activity.isEmpty {
                ContentUnavailableView("No Activity Yet", systemImage: "clock",
                    description: Text("Completed optimizations will appear here with file sizes and savings."))
            } else {
                List(watcher.activity) { event in
                    WatchResultRow(event: event).padding(.vertical, 6)
                }.listStyle(.inset)
            }
        }.padding(16).frame(minWidth: 420, minHeight: 300)
    }
}
