import Foundation

/// 写真から読み取った文字の1かたまり。位置は**画像の左上が (0, 0)、右下が (1, 1)** の割合で持つ。
///
/// 画面の仕組み（Vision）に依存させないため、位置と文字だけの形にしてある。
/// こうしておくと、読み取りの部分を差し替えても、表に組み直す規則はそのまま使える
public struct SheetTextBox: Equatable, Sendable {
    public let text: String
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(text: String, x: Double, y: Double, width: Double, height: Double) {
        self.text = text
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var centerY: Double { y + height / 2 }
    public var centerX: Double { x + width / 2 }
}

/// 紙のスコア表やスクリーンショットから読んだ文字を、**行と列に組み直して CSV にする。**
///
/// 組み直した CSV は `CSVImport.parse` に渡す。取り込みの規則（合計行・お休み・全角の数字・▲）は
/// すでにそちらにあるので、ここは「どの文字が同じ行か」「左から何番目か」だけを決める
public enum SheetReader {

    /// 同じ行と見なす縦のずれ。文字の高さに対する割合
    static let rowTolerance = 0.6

    /// 読み取った文字を CSV の形にする
    public static func csv(from boxes: [SheetTextBox]) -> String {
        rows(from: boxes)
            .map { row in row.map { clean($0.text) }.joined(separator: ",") }
            .joined(separator: "\n")
    }

    /// 縦の位置が近いものを同じ行にまとめ、行の中では左から並べる。
    /// **1行の高さを基準にする。** 固定の値にすると、写真の寄り具合で行が混ざる
    static func rows(from boxes: [SheetTextBox]) -> [[SheetTextBox]] {
        let sorted = boxes.filter { !clean($0.text).isEmpty }.sorted { $0.centerY < $1.centerY }
        guard !sorted.isEmpty else { return [] }

        let tolerance = medianHeight(sorted) * rowTolerance
        var rows: [[SheetTextBox]] = []
        var current: [SheetTextBox] = [sorted[0]]
        for box in sorted.dropFirst() {
            let center = current.map(\.centerY).reduce(0, +) / Double(current.count)
            if abs(box.centerY - center) <= tolerance {
                current.append(box)
            } else {
                rows.append(current)
                current = [box]
            }
        }
        rows.append(current)
        return rows.map { $0.sorted { $0.centerX < $1.centerX } }
    }

    static func medianHeight(_ boxes: [SheetTextBox]) -> Double {
        let heights = boxes.map(\.height).sorted()
        guard !heights.isEmpty else { return 0 }
        return heights[heights.count / 2]
    }

    /// 読み取りに混ざる余計な字を落とす。**カンマは列の区切りとぶつかる**ので置き換える
    static func clean(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "，", with: "")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
