import Foundation

/// 集計の対象になる1対局。
///
/// 日付を持たせているのは、期間で絞るため。保存日時ではなく**対局日**を渡すこと。
/// 後日まとめて入力すると保存日時が実際の対局日とズレる。
public struct GameForStats: Equatable, Sendable {
    public let playedAt: Date
    public let session: Session

    public init(playedAt: Date, session: Session) {
        self.playedAt = playedAt
        self.session = session
    }

    /// この対局の人数。3人局と4人局を混ぜないための鍵になる
    public var playerCount: Int { session.players.count }
}

/// 集計する期間。
public enum StatsPeriod: Equatable, Sendable {
    case all
    case thisMonth
    case lastMonth
    case last30Days
    case thisYear
    case custom(from: Date, to: Date)

    /// 判定に使う範囲。`nil` は全期間
    public func range(now: Date, calendar: Calendar = .current) -> ClosedRange<Date>? {
        switch self {
        case .all:
            return nil
        case .thisMonth:
            guard let i = calendar.dateInterval(of: .month, for: now) else { return nil }
            return i.start...i.end
        case .lastMonth:
            guard let prev = calendar.date(byAdding: .month, value: -1, to: now),
                  let i = calendar.dateInterval(of: .month, for: prev) else { return nil }
            return i.start...i.end
        case .last30Days:
            guard let from = calendar.date(byAdding: .day, value: -30, to: now) else { return nil }
            return from...now
        case .thisYear:
            guard let i = calendar.dateInterval(of: .year, for: now) else { return nil }
            return i.start...i.end
        case .custom(let from, let to):
            return from <= to ? from...to : to...from
        }
    }

    public func contains(_ date: Date, now: Date, calendar: Calendar = .current) -> Bool {
        guard let range = range(now: now, calendar: calendar) else { return true }
        return range.contains(date)
    }
}

/// 複数の対局をまたいだ1人分の成績。
///
/// 1つの表の中だけを見る `PlayerStats` と違い、**対局数**を持つ。
/// 「何半荘打ったか」と「何局打ったか」は別の数字で、どちらも見たい。
public struct AggregatedStats: Equatable, Sendable {
    public let name: String
    /// 参加した対局(表)の数
    public let games: Int
    /// 実際に打った局数。お休みは含まない
    public let played: Int
    public let total: Int
    /// 着順ごとの回数。キーは1位から
    public let rankCounts: [Int: Int]

    public init(name: String, games: Int, played: Int, total: Int, rankCounts: [Int: Int]) {
        self.name = name
        self.games = games
        self.played = played
        self.total = total
        self.rankCounts = rankCounts
    }

    public func count(ofRank rank: Int) -> Int { rankCounts[rank] ?? 0 }

    public var averageRank: Double? {
        guard played > 0 else { return nil }
        let sum = rankCounts.reduce(0) { $0 + $1.key * $1.value }
        return Double(sum) / Double(played)
    }

    /// 1局あたりの平均収支
    public var averageScore: Double? {
        guard played > 0 else { return nil }
        return Double(total) / Double(played)
    }

    public var topRate: Double? { rate(of: [1]) }
    public var lastRate: Double? { rate(of: [rankCounts.keys.max() ?? 0]) }
    /// 連対率。1位か2位に入った割合
    public var rentaiRate: Double? { rate(of: [1, 2]) }

    private func rate(of ranks: [Int]) -> Double? {
        guard played > 0 else { return nil }
        let hits = ranks.reduce(0) { $0 + count(ofRank: $1) }
        return Double(hits) / Double(played)
    }
}

public enum Aggregator {

    /// 対局をまたいで集計する。
    ///
    /// **`playerCount` を指定しないと3人局と4人局が混ざる。** 着順率の分母が
    /// 変わってしまい、数字の意味が壊れる。UIでは必ず人数を選ばせること。
    ///
    /// - Parameters:
    ///   - playerCount: この人数の対局だけを見る。`nil` なら全部（混ざる点に注意）
    ///   - decimalMode: この表示モードの記録だけを見る。`nil` なら区別しない。
    ///     モードが違う記録を混ぜると10倍ズレる
    public static func aggregate(
        games: [GameForStats],
        period: StatsPeriod = .all,
        playerCount: Int? = nil,
        decimalMode: Bool? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [AggregatedStats] {
        let targets = filter(games: games, period: period, playerCount: playerCount,
                             decimalMode: decimalMode, now: now, calendar: calendar)

        // 名前で束ねる。出てきた順を覚えておき、表示の並びを安定させる
        var order: [String] = []
        var games_ = [String: Int]()
        var played = [String: Int]()
        var totals = [String: Int]()
        var ranks = [String: [Int: Int]]()

        for game in targets {
            for stat in game.session.playerStats() {
                if order.contains(stat.name) == false { order.append(stat.name) }
                // 1局も打っていない人は「参加した」に数えない。名簿にいるだけの列を除く
                guard stat.played > 0 else { continue }
                games_[stat.name, default: 0] += 1
                played[stat.name, default: 0] += stat.played
                totals[stat.name, default: 0] += stat.total
                for (rank, count) in stat.rankCounts {
                    ranks[stat.name, default: [:]][rank, default: 0] += count
                }
            }
        }

        return order.compactMap { name in
            guard let g = games_[name], g > 0 else { return nil }
            return AggregatedStats(
                name: name,
                games: g,
                played: played[name] ?? 0,
                total: totals[name] ?? 0,
                rankCounts: ranks[name] ?? [:]
            )
        }
    }

    /// 対局をまたいだ累計収支の推移。返すのは名前ごとの折れ線。
    ///
    /// 横軸は対局の並び順（古い順）。その対局に出ていない人は前の値を引き継ぐので、
    /// 線が途切れずに読める。
    public static func cumulative(
        games: [GameForStats],
        period: StatsPeriod = .all,
        playerCount: Int? = nil,
        decimalMode: Bool? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [(name: String, values: [Int])] {
        let targets = filter(games: games, period: period, playerCount: playerCount,
                             decimalMode: decimalMode, now: now, calendar: calendar)
            .sorted { $0.playedAt < $1.playedAt }

        var order: [String] = []
        var running = [String: Int]()
        var series = [String: [Int]]()

        for game in targets {
            for stat in game.session.playerStats() where stat.played > 0 {
                if order.contains(stat.name) == false {
                    order.append(stat.name)
                    // 途中から現れた人は、それまでを0で埋めて長さを揃える
                    series[stat.name] = Array(repeating: 0, count: series.values.first?.count ?? 0)
                    running[stat.name] = 0
                }
                running[stat.name, default: 0] += stat.total
            }
            for name in order {
                series[name, default: []].append(running[name] ?? 0)
            }
        }

        return order.map { (name: $0, values: series[$0] ?? []) }
    }

    /// 集計に使う対局を選ぶ。UIの「該当◯件」もこれで数える
    public static func filter(
        games: [GameForStats],
        period: StatsPeriod = .all,
        playerCount: Int? = nil,
        decimalMode: Bool? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [GameForStats] {
        games.filter { game in
            guard period.contains(game.playedAt, now: now, calendar: calendar) else { return false }
            if let playerCount, game.playerCount != playerCount { return false }
            if let decimalMode, game.session.decimalMode != decimalMode { return false }
            return true
        }
    }

    /// 記録に含まれる人数の種類。UIの「3人打ち / 4人打ち」の選択肢に使う
    public static func availablePlayerCounts(games: [GameForStats]) -> [Int] {
        Array(Set(games.map(\.playerCount))).sorted()
    }
}
