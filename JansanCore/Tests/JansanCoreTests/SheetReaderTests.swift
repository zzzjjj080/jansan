import Testing
import Foundation
@testable import JansanCore

/// 写真から読んだ文字を、行と列に組み直せるか。
/// 位置は画像の左上が (0, 0)。実際の読み取りは高さ 0.04 前後の文字が並ぶ
private func box(_ text: String, x: Double, y: Double, w: Double = 0.08, h: Double = 0.04) -> SheetTextBox {
    SheetTextBox(text: text, x: x, y: y, width: w, height: h)
}

@Suite("写真から読んだ文字を表に組み直す")
struct SheetReaderTests {

    @Test("縦の位置が近いものは同じ行。行の中は左から並べる")
    func groupsRowsAndSortsByX() {
        // わざと順番をばらばらに、縦も少しずらして渡す
        let boxes = [
            box("斎藤", x: 0.60, y: 0.102), box("中村", x: 0.20, y: 0.100), box("五十嵐", x: 0.40, y: 0.098),
            box("-10", x: 0.60, y: 0.200), box("30", x: 0.20, y: 0.202), box("10", x: 0.40, y: 0.199),
        ]
        #expect(SheetReader.csv(from: boxes) == "中村,五十嵐,斎藤\n30,10,-10")
    }

    @Test("行の高さより大きくずれていれば、別の行になる")
    func splitsRows() {
        let boxes = [box("30", x: 0.2, y: 0.10), box("10", x: 0.2, y: 0.14), box("-40", x: 0.2, y: 0.18)]
        #expect(SheetReader.rows(from: boxes).count == 3)
        #expect(SheetReader.csv(from: boxes) == "30\n10\n-40")
    }

    @Test("読み取りに混ざるカンマは列の区切りとぶつかるので落とす")
    func dropsCommas() {
        let boxes = [box("1,000", x: 0.2, y: 0.1), box("-1，200", x: 0.5, y: 0.1)]
        #expect(SheetReader.csv(from: boxes) == "1000,-1200")
    }

    @Test("空の読み取りは行にしない")
    func skipsEmpty() {
        let boxes = [box(" ", x: 0.1, y: 0.1), box("30", x: 0.3, y: 0.1)]
        #expect(SheetReader.csv(from: boxes) == "30")
        #expect(SheetReader.csv(from: []) == "")
    }

    @Test("組み直した CSV は、そのまま取り込みに渡せる")
    func feedsCSVImport() throws {
        let boxes = [
            box("中村", x: 0.2, y: 0.10), box("五十嵐", x: 0.4, y: 0.10),
            box("斎藤", x: 0.6, y: 0.10), box("佐々木", x: 0.8, y: 0.10),
            box("30", x: 0.2, y: 0.20), box("10", x: 0.4, y: 0.20),
            box("▲10", x: 0.6, y: 0.20), box("▲30", x: 0.8, y: 0.20),
        ]
        let games = try CSVImport.parse(SheetReader.csv(from: boxes))
        #expect(games.count == 1)
        #expect(games[0].session.players == ["中村", "五十嵐", "斎藤", "佐々木"])
        #expect(games[0].session.playerStats().map(\.total) == [30, 10, -10, -30])
    }
}

@Suite("写真から読んだ表の崩れを吸収する")
struct SheetReaderRobustnessTests {

    @Test("題名の行と、崩れた合計の行があっても取り込める")
    func titleAndGarbledTotal() throws {
        // 実際に読み取ったもの（他のアプリの画面）。合計が「合卵9」に化けた
        let csv = """
        対局結果
        中村,五十嵐,斎藤,佐々木
        30,10,-10,-30
        -20,40,0,-20
        合卵9,45,-1,-103
        """
        let games = try CSVImport.parse(csv)
        #expect(games.count == 1)
        #expect(games[0].session.players == ["中村", "五十嵐", "斎藤", "佐々木"])
        #expect(games[0].session.playedRoundCount == 2)
        #expect(games[0].session.playerStats().map(\.total) == [10, 50, -10, -50])
    }

    @Test("「合」で始まる名前の行は、合計と間違えない")
    func nameStartingWithTotalCharacter() throws {
        let csv = """
        中村,五十嵐,斎藤,佐々木
        30,10,-10,-30
        合田,田中,佐藤,鈴木
        20,-10,-5,-5
        """
        let games = try CSVImport.parse(csv)
        #expect(games.count == 2)
        #expect(games[1].session.players == ["合田", "田中", "佐藤", "鈴木"])
    }
}
