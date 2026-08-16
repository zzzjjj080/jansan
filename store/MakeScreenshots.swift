import AppKit
import CoreGraphics
import Foundation

// App Store用のスクリーンショットを組む使い捨てスクリプト。
// 生のスクリーンショットの上にキャプションを載せ、6.9インチ(1320x2868)に収める。

// 既定は6.9インチ(1320x2868)。第3・第4引数で他のサイズにも出せる
let width = CommandLine.arguments.count > 3 ? Double(CommandLine.arguments[3])! : 1320.0
let height = CommandLine.arguments.count > 4 ? Double(CommandLine.arguments[4])! : 2868.0
let uiScale = width / 1320.0

struct Shot {
    let file: String
    let title: String
    let subtitle: String
}

let shots = [
    Shot(file: "01-main.png",     title: "3人打てば、4人目は自動", subtitle: "合計が0になるよう逆算します"),
    Shot(file: "02-fit.png",      title: "6人でも1画面に収まる", subtitle: "人数と局数に合わせて自動で縮小。横スクロールなし"),
    Shot(file: "03-stats.png",    title: "着順も推移も、ひと目で", subtitle: "打つほど成績が積み上がります"),
    Shot(file: "04-settings.png", title: "抜け番があっても迷わない", subtitle: "打った人をタップするだけ。休みは自動で入ります"),
    Shot(file: "05-export.png",   title: "CSVで書き出して共有", subtitle: "メモにもスプレッドシートにも貼れます"),
]

let inputDir = URL(fileURLWithPath: CommandLine.arguments[1])
let outputDir = URL(fileURLWithPath: CommandLine.arguments[2])
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

func color(_ hex: UInt32) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

for shot in shots {
    guard let context = CGContext(
        data: nil, width: Int(width), height: Int(height),
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("context") }

    // 背景。アプリの生成り色から少しだけ緑に寄せる
    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: [color(0xF7F5F0), color(0xE2EAE3)] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: height),
        end: CGPoint(x: 0, y: 0),
        options: []
    )

    // 端末画面。角丸にして影を落とす
    let source = NSImage(contentsOf: inputDir.appendingPathComponent(shot.file))!
    var rect = CGRect(x: 0, y: 0, width: source.size.width, height: source.size.height)
    let cgSource = source.cgImage(forProposedRect: &rect, context: nil, hints: nil)!

    let shotWidth = width * 0.80
    let shotHeight = shotWidth * (height / width)
    let shotRect = CGRect(
        x: (width - shotWidth) / 2,
        y: -shotHeight * 0.06,
        width: shotWidth,
        height: shotHeight
    )
    let clip = CGPath(roundedRect: shotRect, cornerWidth: 56 * uiScale, cornerHeight: 56 * uiScale, transform: nil)

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -18),
        blur: 46,
        color: CGColor(red: 0.11, green: 0.16, blue: 0.13, alpha: 0.30)
    )
    context.addPath(clip)
    context.setFillColor(color(0xFFFFFF))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(clip)
    context.clip()
    context.draw(cgSource, in: shotRect)
    context.restoreGState()

    // キャプション
    let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsContext

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center

    let title = shot.title as NSString
    let titleAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont(name: "HiraginoSans-W7", size: 84 * uiScale) ?? NSFont.systemFont(ofSize: 84 * uiScale, weight: .bold),
        .foregroundColor: NSColor(cgColor: color(0x1F5C43))!,
        .paragraphStyle: paragraph,
    ]
    let titleBox = CGRect(x: 70 * uiScale, y: height - 400 * uiScale, width: width - 140 * uiScale, height: 200 * uiScale)
    title.draw(in: titleBox, withAttributes: titleAttributes)

    let subtitle = shot.subtitle as NSString
    let subtitleAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont(name: "HiraginoSans-W3", size: 44 * uiScale) ?? NSFont.systemFont(ofSize: 44 * uiScale),
        .foregroundColor: NSColor(cgColor: color(0x5A6B5F))!,
        .paragraphStyle: paragraph,
    ]
    let subtitleBox = CGRect(x: 80 * uiScale, y: height - 500 * uiScale, width: width - 160 * uiScale, height: 120 * uiScale)
    subtitle.draw(in: subtitleBox, withAttributes: subtitleAttributes)

    NSGraphicsContext.restoreGraphicsState()

    let output = outputDir.appendingPathComponent(shot.file)
    let destination = CGImageDestinationCreateWithURL(output as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    print("wrote \(output.lastPathComponent)")
}
