import CoreServices
import Foundation

/// Calls `onChange` (on a private queue) when anything under a folder changes, or the folder itself is
/// moved or deleted, using FSEvents. Safe to stop or release from anywhere, including from `onChange`.
public final class FolderWatcher: @unchecked Sendable {
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "DraftKit.FolderWatcher")
    private let queueKey = DispatchSpecificKey<Void>()
    private var stream: FSEventStreamRef?

    public init(_ url: URL, latency: TimeInterval = 0.3, onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        queue.setSpecific(key: queueKey, value: ())
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            // Retained for the call, so a callback that drops the last reference tears down only after it returns.
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            withExtendedLifetime(watcher) { watcher.onChange() }
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot)
        guard let stream = FSEventStreamCreate(nil, callback, &context, [url.resolvingSymlinksInPath().path] as CFArray,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags) else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        guard !isOnCallbackQueue else { return }   // the in-flight callback is this very call, and it holds `self`
        queue.sync {}   // let a callback already in flight finish before `self` can go away
    }

    private var isOnCallbackQueue: Bool {
        DispatchQueue.getSpecific(key: queueKey) != nil
    }

    deinit { stop() }
}
