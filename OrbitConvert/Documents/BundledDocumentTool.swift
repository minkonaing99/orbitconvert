import Darwin
import Foundation

nonisolated enum DocumentConversionError: Error, LocalizedError {
    case invalidMarkdown, unavailableTool, toolFailed, timedOut, invalidOutput, protectedPDF

    var errorDescription: String? {
        switch self {
        case .invalidMarkdown: "Choose a UTF-8 Markdown file under 10 MB without binary content."
        case .unavailableTool: "The document helper is unavailable on this Mac."
        case .toolFailed: "The document helper could not process this file. The original was kept."
        case .timedOut: "Document processing took too long. Try a smaller file."
        case .invalidOutput: "The generated document failed validation. The original was kept."
        case .protectedPDF: "This PDF contains protected or interactive features. Stronger compression is unavailable."
        }
    }
}

struct BundledDocumentTool: Sendable {
    nonisolated init() {}

    nonisolated func run(_ name: String, arguments: [String], in directory: URL,
                         timeout: Duration = .seconds(60)) throws {
        let executable = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/" + name)
        guard ["pandoc", "gs"].contains(name), FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw DocumentConversionError.unavailableTool
        }
        try Task.checkCancellation()
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = ["PATH": "/usr/bin:/bin", "LC_ALL": "en_US.UTF-8",
                               "HOME": directory.path, "TMPDIR": directory.path,
                               "XDG_DATA_HOME": directory.path, "XDG_CONFIG_HOME": directory.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
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
                throw DocumentConversionError.timedOut
            }
        }
        try Task.checkCancellation()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw DocumentConversionError.toolFailed
        }
    }

    nonisolated static func workspace() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OrbitConvert-Document-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        return directory
    }
}
