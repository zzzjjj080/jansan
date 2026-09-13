import Foundation

/// 1人ぶんの詳しい成績。集計画面の表と、名前をタップした先の詳細で使う。
///
/// **局ごとに着順を付け直して数える。** `AggregatedStats` は表ごとの着順回数を足すだけなので、
/// 連続記録・1局の最高点・対局単位の順位・相性のような「局の並び」が要る数字は出せない。
/// 着順の付け方（同点は列の並びで先の人が上）は、表の中の集計（`Session.playerStats`）と同じ
public struct PlayerReport: Equatable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    /// 1局以上打った対局（表）の数
    public let games: Int
    /// 打った局数。お休みは含まない
    public let rounds: Int
    public let total: Int
    /// 着順ごとの回数。添字0が1位
    public let rankCounts: [Int]
    /// その局の最下位になった回数。
    /// **自分の最低着順で数えない。** それだと一度も4位を取っていない人の3位がラスになる
    public let lastCount: Int
    /// 点数がプラスだった局数
    public let plusRounds: Int
    public let bestRound: Int?
    public let worstRound: Int?
    /// 連続記録は**1回の記録（その日の表）の中だけで数える。** 次の記録に移ると途切れる
    public let longestTopStreak: Int
    public let longestLastStreak: Int
    /// ラスを引かずに続いた局数の最長
    public let longestNoLastStreak: Int
    /// その最長を出した記録の対局日。1局も無ければ nil。日付未記入の記録なら `PlayedDate.unknown`
    public let longestTopStreakDate: Date?
    public let longestLastStreakDate: Date?
    public let longestNoLastStreakDate: Date?
    /// 対局（表）の合計で1位だった回数
    public let gameTops: Int
    /// 対局（表）の合計がプラスだった回数
    public let plusGames: Int
    public let bestGame: Int?
    public let worstGame: Int?
    /// 直近の局だけの成績。調子を見る
    public let recent: RecentForm?

    public struct RecentForm: Equatable, Sendable {
        public let rounds: Int
        public let averageRank: Double
        public let total: Int
    }

    public func count(ofRank rank: Int) -> Int {
        rankCounts.indices.contains(rank - 1) ? rankCounts[rank - 1] : 0
    }

    public var averageScore: Double? { rate(total) }
    public var averageRank: Double? {
        rate(rankCounts.enumerated().reduce(0) { $0 + ($1.offset + 1) * $1.element })
    }
    public var topRate: Double? { rate(count(ofRank: 1)) }
    /// 連対率。1位か2位に入った割合
    public var rentaiRate: Double? { rate(count(ofRank: 1) + count(ofRank: 2)) }
    public var lastRate: Double? { rate(lastCount) }
    public var lastAvoidRate: Double? { lastRate.map { 1 - $0 } }
    public var plusRate: Double? { rate(plusRounds) }
    public var gameTopRate: Double? { games > 0 ? Double(gameTops) / Double(games) : nil }
    public var gamePlusRate: Double? { games > 0 ? Double(plusGames) / Double(games) : nil }

    private func rate(_ hits: Int) -> Double? {
        rounds > 0 ? Double(hits) / Double(rounds) : nil
    }
}

/// ある人から見た、1人の相手との成績
public struct Matchup: Equatable, Sendable, Identifiable {
    public var id: String { opponent }
    public let opponent: String
    /// 同じ局を打った数
    public let rounds: Int
    /// 着順で相手より上だった局数
    public let wins: Int
    /// 自分の点数 − 相手の点数 の合計
    public let difference: Int

    public var winRate: Double { rounds > 0 ? Double(wins) / Double(rounds) : 0 }
    public var averageDifference: Double { rounds > 0 ? Double(difference) / Double(rounds) : 0 }
}

public enum Report {

    /// 「最近」とみなす局数
    public static let recentRounds = 10

    /// 記録にある打ち方。四麻を先に並べる
    public static func availableStyles(games: [GameForStats]) -> [Int] {
        Array(Set(games.map(\.style))).sorted(by: >)
    }

    /// 集計に使う対局を選び、対局日の古い順に並べる
    ///
    /// - Parameters:
    ///   - style: 三麻=3・四麻=4。`nil` なら区別しない（着順の分母が混ざる）
    ///   - decimalMode: 表示モード。混ぜると10倍ズレる
    public static func select(
        games: [GameForStats],
        period: StatsPeriod = .all,
        style: Int? = nil,
        decimalMode: Bool? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [GameForStats] {
        chronological(games.filter { game in
            guard period.contains(game.playedAt, now: now, calendar: calendar) else { return false }
            if let style, game.style != style { return false }
            if let decimalMode, game.session.decimalMode != decimalMode { return false }
            return true
        })
    }

    /// 対局日の古い順。同じ日付どうしは渡された順を保つ（`sorted` は安定ソートを保証しない）
    public static func chronological(_ games: [GameForStats]) -> [GameForStats] {
        games.enumerated()
            .sorted { lhs, rhs in
                lhs.element.playedAt != rhs.element.playedAt
                    ? lhs.element.playedAt < rhs.element.playedAt
                    : lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// 全員の点が入った局。入力途中の局は数えない（表の中の集計と同じ基準）
    public static func completedRounds(of session: Session) -> [Round] {
        session.rounds.filter { $0.isComplete && !$0.playingColumns.isEmpty }
    }

    public static func roundCount(games: [GameForStats]) -> Int {
        games.reduce(0) { $0 + completedRounds(of: $1.session).count }
    }

    /// 1局の着順。点数の高い順で、同点は列の並びで先の人を上にする
    static func ranking(of round: Round) -> [(column: Int, value: Int)] {
        round.playingColumns
            .compactMap { column in round.entries[column].value.map { (column: column, value: $0) } }
            .sorted { lhs, rhs in lhs.value != rhs.value ? lhs.value > rhs.value : lhs.column < rhs.column }
    }

    /// 1人ずつの成績。並びは、選んだ対局の中で初めて出てきた順
    public static func players(games: [GameForStats]) -> [PlayerReport] {
        var order: [String] = []
        var tally: [String: Tally] = [:]

        for (gameIndex, game) in chronological(games).enumerated() {
            let players = game.session.players
            var gameTotals: [Int: Int] = [:]

            for round in completedRounds(of: game.session) {
                let ranked = ranking(of: round)
                for (index, item) in ranked.enumerated() {
                    let name = players[item.column]
                    if tally[name] == nil {
                        order.append(name)
                        tally[name] = Tally()
                    }
                    tally[name]!.addRound(rank: index + 1, seats: ranked.count, value: item.value,
                                          game: gameIndex, date: game.playedAt)
                    gameTotals[item.column, default: 0] += item.value
                }
            }

            // 対局の中の順位。同点は列の並びで先の人
            guard let top = gameTotals.min(by: { lhs, rhs in
                lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key
            })?.key else { continue }
            for (column, total) in gameTotals {
                tally[players[column]]!.addGame(total: total, isTop: column == top)
            }
        }

        return order.map { tally[$0]!.report(name: $0) }
    }

    /// その人から見た、相手ごとの成績。一緒に打った局の多い順
    public static func matchups(for name: String, games: [GameForStats]) -> [Matchup] {
        var order: [String] = []
        var rounds: [String: Int] = [:], wins: [String: Int] = [:], difference: [String: Int] = [:]

        for game in chronological(games) {
            let players = game.session.players
            for round in completedRounds(of: game.session) {
                let ranked = ranking(of: round)
                guard let me = ranked.firstIndex(where: { players[$0.column] == name }) else { continue }
                for (index, other) in ranked.enumerated() where index != me {
                    let opponent = players[other.column]
                    if rounds[opponent] == nil { order.append(opponent) }
                    rounds[opponent, default: 0] += 1
                    if me < index { wins[opponent, default: 0] += 1 }
                    difference[opponent, default: 0] += ranked[me].value - other.value
                }
            }
        }

        return order.enumerated()
            .map { index, opponent in
                (index, Matchup(opponent: opponent, rounds: rounds[opponent] ?? 0,
                                wins: wins[opponent] ?? 0, difference: difference[opponent] ?? 0))
            }
            .sorted { $0.1.rounds != $1.1.rounds ? $0.1.rounds > $1.1.rounds : $0.0 < $1.0 }
            .map(\.1)
    }
}

/// 1人ぶんを数えている途中の値
private struct Tally {
    var games = 0, rounds = 0, total = 0
    var rankCounts: [Int] = []
    var lastCount = 0, plusRounds = 0
    var best: Int?, worst: Int?
    var topStreak = 0, lastStreak = 0, noLastStreak = 0
    var longestTop = 0, longestLast = 0, longestNoLast = 0
    var topDate: Date?, lastDate: Date?, noLastDate: Date?
    /// いま数えている記録。変わったら連続記録を数え直す
    var currentGame = -1
    var gameTops = 0, plusGames = 0
    var bestGame: Int?, worstGame: Int?
    var history: [(rank: Int, value: Int)] = []

    mutating func addRound(rank: Int, seats: Int, value: Int, game: Int, date: Date) {
        // 連続記録は1回の記録の中だけ。日をまたいで「連続」とは呼ばない
        if game != currentGame {
            topStreak = 0
            lastStreak = 0
            noLastStreak = 0
            currentGame = game
        }

        rounds += 1
        total += value
        if rankCounts.count < rank {
            rankCounts += Array(repeating: 0, count: rank - rankCounts.count)
        }
        rankCounts[rank - 1] += 1

        // 1人しか打っていない局はラスと呼ばない
        let isLast = seats >= 2 && rank == seats
        if isLast { lastCount += 1 }
        if value > 0 { plusRounds += 1 }
        best = Swift.max(best ?? value, value)
        worst = Swift.min(worst ?? value, value)

        topStreak = rank == 1 ? topStreak + 1 : 0
        lastStreak = isLast ? lastStreak + 1 : 0
        noLastStreak = isLast ? 0 : noLastStreak + 1
        // 同じ長さなら先に出した方を残す
        if topStreak > longestTop { longestTop = topStreak; topDate = date }
        if lastStreak > longestLast { longestLast = lastStreak; lastDate = date }
        if noLastStreak > longestNoLast { longestNoLast = noLastStreak; noLastDate = date }

        history.append((rank: rank, value: value))
    }

    mutating func addGame(total: Int, isTop: Bool) {
        games += 1
        if isTop { gameTops += 1 }
        if total > 0 { plusGames += 1 }
        bestGame = Swift.max(bestGame ?? total, total)
        worstGame = Swift.min(worstGame ?? total, total)
    }

    func report(name: String) -> PlayerReport {
        let recentSlice = history.suffix(Report.recentRounds)
        let recent = recentSlice.isEmpty ? nil : PlayerReport.RecentForm(
            rounds: recentSlice.count,
            averageRank: Double(recentSlice.reduce(0) { $0 + $1.rank }) / Double(recentSlice.count),
            total: recentSlice.reduce(0) { $0 + $1.value }
        )
        return PlayerReport(
            name: name, games: games, rounds: rounds, total: total,
            rankCounts: rankCounts, lastCount: lastCount, plusRounds: plusRounds,
            bestRound: best, worstRound: worst,
            longestTopStreak: longestTop, longestLastStreak: longestLast,
            longestNoLastStreak: longestNoLast,
            longestTopStreakDate: topDate, longestLastStreakDate: lastDate,
            longestNoLastStreakDate: noLastDate,
            gameTops: gameTops, plusGames: plusGames, bestGame: bestGame, worstGame: worstGame,
            recent: recent
        )
    }
}
