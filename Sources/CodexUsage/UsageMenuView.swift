import AppKit

/// 菜单里用量区块的自定义视图：每个周期一行「标题 + 剩余百分比 + 进度条 + 重置时间」。
///
/// 用自定义视图是为了在原生菜单（磨砂背景、无箭头）里保留进度条。
/// 代价是这一项不参与菜单高亮 —— 它本来就是只读信息，这样反而更像原生的信息区。
final class UsageMenuView: NSView {
    enum Metrics {
        static let width: CGFloat = 300
        static let horizontalPadding: CGFloat = 14
        static let topPadding: CGFloat = 8
        static let rowHeight: CGFloat = 46
        static let barHeight: CGFloat = 7
        static let dividerGap: CGFloat = 8
        static let footerHeight: CGFloat = 16
        static let bottomPadding: CGFloat = 8

        static var contentWidth: CGFloat { width - horizontalPadding * 2 }
        /// 高度固定：菜单展开期间数据刷新时不会引起尺寸跳动。
        static var height: CGFloat {
            topPadding + rowHeight * 2 + dividerGap + footerHeight + bottomPadding
        }
        static var maxRows: Int { 2 }
    }

    private static let titleFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
    private static let captionFont = NSFont.systemFont(ofSize: 11)

    private var windows: [UsageWindow] = []
    private var error: String?
    private var lastUpdated: Date?

    /// 视图内自上而下排布，用翻转坐标系省掉一堆高度换算。
    override var isFlipped: Bool { true }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Metrics.width, height: Metrics.height))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) 未使用") }

    func update(windows: [UsageWindow], error: String?, lastUpdated: Date?) {
        self.windows = windows
        self.error = error
        self.lastUpdated = lastUpdated
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let pad = Metrics.horizontalPadding
        var y = Metrics.topPadding
        let shown = Array(windows.prefix(Metrics.maxRows))

        if shown.isEmpty {
            draw(error ?? "正在获取用量…",
                 in: NSRect(x: pad, y: y + 10, width: Metrics.contentWidth, height: 18),
                 font: Self.titleFont, color: .secondaryLabelColor)
        } else {
            for window in shown {
                drawRow(window, y: y)
                y += Metrics.rowHeight
            }
        }
        // 没有数据时也占住同样的高度，避免菜单尺寸变化。
        y = Metrics.topPadding + Metrics.rowHeight * CGFloat(Metrics.maxRows)

        y += Metrics.dividerGap / 2
        NSColor.separatorColor.setFill()
        NSRect(x: pad, y: y, width: Metrics.contentWidth, height: 1).fill()
        y += Metrics.dividerGap / 2

        let footer = error
            ?? lastUpdated.map { "更新于 \($0.formatted(date: .omitted, time: .shortened))" }
            ?? "正在获取用量…"
        draw(footer,
             in: NSRect(x: pad, y: y, width: Metrics.contentWidth, height: Metrics.footerHeight),
             font: Self.captionFont, color: .tertiaryLabelColor)
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
