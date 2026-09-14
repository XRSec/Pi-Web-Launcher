import AppKit
import SwiftUI

/// 基于 AppKit 原生 NSTextView 的高性能控制台日志视图
///
/// 相比 SwiftUI 的 Text(string)，NSTextView 具备以下核心性能优势：
/// 1. 增量排版（Incremental Layout）：新日志仅追加至 textStorage，不会触发全量重排；
/// 2. 毫秒级内存流转：结合 LogStore 节流和容量裁剪，UI 界面永不卡死；
/// 3. 支持原生操作：划词选中、⌘A、⌘C、自动滚动/手动查看；
/// 4. 专为开发者设计的深色终端风格。
struct ConsoleTextView: NSViewRepresentable {
    @Binding var autoScroll: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(deviceRed: 0.10, green: 0.11, blue: 0.13, alpha: 1.0)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let contentSize = scrollView.contentSize
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(
            containerSize: NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        )
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = NSTextView(frame: NSRect(origin: .zero, size: contentSize), textContainer: textContainer)
        textView.minSize = NSSize(width: 0.0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 12, height: 10)

        // 终端配色与字体
        textView.backgroundColor = NSColor(deviceRed: 0.10, green: 0.11, blue: 0.13, alpha: 1.0)
        textView.drawsBackground = true
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
        textView.textColor = NSColor(deviceRed: 0.88, green: 0.90, blue: 0.92, alpha: 1.0)

        scrollView.documentView = textView
        context.coordinator.setup(textView: textView, scrollView: scrollView)

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject {
        var parent: ConsoleTextView
        private weak var textView: NSTextView?
        private weak var scrollView: NSScrollView?
        private var listenerToken: LogStore.ListenerToken?

        private let textAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular),
            .foregroundColor: NSColor(deviceRed: 0.88, green: 0.90, blue: 0.92, alpha: 1.0),
        ]

        init(_ parent: ConsoleTextView) {
            self.parent = parent
        }

        func setup(textView: NSTextView, scrollView: NSScrollView) {
            self.textView = textView
            self.scrollView = scrollView

            self.listenerToken = LogStore.shared.addListener(
                incremental: { [weak self] chunk in
                    self?.appendChunk(chunk)
                },
                reset: { [weak self] fullText in
                    self?.resetText(fullText)
                }
            )
        }

        private func appendChunk(_ chunk: String) {
            guard let textView = textView, let storage = textView.textStorage else { return }
            let attr = NSAttributedString(string: chunk, attributes: textAttributes)
            storage.append(attr)

            if parent.autoScroll {
                scrollToBottom()
            }
        }

        private func resetText(_ fullText: String) {
            guard let textView = textView else { return }
            if fullText.isEmpty {
                textView.string = ""
            } else {
                let attr = NSAttributedString(string: fullText, attributes: textAttributes)
                textView.textStorage?.setAttributedString(attr)
            }
            if parent.autoScroll {
                scrollToBottom()
            }
        }

        private func scrollToBottom() {
            guard let textView = textView else { return }
            textView.scrollToEndOfDocument(nil)
        }

        deinit {
            LogStore.shared.removeListener(listenerToken)
        }
    }
}
