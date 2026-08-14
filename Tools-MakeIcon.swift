import AppKit
import CoreGraphics
import Foundation

// 雀算のアプリアイコンを描く使い捨てスクリプト。
// 麻雀牌を模した白い角丸の上に「雀」を置き、下に点棒に見立てた線を入れる。

let size = 1024.0

guard let context = CGContext(
    data: nil,
    width: Int(size),
    height: Int(size),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("context") }

func color(_ hex: UInt32) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

// 背景: アプリの緑を上から下へ少し暗くする
let gradient = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    colors: [color(0x3A8F69), color(0x1F5C43)] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: size),
    end: CGPoint(x: 0, y: 0),
    options: []
)

// 牌のシルエット
let tileWidth = size * 0.56
let tileHeight = size * 0.70
let tileRect = CGRect(
    x: (size - tileWidth) / 2,
    y: (size - tileHeight) / 2 + size * 0.015,
    width: tileWidth,
    height: tileHeight
)
let tilePath = CGPath(
    roundedRect: tileRect,
    cornerWidth: size * 0.075,
    cornerHeight: size * 0.075,
    transform: nil
)

// 牌の影
context.saveGState()
context.setShadow(
    offset: CGSize(width: 0, height: -size * 0.018),
    blur: size * 0.05,
    color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35)
)
context.addPath(tilePath)
context.setFillColor(color(0xFBFAF6))
context.fillPath()
context.restoreGState()

// 牌の縁
context.addPath(tilePath)
context.setStrokeColor(color(0xDCD9CE))
context.setLineWidth(size * 0.008)
context.strokePath()

// 「雀」の字
let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = nsContext

let glyph = "雀" as NSString
let font = NSFont(name: "HiraginoSans-W7", size: size * 0.40)
    ?? NSFont.systemFont(ofSize: size * 0.40, weight: .bold)
let attributes: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor(cgColor: color(0x1F5C43))!,
]
let glyphSize = glyph.size(withAttributes: attributes)
glyph.draw(
    at: NSPoint(
        x: (size - glyphSize.width) / 2,
        y: tileRect.midY - glyphSize.height / 2 + size * 0.035
    ),
    withAttributes: attributes
)

NSGraphicsContext.restoreGraphicsState()

// 点棒に見立てた3本線。左から緑・赤・緑で、得点の増減を示す
let barWidth = tileWidth * 0.46
let barHeight = size * 0.020
let barSpacing = size * 0.034
let barTop = tileRect.minY + size * 0.135
let barColors = [color(0x2F7D5C), color(0xC93B3B), color(0x2F7D5C)]

for (index, barColor) in barColors.enumerated() {
    let width = barWidth * (index == 1 ? 0.62 : 1.0)
    let rect = CGRect(
        x: tileRect.midX - width / 2,
        y: barTop - CGFloat(index) * barSpacing,
        width: width,
        height: barHeight
    )
    context.addPath(CGPath(roundedRect: rect, cornerWidth: barHeight / 2, cornerHeight: barHeight / 2, transform: nil))
    context.setFillColor(barColor)
    context.fillPath()
}

guard let image = context.makeImage() else { fatalError("image") }
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = CGImageDestinationCreateWithURL(output as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
CGImageDestinationFinalize(destination)
print("wrote \(output.path)")
