import Foundation

/// 1局分の行。
public struct Round: Equatable, Sendable, Codable {
    public var entries: [Entry]

    public init(playerCount: Int) {
        self.entries = Array(repeating: .empty, count: playerCount)
    }

    public init(entries: [Entry]) {
        self.entries = entries
    }

    /// お休みを除いた参加者の列番号
    public var playingColumns: [Int] {
        entries.indices.filter { !entries[$0].isResting }
    }

    /// 手入力済みの列番号
    public var enteredColumns: [Int] {
        entries.indices.filter { entries[$0].isEntered }
    }

    /// お休みを除く全員に点数が入っている
    public var isComplete: Bool {
        playingColumns.allSatisfy { entries[$0].value != nil }
    }

    /// 残り1マスになったら、その局の合計が0になるよう逆算して埋める。
    ///
    /// 2〜3着を後から訂正した時もここを通るので、トップの点数が自動的に付け直される。
    /// 逆に残りが2マス以上に戻った場合は、前回の逆算結果を消して入力待ちに戻す。
    public mutating func recompute() {
        let playing = playingColumns
        let entered = playing.filter { entries[$0].isEntered }
        let open = playing.filter { !entries[$0].isEntered }

        guard playing.count >= 2, open.count == 1 else {
            for column in open { entries[column] = .empty }
            return
        }
        let sum = entered.reduce(0) { $0 + (entries[$1].value ?? 0) }
        entries[open[0]] = .derived(-sum)
    }

    /// 全員確定した局のトップ/ラスの列。全員同点なら色分けしないのでnilを返す。
    public var topAndLastColumns: (top: [Int], last: [Int])? {
        let playing = playingColumns
        guard !playing.isEmpty, isComplete else { return nil }
        let values = playing.compactMap { entries[$0].value }
        guard let maxValue = values.max(), let minValue = values.min(), maxValue != minValue else { return nil }
        return (
            top: playing.filter { entries[$0].value == maxValue },
            last: playing.filter { entries[$0].value == minValue }
        )
    }
}
