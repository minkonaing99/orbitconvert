import CoreServices
import Foundation

@MainActor
final class FolderWatchService {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.example.OrbitConvert.FolderWatch")
    private let onChange: @MainActor (URL, FSEventStreamEventFlags, FSEventStreamEventId) -> Void

    init(folder: URL, since eventID: FSEventStreamEventId = FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
         onChange: @escaping @MainActor (URL, FSEventStreamEventFlags, FSEventStreamEventId) -> Void) throws {
        self.onChange = onChange
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: { pointer in
                guard let pointer else { return nil }
                _ = Unmanaged<FolderWatchService>.fromOpaque(pointer).retain()
                return pointer
            },
            release: { pointer in
                if let pointer { Unmanaged<FolderWatchService>.fromOpaque(pointer).release() }
            },
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes |
                                           kFSEventStreamCreateFlagFileEvents |
                                           kFSEventStreamCreateFlagWatchRoot)
        let callback: FSEventStreamCallback = { _, info, count, eventPaths, eventFlags, eventIDs in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatchService>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(eventPaths, to: NSArray.self)
            for index in 0..<count {
                guard let path = paths[index] as? String else { continue }
                let flags = eventFlags[index]
                let eventID = eventIDs[index]
                let url = URL(fileURLWithPath: path)
                Task { @MainActor [weak watcher] in watcher?.onChange(url, flags, eventID) }
            }
        }
        guard let created = FSEventStreamCreate(nil, callback, &context,
                                                [folder.path] as CFArray,
                                                eventID,
                                                0.75, flags) else { throw WatchError.unavailableFile }
        stream = created
        FSEventStreamSetDispatchQueue(created, queue)
        guard FSEventStreamStart(created) else {
            FSEventStreamInvalidate(created)
            FSEventStreamRelease(created)
            stream = nil
            throw WatchError.unavailableFile
        }
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
