import Testing
@testable import JansanCore

@Suite("CSV書き出し")
struct CSVExportTests {

    private func played() -> Session {
        var session = Session(players: ["中村", "五十嵐", "斎藤", "佐々木"])
        session.enter(-32, at: Position(round: 0, column: 0))
        session.enter(71, at: Position(round: 0, column: 1))
        session.enter(-50, at: Position(round: 0, column: 2))
        return session
    }

    @Test("見出し・各局・合計が並ぶ")
    func layout() {
        let lines = played().csv().split(separator: "\n").map(String.init)
        #expect(lines[0] == "No,中村,五十嵐,斎藤,佐々木")
        #expect(lines[1] == "1,-32,71,-50,11")
        #expect(lines[2] == "合計,-32,71,-50,11")
    }

    @Test("入力待ちの空行は出さない")
    func skipsTrailingBlankRound() {
        // 局が埋まると空行が足されるが、CSVには出さない
        #expect(played().rounds.count == 2)
        #expect(played().csv().split(separator: "\n").count == 3)
    }

    @Test("お休みは空欄にして0と区別する")
    func restingIsBlank() {
        var session = Session(players: ["A", "B", "C", "D"])
        session.toggleResting(at: Position(round: 0, column: 3))
        session.enter(30, at: Position(round: 0, column: 0))
        session.enter(-10, at: Position(round: 0, column: 1))

        let lines = session.csv().split(separator: "\n").map(String.init)
        #expect(lines[1] == "1,30,-10,-20,")
    }

    @Test("小数点モードは表示と同じ形で書き出す")
    func decimalMode() {
        var session = played()
        session.decimalMode = true
        let lines = session.csv().split(separator: "\n").map(String.init)
        #expect(lines[1] == "1,-3.2,7.1,-5.0,1.1")
    }
}
