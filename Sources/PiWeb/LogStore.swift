import AppKit
import Foundation

/// 线程安全的日志缓冲与多播分发中心
///
/// 解决高频日志输出导致主线程 UI 卡顿的根本问题：
/// 1. 线程安全的高效缓冲：后台线程（Pipe/网络等）调用 `append` 极速入队，零阻塞；
/// 2. 批量合并与主线程节流（约 50ms 批次）：避免成千上万条碎片输出疯狂触发主线程重绘；
/// 3. 内存与字数上限修剪：超出最大字符数时自动修剪早期历史，防止内存无限上涨；
/// 4. 增量渲染回调：通知 NSTextView 仅追加新增片段，彻底告别整段富文本重新排版带来的 UI 卡顿。
public final class LogStore: ObservableObject, @unchecked Sendable {
    public static let shared = LogStore()

    public static let maxBufferedCharacters = 150_000
    public static let trimTargetCharacters = 100_000

    @Published public private(set) var lineCount: Int = 0
    @Published public private(set) var logSizeFormatted: String = "0 KB"

    private let lock = NSLock()
    private var pendingChunks: [String] = []
    private var isFlushScheduled = false

    public private(set) var currentText: String = ""

    public struct ListenerToken: Hashable {
        let id = UUID()
    }

    private struct Listener {
        let id: UUID
        let incremental: (String) -> Void
        let reset: (String) -> Void
    }

    private var listeners: [Listener] = []

    private init() {}

    /// 线程安全追加文本，可在任意后台线程无锁竞争地迅速返回
    public func append(_ text: String) {
        guard !text.isEmpty else { return }

        lock.lock()
        pendingChunks.append(text)
        let shouldSchedule = !isFlushScheduled
        if shouldSchedule {
            isFlushScheduled = true
        }
        lock.unlock()

        if shouldSchedule {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50)) { [weak self] in
                self?.flushToMain()
            }
        }
    }

    public func appendLine(_ line: String) {
        append(line + "\n")
    }

    private func flushToMain() {
        lock.lock()
        let chunks = pendingChunks
        pendingChunks.removeAll(keepingCapacity: true)
        isFlushScheduled = false
        lock.unlock()

        guard !chunks.isEmpty else { return }
        let merged = chunks.joined()

        consumeMergedText(merged)
    }

    private func consumeMergedText(_ text: String) {
        var didTrim = false
        var activeListeners: [Listener] = []
        var textToReset: String = ""

        lock.lock()
        currentText.append(text)

        if currentText.count > Self.maxBufferedCharacters {
            let overflow = currentText.count - Self.trimTargetCharacters
            let targetIndex = currentText.index(currentText.startIndex, offsetBy: overflow)
            if let newlineIndex = currentText[targetIndex...].firstIndex(of: "\n") {
                let sliceStart = currentText.index(after: newlineIndex)
                currentText = "[…早前日志已自动截断清理…]\n" + String(currentText[sliceStart...])
            } else {
                currentText = "[…早前日志已自动截断清理…]\n" + String(currentText[targetIndex...])
            }
            didTrim = true
            textToReset = currentText
        }

        let currentCount = currentText.reduce(into: 1) { count, char in
            if char == "\n" { count += 1 }
        }
        let bytes = Double(currentText.utf8.count)
        let sizeString: String
        if bytes >= 1024 * 1024 {
            sizeString = String(format: "%.1f MB", bytes / (1024 * 1024))
        } else {
            sizeString = String(format: "%.1f KB", bytes / 1024)
        }

        activeListeners = listeners
        lock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.lineCount = currentCount
            self.logSizeFormatted = sizeString

            if didTrim {
                for listener in activeListeners {
                    listener.reset(textToReset)
                }
            } else {
                for listener in activeListeners {
                    listener.incremental(text)
                }
            }
        }
    }

    public func clear() {
        var activeListeners: [Listener] = []
        lock.lock()
        pendingChunks.removeAll()
        currentText = ""
        activeListeners = listeners
        lock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.lineCount = 0
            self.logSizeFormatted = "0 KB"
            for listener in activeListeners {
                listener.reset("")
            }
        }
    }

    @discardableResult
    public func addListener(
        incremental: @escaping (String) -> Void,
        reset: @escaping (String) -> Void
    ) -> ListenerToken {
        let token = ListenerToken()
        var current: String = ""

        lock.lock()
        listeners.append(Listener(id: token.id, incremental: incremental, reset: reset))
        current = currentText
        lock.unlock()

        DispatchQueue.main.async {
            reset(current)
        }
        return token
    }

    public func removeListener(_ token: ListenerToken?) {
        guard let token = token else { return }
        lock.lock()
        listeners.removeAll { $0.id == token.id }
        lock.unlock()
    }
}
