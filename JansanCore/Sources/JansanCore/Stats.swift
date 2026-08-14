import Foundation

/// ビューモードで出す1人分の成績。
public struct PlayerStats: Equatable, Sendable {
    public let name: String
    /// お休みを除いて実際に打った局数
    public let played: Int
    /// 着順ごとの回数。キーは1位から
    public let rankCounts: [Int: Int]
    public let averageRank: Double?
    public let total: Int

    public func count(ofRank rank: Int) -> Int { rankCounts[rank] ?? 0 }
}

extension Session {
    /// 全員確定した局だけを対象に着順を集計する。入力途中の局は数えない
    public func playerStats() -> [PlayerStats] {
        let completed = rounds.filter { $0.isComplete && !$0.playingColumns.isEmpty }
        var played = Array(repeating: 0, count: players.count)
        var rankSum = Array(repeating: 0, count: players.count)
        var rankCounts = Array(repeating: [Int: Int](), count: players.count)

        for round in completed {
            // 点数の高い順に1位から。同点は列の並び順で先に来た方が上位になる
            // Swiftのsortedは安定ソートが保証されないので、同点の順序は明示的に決める
            let ranking = round.playingColumns
                .compactMap { column in round.entries[column].value.map { (column: column, value: $0) } }
                .enumerated()
                .sorted { lhs, rhs in
                    lhs.element.value != rhs.element.value
                        ? lhs.element.value > rhs.element.value
                        : lhs.offset < rhs.offset
                }
                .map(\.element)

            for (index, item) in ranking.enumerated() {
                let rank = index + 1
                played[item.column] += 1
                rankSum[item.column] += rank
                rankCounts[item.column][rank, default: 0] += 1
            }
        }

        let totals = self.totals
        return players.enumerated().map { column, name in
            PlayerStats(
                name: name,
                played: played[column],
                rankCounts: rankCounts[column],
                averageRank: played[column] > 0 ? Double(rankSum[column]) / Double(played[column]) : nil,
                total: totals[column]
            )
        }
    }

    /// 推移グラフ用の累計点数。入力のある局まで
    public func cumulativeTotals() -> [[Int]] {
        let dataRounds = rounds.filter { round in round.entries.contains { $0.value != nil } }
        return players.indices.map { column in
            var running = 0
            return dataRounds.map { round in
                running += round.entries[column].value ?? 0
                return running
            }
        }
    }
}
