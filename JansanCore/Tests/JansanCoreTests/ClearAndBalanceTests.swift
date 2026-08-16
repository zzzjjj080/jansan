import Testing
@testable import JansanCore

private let yonma = ["中村", "五十嵐", "斎藤", "佐々木"]

@Suite("マスのクリア")
struct ClearTests {

    private func filledRound() -> Session {
        var session = Session(players: yonma)
        session.enter(-32, at: Position(round: 0, column: 0))
        session.enter(71, at: Position(round: 0, column: 1))
        session.enter(-50, at: Position(round: 0, column: 2))
        return session
    }

    @Test("手入力したマスを空に戻せる")
    func clearsEnteredCell() {
        var session = filledRound()
        // 3人入力済み・4人目は逆算で 11
        #expect(session.rounds[0].entries[3] == .derived(11))

        session.clear(at: Position(round: 0, column: 0))
        #expect(session.rounds[0].entries[0] == .empty)
    }

    @Test("クリアした結果、他の3人が埋まっていればそのマスが逆算される")
    func clearedCellBecomesDerived() {
        var session = filledRound()
        // 4人目を手で上書きして、全員が手入力の状態にする
        session.enter(99, at: Position(round: 0, column: 3))
        #expect(session.rounds[0].entries[3] == .entered(99))

        // 2人目を消すと、残り3人から2人目が逆算される
        session.clear(at: Position(round: 0, column: 1))
        #expect(session.rounds[0].entries[1] == .derived(-(-32 - 50 + 99)))
        #expect(session.rounds[0].isUnbalanced == false)
    }

    @Test("お休みのマスもクリアできる")
    func clearsResting() {
        var session = Session(players: yonma)
        session.toggleResting(at: Position(round: 0, column: 3))
        session.clear(at: Position(round: 0, column: 3))
        #expect(session.rounds[0].entries[3] == .empty)
    }

    @Test("範囲外を指定しても何も起きない")
    func ignoresBadPosition() {
        var session = filledRound()
        let before = session.rounds
        session.clear(at: Position(round: 9, column: 0))
        session.clear(at: Position(round: 0, column: 9))
        #expect(session.rounds == before)
    }
}

@Suite("合計が合わない局の検出")
struct BalanceTests {

    @Test("逆算で埋まった局は必ず釣り合う")
    func derivedRoundIsBalanced() {
        var session = Session(players: yonma)
        session.enter(-32, at: Position(round: 0, column: 0))
        session.enter(71, at: Position(round: 0, column: 1))
        session.enter(-50, at: Position(round: 0, column: 2))
        #expect(session.rounds[0].isUnbalanced == false)
    }

    @Test("4人すべてを手で入れて合計が0でなければ検出する")
    func detectsManualImbalance() {
        var session = Session(players: yonma)
        session.enter(10, at: Position(round: 0, column: 0))
        session.enter(10, at: Position(round: 0, column: 1))
        session.enter(10, at: Position(round: 0, column: 2))
        // ここまでで4人目は -30 に逆算される。それを手で 0 に上書きする
        session.enter(0, at: Position(round: 0, column: 3))

        #expect(session.rounds[0].isComplete)
        #expect(session.rounds[0].isUnbalanced)
    }

    @Test("入力途中の局は警告しない")
    func incompleteRoundIsNotFlagged() {
        var session = Session(players: yonma)
        session.enter(10, at: Position(round: 0, column: 0))
        #expect(session.rounds[0].isUnbalanced == false)
    }

    @Test("お休みを除いた参加者だけで判定する")
    func ignoresRestingPlayers() {
        var session = Session(players: yonma)
        session.toggleResting(at: Position(round: 0, column: 3))
        session.enter(30, at: Position(round: 0, column: 0))
        session.enter(-10, at: Position(round: 0, column: 1))
        // 3人目が -20 に逆算されて釣り合う
        #expect(session.rounds[0].isUnbalanced == false)
    }
}
