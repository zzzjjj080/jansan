import AppKit
import CoreGraphics
import Foundation

// 雀（鳥）のアプリアイコン。
// 麻雀の一索は伝統的に鳥の意匠なので、モチーフとして筋が通る。
// ホーム画面では60px程度まで縮むため、細部より輪郭で見せる。

let size = 1024.0

guard let context = CGContext(
    data: nil, width: Int(size), height: Int(size),
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("context") }

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let cream = color(0xFBFAF6)
let deepGreen = color(0x17402F)
let wingTint = color(0xD3E2D6)
let beakGold = color(0xE9B457)

// 背景
let gradient = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    colors: [color(0x43A078), color(0x1B5340)] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: size),
    end: CGPoint(x: size, y: 0),
    options: []
)

// アイコンは角丸でマスクされるので、端に余白を残す
context.translateBy(x: size / 2, y: size / 2)
context.scaleBy(x: 0.86, y: 0.86)
context.translateBy(x: -size / 2, y: -size / 2)

func addEllipse(center: CGPoint, rx: CGFloat, ry: CGFloat, degrees: CGFloat, to path: CGMutablePath) {
    let transform = CGAffineTransform(translationX: center.x, y: center.y)
        .rotated(by: degrees * .pi / 180)
    path.addEllipse(in: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2), transform: transform)
}

// 止まり木。点棒に見立てた一本線で、麻雀の文脈を添える
let perchWidth = 470.0
let perch = CGPath(
    roundedRect: CGRect(x: (size - perchWidth) / 2, y: 214, width: perchWidth, height: 30),
    cornerWidth: 15, cornerHeight: 15, transform: nil
)

// 脚
let legs = CGMutablePath()
for x in [CGFloat(452), 566] {
    legs.addRect(CGRect(x: x, y: 232, width: 26, height: 150))
}

// 胴・頭・尾はひとつのパスにまとめ、影を一度で落とす
let bird = CGMutablePath()
addEllipse(center: CGPoint(x: 498, y: 548), rx: 246, ry: 202, degrees: 10, to: bird)
addEllipse(center: CGPoint(x: 688, y: 688), rx: 152, ry: 146, degrees: 0, to: bird)

// 尾。左上へ跳ね上げ、先を二又にする
bird.move(to: CGPoint(x: 320, y: 646))
bird.addLine(to: CGPoint(x: 78, y: 762))
bird.addLine(to: CGPoint(x: 158, y: 648))
bird.addLine(to: CGPoint(x: 58, y: 586))
bird.addLine(to: CGPoint(x: 316, y: 470))
bird.closeSubpath()

context.saveGState()
context.setShadow(
    offset: CGSize(width: 0, height: -16),
    blur: 38,
    color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.30)
)
context.addPath(legs)
context.addPath(bird)
context.setFillColor(cream)
context.fillPath()
context.restoreGState()

context.addPath(perch)
context.setFillColor(beakGold)
context.fillPath()

// くちばし
let beak = CGMutablePath()
beak.move(to: CGPoint(x: 812, y: 726))
beak.addLine(to: CGPoint(x: 964, y: 676))
beak.addLine(to: CGPoint(x: 810, y: 628))
beak.closeSubpath()
context.addPath(beak)
context.setFillColor(beakGold)
context.fillPath()

// 翼。輪郭が潰れないよう、胴より一段濃くしただけの単純な形にする
let wing = CGMutablePath()
addEllipse(center: CGPoint(x: 468, y: 512), rx: 172, ry: 104, degrees: 16, to: wing)
context.addPath(wing)
context.setFillColor(wingTint)
context.fillPath()

// 目
context.addEllipse(in: CGRect(x: 712, y: 706, width: 48, height: 48))
context.setFillColor(deepGreen)
context.fillPath()

guard let image = context.makeImage() else { fatalError("image") }
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = CGImageDestinationCreateWithURL(output as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
CGImageDestinationFinalize(destination)
print("wrote \(output.path)")
