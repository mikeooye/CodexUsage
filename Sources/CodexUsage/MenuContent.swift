import SwiftUI

struct MenuContent: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Codex Usage").font(.headline)
                Spacer()
                if store.isLoading { ProgressView().controlSize(.small) }
                Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).help("刷新")
            }

            if let error = store.error, store.windows.isEmpty {
                Text(error).font(.callout).foregroundStyle(.secondary).frame(width: 300, alignment: .leading)
            } else {
                ForEach(store.windows) { window in UsageRow(window: window) }
            }

            Divider()
            HStack {
                if let date = store.lastUpdated {
                    Text("更新于 \(date.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("退出") { NSApplication.shared.terminate(nil) }.buttonStyle(.plain)
            }
        }
        .padding(16).frame(width: 330)
    }
}

private struct UsageRow: View {
    let window: UsageWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(window.title).fontWeight(.medium)
                Spacer()
                Text("\(Int(window.remainingPercent.rounded()))% 剩余").monospacedDigit()
            }
            ProgressView(value: window.remainingPercent, total: 100)
            if let reset = window.resetsAt {
                Text("重置：\(reset.formatted(date: window.title == "7 天" ? .abbreviated : .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
