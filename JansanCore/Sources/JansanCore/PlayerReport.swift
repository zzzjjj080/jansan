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
    /// 最高・最低の1局を出した記録の対局日。同じ点なら先に出した日
    public let bestRoundDate: Date?
    public let worstRoundDate: Date?
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
    /// 最高・最低の対局の対局日。同じ点なら先に出した日
    public let bestGameDate: Date?
    public let worstGameDate: Date?
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

/// 卓の直近の局だけで見た、1人ぶんの成績。「絶好調」に使う
public struct WindowForm: Equatable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    /// 直近の局のうち、この人が打った局数
    public let rounds: Int
    public let total: Int

    public var averageScore: Double { rounds > 0 ? Double(total) / Double(rounds) : 0 }
}

public enum Report {

    /// 「最近」とみなす局数（その人が打った局で数える。詳細の「最近の調子」）
    public static let recentRounds = 10

    /// 「絶好調」で見る局数（卓全体の直近で数える）
    public static let hotWindow = 20

    /// 集計の期間「最近20局」で見る局数。日付ではなく局で区切る（本人の指示で「最近30日」から変更）
    public static let latestRoundsPeriod = 20

    /// 選んだ対局のうち、**卓全体でいちばん新しい `rounds` 局**だけを残す。
    ///
    /// 対局日の順に新しい方から数え、境目の対局は**新しい方の局だけを残した表**にする。
    /// 入力途中の局と、1局も終わっていない対局は数えない
    public static func latest(games: [GameForStats], rounds: Int = latestRoundsPeriod) -> [GameForStats] {
        var remaining = rounds
        var kept: [GameForStats] = []
        for game in chronological(games).reversed() {
            guard remaining > 0 else { break }
            let completed = completedRounds(of: game.session)
            guard !completed.isEmpty else { continue }
            if completed.count <= remaining {
                kept.append(game)
                remaining -= completed.count
            } else {
                let s = game.session
                let trimmed = Session(players: s.players, rounds: Array(completed.suffix(remaining)),
                                      decimalMode: s.decimalMode, playersPerRound: s.playersPerRound)
                kept.append(GameForStats(playedAt: game.playedAt, session: trimmed))
                remaining = 0
            }
        }
        return kept.reversed()
    }

    /// 選んだ対局の中で、**いちばん新しい `window` 局**だけを見た成績。
    ///
    /// **その人が打った直近ではなく、卓全体の直近で切る。** その人の直近で数えると、
    /// しばらく来ていない人の昔の好成績が「今の調子」として残り続ける
    public static func recentWindow(games: [GameForStats], window: Int = hotWindow) -> [WindowForm] {
        let recent = chronological(games)
            .flatMap { game in
                completedRounds(of: game.session).map { (players: game.session.players, round: $0) }
            }
            .suffix(window)

        var order: [String] = []
        var rounds: [String: Int] = [:], totals: [String: Int] = [:]
        for item in recent {
            for column in item.round.playingColumns {
                guard let value = item.round.entries[column].value else { continue }
                let name = item.players[column]
                if rounds[name] == nil { order.append(name) }
                rounds[name, default: 0] += 1
                totals[name, default: 0] += value
            }
        }
        return order.map { WindowForm(name: $0, rounds: rounds[$0] ?? 0, total: totals[$0] ?? 0) }
    }

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
                tally[players[column]]!.addGame(total: total, isTop: column == top, date: game.playedAt)
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
    var bestDate: Date?, worstDate: Date?
    var topStreak = 0, lastStreak = 0, noLastStreak = 0
    var longestTop = 0, longestLast = 0, longestNoLast = 0
    var topDate: Date?, lastDate: Date?, noLastDate: Date?
    /// いま数えている記録。変わったら連続記録を数え直す
    var currentGame = -1
    var gameTops = 0, plusGames = 0
    var bestGame: Int?, worstGame: Int?
    var bestGameDate: Date?, worstGameDate: Date?
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
        // 同じ点なら先に出した日を残す
        if best == nil || value > best! { best = value; bestDate = date }
        if worst == nil || value < worst! { worst = value; worstDate = date }

        topStreak = rank == 1 ? topStreak + 1 : 0
        lastStreak = isLast ? lastStreak + 1 : 0
        noLastStreak = isLast ? 0 : noLastStreak + 1
        // 同じ長さなら先に出した方を残す
        if topStreak > longestTop { longestTop = topStreak; topDate = date }
        if lastStreak > longestLast { longestLast = lastStreak; lastDate = date }
        if noLastStreak > longestNoLast { longestNoLast = noLastStreak; noLastDate = date }

        history.append((rank: rank, value: value))
    }

    mutating func addGame(total: Int, isTop: Bool, date: Date) {
        games += 1
        if isTop { gameTops += 1 }
        if total > 0 { plusGames += 1 }
        if bestGame == nil || total > bestGame! { bestGame = total; bestGameDate = date }
        if worstGame == nil || total < worstGame! { worstGame = total; worstGameDate = date }
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
            bestRound: best, worstRound: worst, bestRoundDate: bestDate, worstRoundDate: worstDate,
            longestTopStreak: longestTop, longestLastStreak: longestLast,
            longestNoLastStreak: longestNoLast,
            longestTopStreakDate: topDate, longestLastStreakDate: lastDate,
            longestNoLastStreakDate: noLastDate,
            gameTops: gameTops, plusGames: plusGames, bestGame: bestGame, worstGame: worstGame,
            bestGameDate: bestGameDate, worstGameDate: worstGameDate,
            recent: recent
        )
    }
}
