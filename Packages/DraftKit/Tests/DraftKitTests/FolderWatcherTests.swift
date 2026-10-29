import Foundation
import Testing
@testable import DraftKit

@Suite struct FolderWatcherTests {
    /// Holds the only strong reference to a watcher, so its callback can drop it.
    final class Owner: @unchecked Sendable {
        var watcher: FolderWatcher?
    }

    /// Captured only by the watcher's callback: it goes away once the watcher's teardown has finished.
    final class Sentinel: Sendable {
        let onDeinit: @Sendable () -> Void
        init(onDeinit: @escaping @Sendable () -> Void) { self.onDeinit = onDeinit }
        deinit { onDeinit() }
    }

    @Test func releasingTheWatcherFromItsCallbackDoesNotDeadlock() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "watcher-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let tornDown = AsyncStream<Void>.makeStream()
        let owner = Owner()
        owner.watcher = FolderWatcher(root, latency: 0.1) { [sentinel = Sentinel { tornDown.continuation.yield() }] in
            _ = sentinel
            owner.watcher = nil   // the last reference goes away on the callback queue
        }
        try await Task.sleep(for: .milliseconds(300))
        try "hello".write(to: root.appending(path: "new.md"), atomically: true, encoding: .utf8)
        let completed = await withTaskGroup(of: Bool.self) { group in
            group.addTask { for await _ in tornDown.stream { return true }; return false }
            group.addTask { try? await Task.sleep(for: .seconds(5)); return false }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        #expect(completed)
    }
}
