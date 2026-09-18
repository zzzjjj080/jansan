import Foundation
import Vision
import UIKit
import JansanCore

/// 写真の中の文字を、端末の中だけで読む。**通信も費用もかからない。**
///
/// 読んだ結果は位置つきの文字（`SheetTextBox`）にして Core へ渡し、
/// 行と列への組み直しは `SheetReader` に任せる。ここは Vision を呼ぶだけ
enum TextInPhoto {

    /// 写真から文字を読む。読めなければ空
    static func read(_ image: UIImage) async -> [SheetTextBox] {
        guard let cgImage = image.cgImage else { return [] }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let found = (request.results as? [VNRecognizedTextObservation]) ?? []
                continuation.resume(returning: found.compactMap { observation in
                    guard let best = observation.topCandidates(1).first else { return nil }
                    // Vision の枠は**左下が原点**。上からの割合に直す
                    let box = observation.boundingBox
                    return SheetTextBox(text: best.string,
                                        x: Double(box.minX), y: Double(1 - box.maxY),
                                        width: Double(box.width), height: Double(box.height))
                })
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ja-JP", "en-US"]
            // 点数の並びを「言葉」として直されると数字が変わる。直しは切る
            request.usesLanguageCorrection = false

            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }
}

private extension CGImagePropertyOrientation {
    /// 写真は横向きで保存されていることがある。向きを合わせないと行が縦に並ぶ
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
