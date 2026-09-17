import AppKit

/// 菜单里用量区块的自定义视图：每个周期一行「标题 + 剩余百分比 + 进度条 + 重置时间」。
///
/// 只负责用量本身：最后更新时间放在「刷新」那一行的标题里，出错原因才在这里补一行。
/// 因此正常状态下这个视图不含页脚，高度会比出错时矮一行。
final class UsageMenuView: NSView {
    enum Metrics {
        static let width: CGFloat = 300
        static let horizontalPadding: CGFloat = 14
        static let topPadding: CGFloat = 8
        static let rowHeight: CGFloat = 46
        static let barHeight: CGFloat = 7
        static let dividerGap: CGFloat = 8
        static let errorHeight: CGFloat = 16
        static let bottomPadding: CGFloat = 8

        static var contentWidth: CGFloat { width - horizontalPadding * 2 }
        static var maxRows: Int { 2 }

        /// 只有出错时才多出「分隔线 + 一行原因」的高度，正常状态不留空白。
        static func height(hasError: Bool) -> CGFloat {
            topPadding + rowHeight * CGFloat(maxRows) + bottomPadding
                + (hasError ? dividerGap + errorHeight : 0)
        }
    }

    private static let titleFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
    private static let captionFont = NSFont.systemFont(ofSize: 11)

    private var windows: [UsageWindow] = []
    private var errorText: String?

    /// 视图内自上而下排布，用翻转坐标系省掉一堆高度换算。
    override var isFlipped: Bool { true }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Metrics.width, height: Metrics.height(hasError: false)))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) 未使用") }

    func update(windows: [UsageWindow], error: String?) {
        self.windows = windows
        self.errorText = error
        // 高度随「是否有错误」变化；只有真的变了才动 frame，
        // 否则每次 60 秒刷新都会白白让 AppKit 重排一次、可能让正开着的菜单抖一下。
        let target = NSSize(width: Metrics.width, height: Metrics.height(hasError: error != nil))
        if frame.size != target { setFrameSize(target) }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let shown = Array(windows.prefix(Metrics.maxRows))
        var y = Metrics.topPadding

        if shown.isEmpty {
            // 还没拿到数据：两条淡色空槽占位，避免被误读成「满额」。
            for _ in 0..<Metrics.maxRows {
                drawPlaceholderRow(y: y)
                y += Metrics.rowHeight
            }
        } else {
            for window in shown {
                drawRow(window, y: y)
                y += Metrics.rowHeight
            }
        }

        guard let errorText else { return }
        let pad = Metrics.horizontalPadding
        y = Metrics.topPadding + Metrics.rowHeight * CGFloat(Metrics.maxRows)
        y += Metrics.dividerGap / 2
        NSColor.separatorColor.setFill()
        NSRect(x: pad, y: y, width: Metrics.contentWidth, height: 1).fill()
        y += Metrics.dividerGap / 2
        draw(errorText,
             in: NSRect(x: pad, y: y, width: Metrics.contentWidth, height: Metrics.errorHeight),
             font: Self.captionFont, color: .secondaryLabelColor)
    }

    private func drawPlaceholderRow(y: CGFloat) {
        let pad = Metrics.horizontalPadding
        let barY = y + 20
        NSColor.quaternaryLabelColor.withAlphaComponent(0.5).setFill()
        NSBezierPath(roundedRect: NSRect(x: pad, y: barY, width: Metrics.contentWidth, height: Metrics.barHeight),
                     xRadius: Metrics.barHeight / 2,
                     yRadius: Metrics.barHeight / 2).fill()
    }

    private func drawRow(_ window: UsageWindow, y: CGFloat) {
        let pad = Metrics.horizontalPadding
        let contentWidth = Metrics.contentWidth
        let titleWidth = (contentWidth * 0.55).rounded()
        let tint = Self.color(for: window.level)

        draw(window.title,
             in: NSRect(x: pad, y: y, width: titleWidth, height: 18),
             font: Self.titleFont, color: .labelColor)
        // 百分比用普通文字色：等级色（尤其绿色）在浅色菜单上偏淡，看不清。
        draw("\(window.remainingText) 剩余",
             in: NSRect(x: pad + titleWidth, y: y, width: contentWidth - titleWidth, height: 18),
             font: Self.valueFont, color: .labelColor, alignment: .right)

        let barY = y + 20
        let radius = Metrics.barHeight / 2
        NSColor.quaternaryLabelColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: pad, y: barY, width: contentWidth, height: Metrics.barHeight),
                     xRadius: radius, yRadius: radius).fill()

        let fraction = CGFloat(max(0, min(1, window.remainingPercent / 100)))
        if fraction > 0 {
            tint.setFill()
            NSBezierPath(roundedRect: NSRect(x: pad, y: barY, width: contentWidth * fraction, height: Metrics.barHeight),
                         xRadius: radius, yRadius: radius).fill()
        }

        if let reset = window.resetsAt {
            let text = "重置：" + reset.formatted(date: window.title == "7 天" ? .abbreviated : .omitted,
                                                time: .shortened)
            draw(text,
                 in: NSRect(x: pad, y: y + 30, width: contentWidth, height: 15),
                 font: Self.captionFont, color: .secondaryLabelColor)
        }
    }

    private func draw(_ text: String,
                      in rect: NSRect,
                      font: NSFont,
                      color: NSColor,
                      alignment: NSTextAlignment = .left) {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(in: rect, withAttributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: style
        ])
    }

    private static func color(for level: UsageLevel) -> NSColor {
        switch level {
        case .healthy: return .systemGreen
        case .warning: return .systemOrange
        case .critical: return .systemRed
        }
    }
}
