import Testing
import Foundation
@testable import JansanCore

// 集計画面の数字の出どころ。1つずつ手で数えられる小さな表で固定する

/// nil はお休み
private func game(_ players: [String], _ rows: [[Int?]], style: Int = 4,
                  day: Double = 0, decimalMode: Bool = false) -> GameForStats {
    let rounds = rows.map { Round(entries: $0.map { $0.map(Entry.entered) ?? .resting }) }
    let session = Session(players: players, rounds: rounds, decimalMode: decimalMode, playersPerRound: style)
    return GameForStats(playedAt: Date(timeIntervalSince1970: 1_700_000_000 + day * 86_400), session: session)
}

private let abcd = ["A", "B", "C", "D"]

private func report(_ name: String, in reports: [PlayerReport]) -> PlayerReport {
    reports.first { $0.name == name }!
}

@Suite("詳しい成績・着順と率")
struct PlayerReportRankTests {

    private let games = [
        game(abcd, [[30, 10, -10, -30],
                    [-20, 40, 0, -20],
                    [50, -10, -15, -25]]),
    ]

    @Test("着順の回数・平均着順・トップ率・連対率")
    func ranks() {
        let a = report("A", in: Report.players(games: games))
        #expect(a.rounds == 3)
        #expect(a.total == 60)
        #expect(a.rankCounts == [2, 0, 1])
        #expect(a.averageRank == 5.0 / 3.0)
        #expect(a.topRate == 2.0 / 3.0)
        #expect(a.rentaiRate == 2.0 / 3.0)
    }

    @Test("同点は列の並びで先の人が上。表の中の集計と同じ")
    func tieBreak() {
        // 2局目は A と D が -20 で並ぶ。列が先の A が3位、D が4位
        let reports = Report.players(games: games)
        #expect(report("A", in: reports).count(ofRank: 3) == 1)
        #expect(report("D", in: reports).count(ofRank: 4) == 3)
    }

    @Test("ラスはその局の最下位で数える。一度も4位が無い人の3位はラスではない")
    func lastIsPerRound() {
        let c = report("C", in: Report.players(games: games))
        #expect(c.count(ofRank: 4) == 0)
        #expect(c.lastCount == 0)
        #expect(c.lastRate == 0)
        #expect(c.lastAvoidRate == 1)
        #expect(report("D", in: Report.players(games: games)).lastRate == 1)
    }

    @Test("プラス率・1局の最高と最低")
    func scores() {
        let b = report("B", in: Report.players(games: games))
        #expect(b.plusRounds == 2)
        #expect(b.plusRate == 2.0 / 3.0)
        #expect(b.bestRound == 40)
        #expect(b.worstRound == -10)
    }

    @Test("お休みの局は数えない。5人の四麻でも着順は4位まで")
    func restingAndFivePlayers() {
        let five = [game(abcd + ["E"], [[30, 10, -10, -30, nil],
                                        [nil, 20, 10, -10, -20]])]
        let reports = Report.players(games: five)
        #expect(report("A", in: reports).rounds == 1)
        #expect(report("E", in: reports).rankCounts == [0, 0, 0, 1])
        #expect(reports.allSatisfy { $0.rankCounts.count <= 4 })
    }

    @Test("入力途中の局は数えない")
    func incompleteRoundsAreSkipped() {
        var session = Session(players: abcd)
        session.enter(30, at: Position(round: 0, column: 0))
        let reports = Report.players(games: [GameForStats(playedAt: .now, session: session)])
        #expect(reports.isEmpty)
    }
}

@Suite("詳しい成績・連続・対局単位・最近")
struct PlayerReportSequenceTests {

    @Test("連続記録は1回の記録の中だけで数える。次の記録に移ると途切れる")
    func streaksStopAtEndOfRecord() {
        // 1日目の最後の局と2日目の最初の2局で A がトップ。記録をまたぐので3連続にはしない
        let earlier = game(abcd, [[-30, 10, -10, 30], [30, 10, -10, -30]], day: 1)
        let later = game(abcd, [[30, 10, -10, -30], [40, 0, -10, -30]], day: 2)
        // 配列の並びではなく対局日の順に数える。後の日を先に渡す
        let a = report("A", in: Report.players(games: [later, earlier]))
        #expect(a.longestTopStreak == 2)
        #expect(a.longestTopStreakDate == later.playedAt)
        #expect(a.longestLastStreak == 1)
        #expect(a.longestLastStreakDate == earlier.playedAt)
        #expect(a.longestNoLastStreak == 2)
        #expect(a.longestNoLastStreakDate == later.playedAt)
    }

    @Test("同じ長さの連続は、先に出した日を残す")
    func streakTieKeepsEarlierDate() {
        let first = game(abcd, [[30, 10, -10, -30], [30, 10, -10, -30]], day: 1)
        let second = game(abcd, [[30, 10, -10, -30], [30, 10, -10, -30]], day: 2)
        let a = report("A", in: Report.players(games: [first, second]))
        #expect(a.longestTopStreak == 2)
        #expect(a.longestTopStreakDate == first.playedAt)
    }

    @Test("トップを取っていない人の連続トップは0で、日付は無い")
    func noStreakNoDate() {
        let d = report("D", in: Report.players(games: [game(abcd, [[30, 10, -10, -30]])]))
        #expect(d.longestTopStreak == 0)
        #expect(d.longestTopStreakDate == nil)
    }

    @Test("対局の合計で1位の回数・プラスの対局・最高と最低の対局")
    func gameLevel() {
        let games = [
            game(abcd, [[30, 10, -10, -30], [-20, 40, 0, -20]], day: 1),   // A +10, B +50 → B がトップ
            game(abcd, [[50, -10, -15, -25]], day: 2),                     // A +50 → A がトップ
        ]
        let reports = Report.players(games: games)
        let a = report("A", in: reports)
        #expect(a.games == 2)
        #expect(a.gameTops == 1)
        #expect(a.plusGames == 2)
        #expect(a.bestGame == 50)
        #expect(a.worstGame == 10)
        #expect(report("B", in: reports).gameTops == 1)
        #expect(report("D", in: reports).plusGames == 0)
    }

    @Test("最高・最低の1局と対局に、それを出した日が付く。同じ点なら先の日")
    func recordDates() {
        let first = game(abcd, [[50, -10, -15, -25]], day: 1)          // A 最高の1局 +50（1日目）
        let second = game(abcd, [[50, 10, -20, -40], [-60, 20, 20, 20]], day: 2)  // A +50 は同点、-60 が最低
        let a = report("A", in: Report.players(games: [second, first]))
        #expect(a.bestRound == 50)
        #expect(a.bestRoundDate == first.playedAt)
        #expect(a.worstRound == -60)
        #expect(a.worstRoundDate == second.playedAt)
        #expect(a.bestGame == 50)
        #expect(a.bestGameDate == first.playedAt)
        #expect(a.worstGame == -10)
        #expect(a.worstGameDate == second.playedAt)
    }

    @Test("最近の成績は直近10局だけ")
    func recentForm() {
        // A は最初の2局だけラス、あとの10局はトップ
        let rows: [[Int?]] = [[-30, 10, 10, 10], [-30, 10, 10, 10]]
            + Array(repeating: [30, -10, -10, -10], count: 10)
        let a = report("A", in: Report.players(games: [game(abcd, rows)]))
        #expect(a.rounds == 12)
        #expect(a.recent?.rounds == 10)
        #expect(a.recent?.averageRank == 1)
        #expect(a.recent?.total == 300)
    }
}

@Suite("詳しい成績・相性と打ち方")
struct PlayerReportMatchupTests {

    @Test("同じ局を打った数・上回った局・点数差")
    func matchup() {
        let games = [game(abcd + ["E"], [[30, 10, -10, -30, nil],
                                        [20, nil, 10, -10, -20]])]
        let vsB = Report.matchups(for: "A", games: games).first { $0.opponent == "B" }!
        #expect(vsB.rounds == 1)
        #expect(vsB.wins == 1)
        #expect(vsB.difference == 20)
        let vsC = Report.matchups(for: "A", games: games).first { $0.opponent == "C" }!
        #expect(vsC.rounds == 2)
        #expect(vsC.winRate == 1)
        #expect(vsC.averageDifference == 25)
        // 一緒に打った局の多い順
        #expect(Report.matchups(for: "A", games: games).first?.rounds == 2)
    }

    @Test("三麻と四麻で分ける。5人の四麻は四麻")
    func styles() {
        let games = [
            game(abcd, [[30, 10, -10, -30]]),
            game(abcd + ["E"], [[30, 10, -10, -30, nil]]),
            game(["A", "B", "C"], [[30, -10, -20]], style: 3),
        ]
        #expect(Report.availableStyles(games: games) == [4, 3])
        #expect(Report.select(games: games, style: 4).count == 2)
        #expect(Report.select(games: games, style: 3).count == 1)
    }

    @Test("三麻/四麻を選べる前の3人の表（打ち方が既定の4のまま）は三麻に入る")
    func oldThreePlayerTableIsSanma() {
        let old = game(["A", "B", "C"], [[30, -10, -20]], style: 4)
        #expect(old.style == 3)
        #expect(Report.select(games: [old], style: 3).count == 1)
    }

    @Test("対局の数と局の数")
    func roundCount() {
        let games = [game(abcd, [[30, 10, -10, -30], [-20, 40, 0, -20]]), game(abcd, [[1, 1, -1, -1]])]
        #expect(Report.roundCount(games: games) == 3)
    }
}

@Suite("記録の一覧の並び")
struct RecordOrderTests {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("対局日の新しい順。保存した順ではない")
    func byPlayedDate() {
        // 古い対局を後から保存しても、対局日で並ぶ
        #expect(PlayedDate.newestFirst(played: base.addingTimeInterval(86_400), saved: base,
                                       before: base, saved: base.addingTimeInterval(999_999)))
    }

    @Test("日付未記入は最後")
    func unknownLast() {
        #expect(PlayedDate.newestFirst(played: base, saved: base,
                                       before: PlayedDate.unknown, saved: base.addingTimeInterval(999_999)))
        #expect(PlayedDate.newestFirst(played: PlayedDate.unknown, saved: base.addingTimeInterval(999_999),
                                       before: base, saved: base) == false)
    }

    @Test("対局日が無い古い記録は保存日時で並ぶ")
    func legacyUsesSavedAt() {
        #expect(PlayedDate.newestFirst(played: nil, saved: base.addingTimeInterval(10),
                                       before: base, saved: base))
    }
}

@Suite("絶好調（卓の直近で切る）")
struct RecentWindowTests {

    @Test("しばらく来ていない人は、直近の局に入らない")
    func absentPlayerDropsOut() {
        // A は昔の5局で大勝ち。そのあと A 抜きで20局
        let old = game(abcd, Array(repeating: [60, -20, -20, -20], count: 5), day: 1)
        let recent = game(abcd + ["E"], Array(repeating: [nil, 10, 0, -10, 0], count: 20), day: 2)
        let window = Report.recentWindow(games: [recent, old])
        #expect(window.contains { $0.name == "A" } == false)
        #expect(window.first { $0.name == "B" }?.rounds == 20)
        #expect(window.first { $0.name == "B" }?.averageScore == 10)
    }

    @Test("直近の局が足りなければ、ある分だけで見る")
    func shortHistory() {
        let a = Report.recentWindow(games: [game(abcd, [[30, 10, -10, -30], [20, 0, -10, -10]])])
            .first { $0.name == "A" }!
        #expect(a.rounds == 2)
        #expect(a.total == 50)
        #expect(a.averageScore == 25)
    }

    @Test("直近は対局日の順で決める。配列の並びではない")
    func windowFollowsDates() {
        let newer = game(abcd, [[30, 10, -10, -30]], day: 2)
        let older = game(abcd, [[-30, 10, -10, 30]], day: 1)
        let a = Report.recentWindow(games: [newer, older], window: 1).first { $0.name == "A" }!
        #expect(a.total == 30)
    }
}
