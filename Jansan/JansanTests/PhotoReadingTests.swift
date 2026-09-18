import Testing
import UIKit
import JansanCore
@testable import Jansan

/// 写真から記録を作る一本道（文字を読む → 行と列に組み直す → 取り込む）を、
/// **実際に画像を描いて**通す。組み直しの規則だけを試しても、読み取りと噛み合うかは分からない
@MainActor
struct PhotoReadingTests {

    /// 名前の行と点数の行が並んだ、素っ気ないスコア表を描く
    private func sheetImage() -> UIImage {
        let size = CGSize(width: 900, height: 500)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let font = UIFont.monospacedDigitSystemFont(ofSize: 44, weight: .semibold)
            let style: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.black]
            let rows = [["A", "B", "C", "D"],
                        ["30", "10", "-10", "-30"],
                        ["-20", "40", "0", "-20"]]
            for (r, row) in rows.enumerated() {
                for (c, cell) in row.enumerated() {
                    let point = CGPoint(x: 80 + CGFloat(c) * 200, y: 80 + CGFloat(r) * 130)
                    (cell as NSString).draw(at: point, withAttributes: style)
                }
            }
        }
    }

    @Test("描いたスコア表を読み取ると、そのまま取り込める形になる")
    func readsDrawnSheet() async throws {
        let boxes = await TextInPhoto.read(sheetImage())
        #expect(!boxes.isEmpty, "文字をひとつも読めていない")

        let csv = SheetReader.csv(from: boxes)
        let lines = csv.split(separator: "\n")
        #expect(lines.count == 3, "行に分けられていない: \(csv)")
        #expect(lines.first?.split(separator: ",").count == 4, "列に分けられていない: \(csv)")

        let games = try CSVImport.parse(csv)
        #expect(games.count == 1)
        #expect(games[0].session.players == ["A", "B", "C", "D"])
        #expect(games[0].session.playedRoundCount == 2)
        // 合計は0。読み違えると崩れる
        #expect(games[0].session.playerStats().map(\.total).reduce(0, +) == 0, "合計が0にならない: \(csv)")
    }

    @Test("文字の無い写真は、読み取れないと分かる")
    func blankImage() async {
        let blank = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 300)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 300, height: 300))
        }
        let boxes = await TextInPhoto.read(blank)
        #expect(SheetReader.csv(from: boxes).isEmpty)
    }
}
