import Testing
@testable import JansanCore

private let yonma = ["中村", "五十嵐", "斎藤", "佐々木"]

@Suite("局の削除")
struct RemoveRoundTests {

    private func threeRounds() -> Session {
        var session = Session(players: yonma)
        for (index, scores) in [[-32, 71, -50], [51, -52, 15], [15, -32, 61]].enumerated() {
            for (column, score) in scores.enumerated() {
                session.enter(score, at: Position(round: index, column: column))
            }
        }
        return session
    }

    @Test("指定した局が消え、以降が繰り上がる")
    func removesAndShiftsUp() {
        var session = threeRounds()
        #expect(session.playedRoundCount == 3)

        session.removeRound(at: 1) // 2局目(51, -52, 15, -14)を消す
        #expect(session.playedRoundCount == 2)
        #expect(session.rounds[1].entries[0] == .entered(15)) // 3局目が2局目に繰り上がる
    }

    @Test("削除すると合計も計算し直される")
    func totalsFollow() {
        var session = threeRounds()
        let before = session.totals
        session.removeRound(at: 0)
        #expect(session.totals != before)
        #expect(session.totals.reduce(0, +) == 0)
    }

    @Test("1局しか無いときは行を残して中身だけ消す")
    func keepsLastRow() {
        var session = Session(players: yonma)
        session.enter(-32, at: Position(round: 0, column: 0))
        session.removeRound(at: 0)

        #expect(session.rounds.count == 1)
        #expect(session.rounds[0].entries.allSatisfy { $0 == .empty })
    }

    @Test("最後の空行を消しても入力先が無くならない")
    func keepsAnOpenRound() {
        var session = threeRounds()
        let blankIndex = session.rounds.count - 1
        session.removeRound(at: blankIndex)

        // 直前の局が埋まっているので、新しい空行が用意される
        #expect(session.rounds.last?.entries.contains { $0.isOpen } == true)
    }

    @Test("範囲外を指定しても何も起きない")
    func ignoresBadIndex() {
        var session = threeRounds()
        let before = session.rounds
        session.removeRound(at: 99)
        #expect(session.rounds == before)
    }
}
