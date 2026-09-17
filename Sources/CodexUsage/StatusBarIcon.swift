import AppKit

/// 菜单栏图标：两条上下排列的胶囊进度条（5 小时在上、7 天在下），不显示任何文字。
///
/// 用「同一色的两档 alpha + 模板图」实现标准菜单栏图表的两种色调：
/// 深色菜单栏下就是**白色进度 + 浅灰底槽**，浅色菜单栏下自动变成深色进度 + 浅灰底槽。
/// 这样无论系统外观如何，都不会出现「进度条看不见」的情况。
enum StatusBarIcon {
    static let height: CGFloat = 18

    private static let barWidth: CGFloat = 20
    private static let barHeight: CGFloat = 4
    private static let barGap: CGFloat = 3
    /// 最多显示两条，避免把菜单栏撑宽。
    private static let maxBars = 2

    /// 底槽比进度浅一档，两档 alpha 组成图表的前景/背景。
    private static let fillAlpha: CGFloat = 1
    private static let trackAlpha: CGFloat = 0.4

    static func image(windows: [UsageWindow], hasError: Bool) -> NSImage {
        let shown = Array(windows.prefix(maxBars))
        guard !shown.isEmpty else {
            // 取数失败显示警告三角；还没拿到数据就画两条空槽占位。
            return hasError ? warningImage() : barImage(fractions: Array(repeating: 0, count: maxBars))
        }
        return barImage(fractions: shown.map(fillFraction))
    }

    private static func fillFraction(_ window: UsageWindow) -> CGFloat {
        CGFloat(max(0, min(1, window.remainingPercent / 100)))
    }

    /// 让整组进度条在图标高度里垂直居中，返回最上面一条的底边 y（y 轴向上）。
    private static func topBarY(count: Int) -> CGFloat {
        let blockHeight = CGFloat(count) * barHeight + CGFloat(max(0, count - 1)) * barGap
        return (height + blockHeight) / 2 - barHeight
    }

    private static func barImage(fractions: [CGFloat]) -> NSImage {
        let image = NSImage(size: NSSize(width: barWidth, height: height), flipped: false) { _ in
            var top = topBarY(count: fractions.count)
            for fraction in fractions {
                drawBar(fraction: fraction, y: top)
                top -= barHeight + barGap
            }
            return true
        }
        // 模板图：系统只用它的 alpha，颜色由菜单栏明暗决定。
        image.isTemplate = true
        return image
    }

    private static func drawBar(fraction: CGFloat, y: CGFloat) {
        capsule(x: 0, y: y, width: barWidth, alpha: trackAlpha)
        // 剩余为 0 时只留底槽，正好表示「这条空了」。
        guard fraction > 0 else { return }
        capsule(x: 0, y: y, width: barWidth * fraction, alpha: fillAlpha)
    }

    private static func capsule(x: CGFloat, y: CGFloat, width: CGFloat, alpha: CGFloat) {
        let path = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: width, height: barHeight),
                                xRadius: barHeight / 2,
                                yRadius: barHeight / 2)
        // 模板图只看 alpha，用什么颜色都无所谓，按惯例用黑色。
        NSColor.black.withAlphaComponent(alpha).setFill()
        path.fill()
    }

    private static func warningImage() -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        if let symbol = NSImage(systemSymbolName: "exclamationmark.triangle.fill",
                                accessibilityDescription: "Codex 用量获取失败")?
            .withSymbolConfiguration(config) {
            symbol.isTemplate = true
            return symbol
        }
        return barImage(fractions: Array(repeating: 0, count: maxBars))
    }
}
