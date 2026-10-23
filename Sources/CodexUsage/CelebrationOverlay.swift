import AppKit
import ConfettiSwiftUI
import QuartzCore
import SwiftUI

/// 在每块屏幕上方短暂展示一次不抢焦点、可穿透点击的庆祝动画。
@MainActor
final class CelebrationOverlay {
    private let model = CelebrationModel()
    private var windows: [NSWindow] = []
    private var dismissTask: Task<Void, Never>?

    func show() {
        dismissTask?.cancel()
        hide()

        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }

        if windows.isEmpty {
            windows = NSScreen.screens.map(makeWindow(for:))
        }
        windows.forEach {
            $0.alphaValue = 1
            $0.orderFrontRegardless()
        }
        // 等宿主视图完成首次挂载后再改变 trigger，否则第一次变化会被当成初始值。
        DispatchQueue.main.async { [model] in model.trigger += 1 }

        dismissTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(CelebrationMetrics.visibleDuration))
            } catch {
                return
            }
            guard let self else { return }
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = CelebrationMetrics.fadeDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.windows.forEach { $0.animator().alphaValue = 0 }
            }
            guard !Task.isCancelled else { return }
            self.hide()
        }
    }

    private func makeWindow(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.contentView = NSHostingView(rootView: CelebrationView(model: model))
        return window
    }

    private func hide() {
        windows.forEach { $0.orderOut(nil) }
    }
}

@MainActor
private final class CelebrationModel: ObservableObject {
    @Published var trigger = 0
}

private enum CelebrationMetrics {
    static let confettiSize: CGFloat = 14
    static let radius: CGFloat = 520
    static let repetitions = 1
    static let repetitionInterval = 0.3
    static let visibleDuration = 2.5
    static let fadeDuration = 0.8

    static func rainHeight(screenHeight: CGFloat) -> CGFloat {
        // 发射点位于屏幕中心；加上爆炸半径和粒子尺寸，确保最高的粒子也越过底边。
        screenHeight / 2 + radius + confettiSize * 2
    }

}

private struct CelebrationView: View {
    @ObservedObject var model: CelebrationModel

    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .frame(width: 1, height: 1)
                .confettiCannon(
                    trigger: $model.trigger,
                    num: 180,
                    confettiSize: CelebrationMetrics.confettiSize,
                    rainHeight: CelebrationMetrics.rainHeight(
                        screenHeight: geometry.size.height
                    ),
                    fadesOut: false,
                    // 90° 为正上方，中心角 135° 即向左旋转 45°。
                    openingAngle: .degrees(75),
                    closingAngle: .degrees(195),
                    radius: CelebrationMetrics.radius,
                    repetitions: CelebrationMetrics.repetitions,
                    repetitionInterval: CelebrationMetrics.repetitionInterval,
                    hapticFeedback: false
                )
                .position(
                    x: geometry.size.width * 0.75,
                    y: geometry.size.height * 0.5
                )
        }
    }
}
