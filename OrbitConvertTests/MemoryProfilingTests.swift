import Darwin
import Foundation
import ImageIO
import PDFKit
import XCTest
@testable import OrbitConvert

final class MemoryProfilingTests: XCTestCase {
    @MainActor
    func testMemoryWorkload() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let scenario = environment["ORBIT_MEMORY_SCENARIO"] else {
            throw XCTSkip("Opt-in memory measurement; see docs/SETUP.md#memory-profiling.")
        }
        guard ["images24", "images48", "convert", "pdfs", "idle"].contains(scenario),
              let path = environment["ORBIT_MEMORY_FIXTURES"], path.hasPrefix("/") else {
            return XCTFail("Invalid profiling configuration")
        }
        let sampler = MemorySampler()
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("OrbitMemory-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        defer {
            sampler.stop()
            let attachment = XCTAttachment(data: Data(sampler.csv.utf8), uniformTypeIdentifier: "public.comma-separated-values-text")
            attachment.name = "memory-\(scenario).csv"
            attachment.lifetime = .keepAlways
            add(attachment)
            try? FileManager.default.removeItem(at: output)
        }
        sampler.start()
        mark("attach", sampler: sampler)
        try await Task.sleep(for: .seconds(20))
        mark("idle", sampler: sampler)
        try await Task.sleep(for: .seconds(20))
        if scenario != "idle" {
            let directory = URL(fileURLWithPath: path).appendingPathComponent(scenario == "convert" ? "images24" : scenario)
            let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).sorted { $0.path < $1.path }
            XCTAssertEqual(urls.count, scenario == "pdfs" ? 3 : scenario == "images48" ? 4 : 12)
            let before = try urls.map { try FileFingerprint.read($0) }
            for cycle in 1...3 {
                let destination = output.appendingPathComponent("cycle-\(cycle)")
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
                mark("batch-\(cycle)", sampler: sampler)
                let result = await Task.detached(priority: .userInitiated) {
                    await Self.run(urls, scenario: scenario, destination: destination)
                }.value
                XCTAssertEqual(result, urls.count, "Every input must complete without failure")
                mark("cooldown-\(cycle)", sampler: sampler)
                try await Task.sleep(for: .seconds(30))
            }
            XCTAssertEqual(try urls.map { try FileFingerprint.read($0) }, before, "Sources must stay unchanged")
        }
        mark("settled", sampler: sampler)
        try await Task.sleep(for: .seconds(60))
        mark("finished", sampler: sampler)
    }

    nonisolated private static func run(_ urls: [URL], scenario: String, destination: URL) async -> Int {
        let inspection = FileTypeService().inspect(urls)
        let files = await MainActor.run { inspection.files }
        guard files.count == urls.count else { return -1 }
        let outputs: [URL]
        let completed: Int
        if scenario == "convert" {
            let result = BatchConversionService().convert(files, to: .png, in: destination)
            guard await MainActor.run(body: { result.failures.isEmpty && !result.cancelled }) else { return -1 }
            outputs = await MainActor.run { result.outputURLs }
            completed = outputs.count
        } else {
            let result = BatchOptimizationService().optimize(files, in: destination, preset: .balanced)
            guard await MainActor.run(body: { result.failures.isEmpty && !result.cancelled }) else { return -1 }
            outputs = await MainActor.run { result.saved.map(\.outputURL) }
            completed = result.successCount
        }
        for url in outputs {
            if scenario == "pdfs" {
                guard let pdf = PDFDocument(url: url), !pdf.isLocked, pdf.pageCount == 20 else { return -1 }
            } else {
                guard let image = CGImageSourceCreateWithURL(url as CFURL, nil),
                      CGImageSourceGetStatusAtIndex(image, 0) == .statusComplete else { return -1 }
            }
        }
        return completed
    }

    private func mark(_ phase: String, sampler: MemorySampler) {
        sampler.setPhase(phase)
        let line = "MEMORY_PROFILE pid=\(getpid()) phase=\(phase) time=\(Date().timeIntervalSince1970)\n"
        FileHandle.standardOutput.write(Data(line.utf8))
    }
}

nonisolated private final class MemorySampler: @unchecked Sendable {
    private let lock = NSLock()
    private var phase = "startup"
    private var rows = ["unix_seconds,phase,rss_bytes,footprint_bytes"]
    private var timer: DispatchSourceTimer?

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "OrbitConvert.memory-sampler"))
        timer.schedule(deadline: .now(), repeating: .milliseconds(200))
        timer.setEventHandler { [weak self] in self?.sample() }
        self.timer = timer
        timer.resume()
    }

    func stop() { timer?.cancel(); timer = nil }
    func setPhase(_ value: String) { lock.lock(); phase = value; lock.unlock(); sample() }
    var csv: String { lock.lock(); defer { lock.unlock() }; return rows.joined(separator: "\n") }

    private func sample() {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return }
        lock.lock()
        rows.append("\(Date().timeIntervalSince1970),\(phase),\(info.resident_size),\(info.phys_footprint)")
        lock.unlock()
    }
}
