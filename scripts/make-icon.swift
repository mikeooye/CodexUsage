#!/usr/bin/env swift
import AppKit

// 生成 App 图标。
//
//   swift scripts/make-icon.swift iconset <graphite|indigo|jade> <输出目录>
//   swift scripts/make-icon.swift preview <graphite|indigo|jade> <边长> <输出 png>
//
// 设计：圆角方形底 + 两条胶囊进度条，和菜单栏图标同一套视觉语言。
// 每个尺寸都按矢量重新绘制（不是缩放位图），小尺寸会加粗进度条、去掉投影以免糊成一团。

enum Variant: String, CaseIterable {
    case graphite
    case indigo
    case jade

    var displayName: String {
        switch self {
        case .graphite: return "石墨黑"
        case .indigo: return "靛蓝"
        case .jade: return "翠绿"
        }
    }

    var top: NSColor {
        switch self {
        case .graphite: return NSColor(srgbRed: 0.34, green: 0.35, blue: 0.39, alpha: 1)
        case .indigo: return NSColor(srgbRed: 0.49, green: 0.55, blue: 0.97, alpha: 1)
        case .jade: return NSColor(srgbRed: 0.31, green: 0.82, blue: 0.54, alpha: 1)
        }
    }

    var bottom: NSColor {
        switch self {
        case .graphite: return NSColor(srgbRed: 0.10, green: 0.11, blue: 0.13, alpha: 1)
        case .indigo: return NSColor(srgbRed: 0.25, green: 0.31, blue: 0.85, alpha: 1)
        case .jade: return NSColor(srgbRed: 0.12, green: 0.56, blue: 0.40, alpha: 1)
        }
    }
}

/// macOS Big Sur 之后的图标网格：1024 画布里主体 824×824、圆角约为边长的 22.37%。
let bodyRatio: CGFloat = 824.0 / 1024.0
let cornerRatio: CGFloat = 0.2237

func drawBar(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, fraction: CGFloat) {
    let radius = height / 2
    NSColor.white.withAlphaComponent(0.30).setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: width, height: height),
                 xRadius: radius, yRadius: radius).fill()

    NSColor.white.setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: width * fraction, height: height),
                 xRadius: radius, yRadius: radius).fill()
}

func draw(in size: CGFloat, variant: Variant) {
    let inset = size * (1 - bodyRatio) / 2
    let body = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = body.width * cornerRatio
    let path = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)
    // 16/32pt 这类极小尺寸：投影只会让边缘发灰，进度条也要更粗才看得清。
    let tiny = size < 64

    NSGraphicsContext.saveGraphicsState()
    if !tiny {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
        shadow.shadowBlurRadius = size * 0.022
        shadow.shadowOffset = NSSize(width: 0, height: -size * 0.010)
        shadow.set()
    }
    NSGradient(starting: variant.top, ending: variant.bottom)?.draw(in: path, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // 顶部一层极淡高光，让纯色块有点体积感。
    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    let gloss = NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2)
    NSGradient(starting: NSColor.white.withAlphaComponent(tiny ? 0.10 : 0.16),
               ending: NSColor.white.withAlphaComponent(0))?.draw(in: gloss, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // 两条进度：上条 72%、下条 38%，和菜单栏一样是「上 5 小时、下 7 天」。
    let barWidth = body.width * 0.56
    let barHeight = body.width * (tiny ? 0.155 : 0.115)
    let gap = body.width * (tiny ? 0.095 : 0.072)
    var y = body.midY + (barHeight * 2 + gap) / 2 - barHeight
    for fraction in [CGFloat(0.72), CGFloat(0.38)] {
        drawBar(x: body.midX - barWidth / 2, y: y, width: barWidth, height: barHeight, fraction: fraction)
        y -= barHeight + gap
    }
}

func render(px: Int, variant: Variant) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                               pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false,
                               colorSpaceName: .calibratedRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(in: CGFloat(px), variant: variant)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(px: Int, variant: Variant, to path: String) throws {
    try pngData(px: px, variant: variant).write(to: URL(fileURLWithPath: path))
}

func pngData(px: Int, variant: Variant) throws -> Data {
    let rep = render(px: px, variant: variant)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "make-icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG 编码失败"])
    }
    return data
}

/// 自己写 ICNS 容器，不依赖 `iconutil`（它在受限环境里会拒绝生成）。
/// 结构：`icns` + 总长度（大端 UInt32），随后每个元素是 类型码(4) + 该元素长度(4) + PNG 数据。
func writeICNS(variant: Variant, to path: String) throws {
    let entries: [(type: String, px: Int)] = [
        ("icp4", 16), ("ic11", 32), ("icp5", 32), ("ic12", 64),
        ("ic07", 128), ("ic13", 256), ("ic08", 256), ("ic14", 512),
        ("ic09", 512), ("ic10", 1024)
    ]

    var body = Data()
    for entry in entries {
        let png = try pngData(px: entry.px, variant: variant)
        var chunk = Data(entry.type.utf8)
        var chunkLength = UInt32(8 + png.count).bigEndian
        withUnsafeBytes(of: &chunkLength) { chunk.append(contentsOf: $0) }
        chunk.append(png)
        body.append(chunk)
    }

    var file = Data("icns".utf8)
    var total = UInt32(8 + body.count).bigEndian
    withUnsafeBytes(of: &total) { file.append(contentsOf: $0) }
    file.append(body)
    try file.write(to: URL(fileURLWithPath: path))
}

func usage() -> Never {
    FileHandle.standardError.write(Data("""
    用法：
      swift scripts/make-icon.swift icns <\(Variant.allCases.map(\.rawValue).joined(separator: "|"))> <输出 .icns>
      swift scripts/make-icon.swift iconset <变体> <输出目录>
      swift scripts/make-icon.swift preview <变体> <边长> <输出 png>

    """.utf8))
    exit(2)
}

let args = CommandLine.arguments
guard args.count >= 3, let variant = Variant(rawValue: args[2]) else { usage() }

switch args[1] {
case "icns":
    guard args.count == 4 else { usage() }
    try writeICNS(variant: variant, to: args[3])
    print("已生成 \(args[3])（\(variant.displayName)）")

case "preview":
    guard args.count == 5, let size = Int(args[3]) else { usage() }
    try writePNG(px: size, variant: variant, to: args[4])
    print("已生成预览（\(variant.displayName)）：\(args[4])")

case "iconset":
    guard args.count == 4 else { usage() }
    let dir = args[3]
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let entries: [(String, Int)] = [
        ("icon_16x16", 16), ("icon_16x16@2x", 32),
        ("icon_32x32", 32), ("icon_32x32@2x", 64),
        ("icon_128x128", 128), ("icon_128x128@2x", 256),
        ("icon_256x256", 256), ("icon_256x256@2x", 512),
        ("icon_512x512", 512), ("icon_512x512@2x", 1024)
    ]
    for (name, px) in entries {
        try writePNG(px: px, variant: variant, to: "\(dir)/\(name).png")
    }
    print("已生成 \(entries.count) 个尺寸（\(variant.displayName)）到 \(dir)")

default:
    usage()
}
