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

@Suite("順位")
struct RankingTests {

    @Test("合計点の高い順に1位から並ぶ")
    func ordersByTotal() {
        var session = Session(players: yonma)
        session.enter(-32, at: Position(round: 0, column: 0))
        session.enter(71, at: Position(round: 0, column: 1))
        session.enter(-50, at: Position(round: 0, column: 2))
        // 合計: -32, 71, -50, 11
        #expect(session.rankings() == [3, 1, 4, 2])
    }

    @Test("同点は同じ順位になり、次の順位が飛ぶ")
    func sharesRankOnTie() {
        var session = Session(players: yonma)
        session.enter(30, at: Position(round: 0, column: 0))
        session.enter(0, at: Position(round: 0, column: 1))
        session.enter(0, at: Position(round: 0, column: 2))
        // 合計: 30, 0, 0, -30
        #expect(session.rankings() == [1, 2, 2, 4])
    }

    @Test("何も入力していなければ全員1位")
    func allTiedWhenEmpty() {
        #expect(Session(players: yonma).rankings() == [1, 1, 1, 1])
    }
}
