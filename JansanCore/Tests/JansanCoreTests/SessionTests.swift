import Testing
@testable import JansanCore

// プロトタイプ(HTML)で詰めた挙動をそのまま仕様として固定する。
// UIを載せ替えてもここが通っていれば計算は壊れていない。

private let yonma = ["中村", "五十嵐", "斎藤", "佐々木"]

@Suite("点数の自動計算")
struct RecomputeTests {

    @Test("3人分入力すると残り1人が合計0から逆算される")
    func derivesLastPlayer() {
        var session = Session(players: yonma)
        session.enter(-32, at: Position(round: 0, column: 0))
        session.enter(71, at: Position(round: 0, column: 1))
        session.enter(-50, at: Position(round: 0, column: 2))

        #expect(session.rounds[0].entries[3] == .derived(11))
        #expect(session.rounds[0].isComplete)
    }

    @Test("2人分だけでは逆算しない")
    func waitsUntilOnlyOneRemains() {
        var session = Session(players: yonma)
        session.enter(-32, at: Position(round: 0, column: 0))
        session.enter(71, at: Position(round: 0, column: 1))

        #expect(session.rounds[0].entries[2] == .empty)
        #expect(session.rounds[0].entries[3] == .empty)
        #expect(!session.rounds[0].isComplete)
    }

    @Test("2〜3着を後から訂正するとトップも連動して再計算される")
    func correctingLowerRanksUpdatesTop() {
        var session = Session(players: yonma)
        session.enter(-32, at: Position(round: 0, column: 0))
        session.enter(71, at: Position(round: 0, column: 1))
        session.enter(-50, at: Position(round: 0, column: 2))
        #expect(session.rounds[0].entries[3] == .derived(11))

        // 3着を -50 から -40 に訂正
        session.enter(-40, at: Position(round: 0, column: 2))
        #expect(session.rounds[0].entries[3] == .derived(1))
    }

    @Test("お休みがいる局は残りの参加者だけで合計0にする")
    func restingIsExcluded() {
        var session = Session(players: ["A", "B", "C", "D"])
        session.toggleResting(at: Position(round: 0, column: 3))
        session.enter(30, at: Position(round: 0, column: 0))
        session.enter(-10, at: Position(round: 0, column: 1))

        #expect(session.rounds[0].entries[2] == .derived(-20))
        #expect(session.rounds[0].entries[3] == .resting)
        #expect(session.rounds[0].isComplete)
    }
}

@Suite("行の自動追加")
struct RoundAppendTests {

    @Test("開始時は1局のみ")
    func startsWithSingleRound() {
        #expect(Session(players: yonma).rounds.count == 1)
    }

    @Test("入力待ちの空行は局数に数えない")
    func playedRoundCountIgnoresTrailingBlank() {
        var session = Session(players: yonma)
        #expect(session.playedRoundCount == 0)

        session.enter(-32, at: Position(round: 0, column: 0))
        #expect(session.playedRoundCount == 1) // 入力途中でも1局として数える

        session.enter(71, at: Position(round: 0, column: 1))
        session.enter(-50, at: Position(round: 0, column: 2))
        // 空行が足された直後。増えた行は数えない
        #expect(session.rounds.count == 2)
        #expect(session.playedRoundCount == 1)
    }

    @Test("局が埋まると次の空行が足される")
    func appendsWhenComplete() {
        var session = Session(players: yonma)
        session.enter(-32, at: Position(round: 0, column: 0))
        #expect(session.rounds.count == 1)

        session.enter(71, at: Position(round: 0, column: 1))
        session.enter(-50, at: Position(round: 0, column: 2))
        #expect(session.rounds.count == 2)
    }
}

@Suite("カーソルの自動移動")
struct CursorTests {

    @Test("右隣が空いていれば右へ進む")
    func prefersRight() {
        let session = Session(players: yonma)
        #expect(session.nextOpenPosition(after: Position(round: 0, column: 0)) == Position(round: 0, column: 1))
    }

    @Test("右が埋まっていれば左側へ戻る。左端ではなく現在地に近い方から探す")
    func fallsBackToLeft() {
        var session = Session(players: yonma)
        session.enter(50, at: Position(round: 0, column: 2))
        session.enter(-20, at: Position(round: 0, column: 3))

        // 空いているのは0列目と1列目。近い1列目が選ばれる
        #expect(session.nextOpenPosition(after: Position(round: 0, column: 3)) == Position(round: 0, column: 1))
    }

    @Test("その局が埋まったら次の局の先頭へ")
    func movesToNextRound() {
        var session = Session(players: yonma)
        session.enter(-32, at: Position(round: 0, column: 0))
        session.enter(71, at: Position(round: 0, column: 1))
        session.enter(-50, at: Position(round: 0, column: 2))

        #expect(session.nextOpenPosition(after: Position(round: 0, column: 2)) == Position(round: 1, column: 0))
    }

    @Test("四人打ちでは1〜2人目の入力後もきちんと次のマスへ進む")
    func fourPlayerNeverStalls() {
        // プロトタイプで実際に踏んだ不具合。四人打ちの通常時に途中で止まっていた
        var session = Session(players: yonma)
        session.enter(-32, at: Position(round: 0, column: 0))

        #expect(!session.needsWinnerDesignation(at: 0))
        #expect(session.nextOpenPosition(after: Position(round: 0, column: 0)) == Position(round: 0, column: 1))
    }
}

@Suite("5〜6人打ちの4人目指定")
struct WinnerDesignationTests {

    private let rokunin = ["A", "B", "C", "D", "E", "F"]

    @Test("四人打ちではタップ指定を待たない")
    func notNeededForFourPlayers() {
        var session = Session(players: yonma)
        session.enter(-32, at: Position(round: 0, column: 0))
        session.enter(71, at: Position(round: 0, column: 1))
        session.enter(-50, at: Position(round: 0, column: 2))

        #expect(!session.needsWinnerDesignation(at: 0))
    }

    @Test("6人で3人分入力すると、4人目のタップ待ちになる")
    func waitsAfterThreeEntries() {
        var session = Session(players: rokunin)
        session.enter(-32, at: Position(round: 0, column: 0))
        session.enter(71, at: Position(round: 0, column: 1))
        session.enter(-50, at: Position(round: 0, column: 2))

        #expect(session.needsWinnerDesignation(at: 0))
        #expect(session.canDesignateWinner(at: Position(round: 0, column: 4)))
    }

    @Test("タップした人が4人目として確定し、残りはその局だけお休みになる")
    func designationRestsTheOthers() {
        var session = Session(players: rokunin)
        session.enter(-32, at: Position(round: 0, column: 0))
        session.enter(71, at: Position(round: 0, column: 1))
        session.enter(-50, at: Position(round: 0, column: 2))
        session.designateWinner(at: Position(round: 0, column: 4))

        #expect(session.rounds[0].entries[3] == .resting)
        #expect(session.rounds[0].entries[4] == .derived(11))
        #expect(session.rounds[0].entries[5] == .resting)
        #expect(session.rounds[0].isComplete)
        #expect(session.rounds.count == 2)
    }
}

@Suite("合計と成績")
struct StatsTests {

    private func playedSession() -> Session {
        var session = Session(players: yonma)
        let demo = [
            [-32, 71, -50],
            [51, -52, 15],
            [15, -32, 61],
        ]
        for (roundIndex, scores) in demo.enumerated() {
            for (column, score) in scores.enumerated() {
                session.enter(score, at: Position(round: roundIndex, column: column))
            }
        }
        return session
    }

    @Test("合計は自動計算されたマスも含める")
    func totalsIncludeDerived() {
        let session = playedSession()
        #expect(session.totals == [34, -13, 26, -47])
        // 各局の合計は必ず0なので、全員の合計も0になる
        #expect(session.totals.reduce(0, +) == 0)
    }

    @Test("着順と平均着順を全員確定した局だけで集計する")
    func ranksCountOnlyCompletedRounds() {
        var session = playedSession()
        session.enter(10, at: Position(round: 3, column: 0)) // 入力途中の局は数えない

        let stats = session.playerStats()
        let nakamura = stats[0]
        #expect(nakamura.played == 3)
        #expect(nakamura.count(ofRank: 1) == 1) // 2局目の51がトップ
        #expect(nakamura.averageRank == 2.0)
    }

    @Test("トップとラスを判定する。全員同点なら色を付けない")
    func topAndLast() {
        let session = playedSession()
        let first = session.rounds[0].topAndLastColumns
        #expect(first?.top == [1])
        #expect(first?.last == [2])

        var flat = Session(players: ["A", "B", "C", "D"])
        for column in 0..<3 { flat.enter(0, at: Position(round: 0, column: column)) }
        #expect(flat.rounds[0].topAndLastColumns == nil)
    }
}

@Suite("表示フォーマット")
struct FormatterTests {

    @Test("小数点モードは末尾1桁を小数として扱う")
    func decimalMode() {
        #expect(ScoreFormatter.string(323, decimalMode: true) == "32.3")
        #expect(ScoreFormatter.string(323, decimalMode: false) == "323")
        #expect(ScoreFormatter.string(4, decimalMode: true) == "0.4")
        #expect(ScoreFormatter.string(80, decimalMode: true) == "8.0")
    }

    @Test("マイナスの点数も正しく表示する")
    func negativeValues() {
        #expect(ScoreFormatter.string(-157, decimalMode: true) == "-15.7")
        #expect(ScoreFormatter.string(-5, decimalMode: true) == "-0.5")
        #expect(ScoreFormatter.signedString(80, decimalMode: true) == "+8.0")
    }
}

@Suite("参加メンバーの変更")
struct PlayerChangeTests {

    @Test("人数を変えても、残るメンバーの入力は名前基準で引き継がれる")
    func keepsEntriesByName() {
        var session = Session(players: yonma)
        session.enter(-32, at: Position(round: 0, column: 0))
        session.enter(71, at: Position(round: 0, column: 1))

        session.setPlayers(["中村", "五十嵐", "斎藤"]) // 三人打ちへ

        #expect(session.players.count == 3)
        #expect(session.rounds[0].entries[0] == .entered(-32))
        #expect(session.rounds[0].entries[1] == .entered(71))
        #expect(session.rounds[0].entries[2] == .derived(-39)) // 3人になったので逆算が成立する
    }
}
