import Foundation
import NeonCore

/// 监听 ~/.claude/neon-status 目录变化。
///
/// 双通道，任何一条通了就能实时更新：
///   1. Darwin notification —— hook 写完主动广播，最快
///   2. kqueue 目录监听 —— 兜底，hook 用 rename 落盘，会触发目录 .write
final class StatusWatcher {
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var directoryFD: CInt = -1
    private var bridgeObserver: NSObjectProtocol?
    private var isObservingDarwin = false

    /// Darwin 回调是 C 函数指针，不能捕获上下文，只能转成一次 NotificationCenter 广播
    fileprivate static let darwinBridgeName = Notification.Name("NeonNotify.statusDidChange")

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    func start() {
        try? FileManager.default.createDirectory(at: StatusPaths.directory, withIntermediateDirectories: true)
        startDarwinObserver()
        startDirectoryObserver()
        onChange()
    }

    func stop() {
        source?.cancel()
        source = nil
        if directoryFD >= 0 {
            close(directoryFD)
            directoryFD = -1
        }
        if isObservingDarwin {
            CFNotificationCenterRemoveEveryObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                Unmanaged.passUnretained(self).toOpaque()
            )
            isObservingDarwin = false
        }
        if let bridgeObserver {
            NotificationCenter.default.removeObserver(bridgeObserver)
            self.bridgeObserver = nil
        }
    }

    private func startDarwinObserver() {
        bridgeObserver = NotificationCenter.default.addObserver(
            forName: Self.darwinBridgeName,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onChange()
        }

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, _, _, _, _ in
                NotificationCenter.default.post(name: StatusWatcher.darwinBridgeName, object: nil)
            },
            StatusPaths.darwinNotificationName as CFString,
            nil,
            .deliverImmediately
        )
        isObservingDarwin = true
    }

    private func startDirectoryObserver() {
        let fd = open(StatusPaths.directory.path, O_EVTONLY)
        guard fd >= 0 else { return }
        directoryFD = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.onChange()
        }
        source.resume()
        self.source = source
    }
}
