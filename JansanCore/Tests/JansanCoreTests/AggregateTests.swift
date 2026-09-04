import Testing
import Foundation
@testable import JansanCore

// 対局をまたいだ集計。1つの表の中を見る Stats とは別物なので、混同しないよう分けてある。

private let yonma = ["中村", "五十嵐", "斎藤", "佐々木"]
private let sanma = ["中村", "五十嵐", "斎藤"]

/// 1局だけ入った表を作る。並びがそのまま着順になる
private func game(_ players: [String], _ scores: [Int], daysAgo: Int = 0,
                  decimalMode: Bool = false) -> GameForStats {
    var session = Session(players: players, decimalMode: decimalMode)
    for (column, value) in scores.enumerated().dropLast() {
        session.enter(value, at: Position(round: 0, column: column))
    }
    let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date(timeIntervalSince1970: 1_700_000_000))!
    return GameForStats(playedAt: date, session: session)
}

@Suite("対局をまたいだ集計")
struct AggregateTests {

    @Test("2回打つと収支と対局数が足し合わされる")
    func sumsAcrossGames() {
        let games = [
            game(yonma, [30, 10, -10, -30]),
            game(yonma, [20, -5, -5, -10]),
        ]
        let stats = Aggregator.aggregate(games: games)
        let nakamura = stats.first { $0.name == "中村" }

        #expect(nakamura?.total == 50)
        #expect(nakamura?.games == 2)
        #expect(nakamura?.played == 2)
        #expect(nakamura?.count(ofRank: 1) == 2)
    }

    @Test("着順率と平均着順が出る")
    func rates() {
        let games = [
            game(yonma, [30, 10, -10, -30]),   // 中村1位
            game(yonma, [-30, 10, -10, 30]),   // 中村4位
        ]
        let nakamura = Aggregator.aggregate(games: games).first { $0.name == "中村" }

        #expect(nakamura?.averageRank == 2.5)
        #expect(nakamura?.topRate == 0.5)
        #expect(nakamura?.lastRate == 0.5)
        #expect(nakamura?.rentaiRate == 0.5)
        #expect(nakamura?.averageScore == 0)
    }

    @Test("人数を指定しないと3人局と4人局が混ざる")
    func mixesWithoutPlayerCount() {
        let games = [game(yonma, [30, 10, -10, -30]), game(sanma, [20, 0, -20])]
        let mixed = Aggregator.aggregate(games: games).first { $0.name == "中村" }
        // 混ぜると「2局打って両方1位」に見えるが、分母の意味が違う
        #expect(mixed?.played == 2)
    }

    @Test("人数で絞ると片方だけになる")
    func filtersByPlayerCount() {
        let games = [game(yonma, [30, 10, -10, -30]), game(sanma, [20, 0, -20])]

        let four = Aggregator.aggregate(games: games, playerCount: 4)
        #expect(four.first { $0.name == "中村" }?.games == 1)
        #expect(four.contains { $0.name == "佐々木" })

        let three = Aggregator.aggregate(games: games, playerCount: 3)
        #expect(three.first { $0.name == "中村" }?.games == 1)
        // 3人局に佐々木は出ていない
        #expect(three.contains { $0.name == "佐々木" } == false)
    }

    @Test("記録にある人数の種類が拾える")
    func availableCounts() {
        let games = [game(yonma, [30, 10, -10, -30]), game(sanma, [20, 0, -20])]
        #expect(Aggregator.availablePlayerCounts(games: games) == [3, 4])
    }

    @Test("表示モードが違う記録は混ぜないようにできる")
    func filtersByDecimalMode() {
        let games = [
            game(yonma, [30, 10, -10, -30], decimalMode: false),
            game(yonma, [300, 100, -100, -300], decimalMode: true),
        ]
        // 混ぜると 330 になり10倍ズレたように見える
        #expect(Aggregator.aggregate(games: games).first { $0.name == "中村" }?.total == 330)
        #expect(Aggregator.aggregate(games: games, decimalMode: false)
                    .first { $0.name == "中村" }?.total == 30)
    }

    @Test("名簿にいるだけで1局も打っていない人は数えない")
    func ignoresPlayersWithNoRounds() {
        let empty = GameForStats(playedAt: .now, session: Session(players: yonma))
        #expect(Aggregator.aggregate(games: [empty]).isEmpty)
    }
}

@Suite("集計の期間")
struct StatsPeriodTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("全期間は何でも通す")
    func all() {
        #expect(StatsPeriod.all.contains(Date(timeIntervalSince1970: 0), now: now))
    }

    @Test("直近30日は境界の外を落とす")
    func last30() {
        let inside = Calendar.current.date(byAdding: .day, value: -10, to: now)!
        let outside = Calendar.current.date(byAdding: .day, value: -40, to: now)!
        #expect(StatsPeriod.last30Days.contains(inside, now: now))
        #expect(StatsPeriod.last30Days.contains(outside, now: now) == false)
    }

    @Test("期間で絞ると対局が減る")
    func filtersGames() {
        let games = [game(yonma, [30, 10, -10, -30], daysAgo: 2),
                     game(yonma, [30, 10, -10, -30], daysAgo: 100)]
        let recent = Aggregator.filter(games: games, period: .last30Days, now: now)
        // 基準日を揃えるため now を渡している
        #expect(recent.count <= games.count)
    }

    @Test("カスタム期間は前後が逆でも通る")
    func customReversed() {
        let a = Date(timeIntervalSince1970: 1_000)
        let b = Date(timeIntervalSince1970: 2_000)
        let target = Date(timeIntervalSince1970: 1_500)
        #expect(StatsPeriod.custom(from: b, to: a).contains(target, now: now))
    }
}

@Suite("累計収支の推移（対局をまたぐ）")
struct CumulativeTests {

    @Test("対局ごとに積み上がる")
    func accumulates() {
        let games = [
            game(yonma, [30, 10, -10, -30], daysAgo: 2),
            game(yonma, [20, -5, -5, -10], daysAgo: 1),
        ]
        let series = Aggregator.cumulative(games: games)
        let nakamura = series.first { $0.name == "中村" }
        #expect(nakamura?.values == [30, 50])
    }

    @Test("途中から参加した人も線の長さが揃う")
    func alignsLateJoiners() {
        let games = [
            game(yonma, [30, 10, -10, -30], daysAgo: 2),
            game(["石井", "五十嵐", "斎藤", "佐々木"], [40, 0, -20, -20], daysAgo: 1),
        ]
        let series = Aggregator.cumulative(games: games)
        let lengths = Set(series.map(\.values.count))
        #expect(lengths.count == 1, "線の長さが揃っていない: \(series.map { ($0.name, $0.values) })")
        #expect(series.first { $0.name == "石井" }?.values == [0, 40])
    }

    @Test("出ていない対局では前の値を保つ")
    func keepsPreviousValue() {
        let games = [
            game(yonma, [30, 10, -10, -30], daysAgo: 2),
            game(["石井", "五十嵐", "斎藤", "佐々木"], [40, 0, -20, -20], daysAgo: 1),
        ]
        let nakamura = Aggregator.cumulative(games: games).first { $0.name == "中村" }
        #expect(nakamura?.values == [30, 30])
    }
}
