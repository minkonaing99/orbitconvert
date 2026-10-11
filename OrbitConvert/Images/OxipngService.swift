import Darwin
import Foundation

struct OxipngService: Sendable {
    nonisolated static var executableURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/oxipng")
    }

    nonisolated init() {}

    nonisolated func validateRewrite(of url: URL) throws {
        _ = try metadataChunks(in: url)
    }

    nonisolated func optimize(source: URL, destination: URL, preset: CompressionPreset,
                              timeout: Duration = .seconds(60)) throws {
        guard source.isFileURL, destination.isFileURL, source.standardizedFileURL != destination.standardizedFileURL,
              FileManager.default.isExecutableFile(atPath: Self.executableURL.path) else {
            throw OptimizationError.cannotEncode
        }
        try Task.checkCancellation()
        let chunks = try metadataChunks(in: source)
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        // Exclusive creation ensures the helper can never truncate an existing file.
        let descriptor = open(destination.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard descriptor >= 0 else { throw FileOutputService.writeError(for: errno) }
        let output = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var succeeded = false
        defer {
            try? output.close()
            if !succeeded { try? FileManager.default.removeItem(at: destination) }
        }
        let level = preset == .aggressive ? "4" : preset == .lossless ? "1" : "2"
        var arguments = ["--quiet", "--stdout", "--opt", level, "--threads", "2",
                         "--timeout", "30", "--max-raw-size", "256000000"]
        if !chunks.isEmpty { arguments += ["--keep", chunks.sorted().joined(separator: ",")] }
        arguments += ["--", "-"]
        let process = Process()
        process.executableURL = Self.executableURL
        process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin", "LC_ALL": "C"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while finished.wait(timeout: .now() + .milliseconds(100)) == .timedOut {
            if Task.isCancelled || ContinuousClock.now >= deadline {
                process.terminate()
                if finished.wait(timeout: .now() + .seconds(2)) == .timedOut, process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                    process.waitUntilExit()
                }
                try Task.checkCancellation()
                throw OptimizationError.cannotEncode
            }
        }
        try Task.checkCancellation()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw OptimizationError.cannotEncode
        }
        succeeded = true
    }

    nonisolated private func metadataChunks(in url: URL) throws -> Set<String> {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        let length = try input.seekToEnd()
        guard length <= 256_000_000 else { throw ConversionError.imageTooLarge }
        try input.seek(toOffset: 0)
        guard try input.read(upToCount: 8) == Data([137, 80, 78, 71, 13, 10, 26, 10]) else {
            throw OptimizationError.unsupportedInput
        }
        var offset: UInt64 = 8
        var chunks: Set<String> = []
        var chunkCount = 0
        while offset < length {
            try Task.checkCancellation()
            chunkCount += 1
            guard chunkCount <= 100_000 else { throw OptimizationError.unsupportedInput }
            guard length - offset >= 12,
                  let header = try input.read(upToCount: 8), header.count == 8 else {
                throw OptimizationError.unsupportedInput
            }
            let size = header.prefix(4).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            let nameBytes = header.suffix(4)
            guard size <= length - offset - 12,
                  nameBytes.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) }),
                  let name = String(data: nameBytes, encoding: .ascii) else {
                throw OptimizationError.unsupportedInput
            }
            // Content credentials cannot survive rewriting. iDOT is encoder cache data, not user metadata.
            if name == "caBX" { throw OptimizationError.protectedMetadata }
            if name != "iDOT", let first = nameBytes.first, first & 32 != 0 { chunks.insert(name) }
            offset += size + 12
            try input.seek(toOffset: offset)
            if name == "IEND" {
                guard size == 0, offset == length else { throw OptimizationError.unsupportedInput }
                return chunks
            }
        }
        throw OptimizationError.unsupportedInput
    }
}
