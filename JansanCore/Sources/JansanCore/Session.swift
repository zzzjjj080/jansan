import Foundation

/// 表の中の1マスの位置。
public struct Position: Equatable, Hashable, Sendable, Codable {
    public var round: Int
    public var column: Int

    public init(round: Int, column: Int) {
        self.round = round
        self.column = column
    }
}

/// 1回の対局セッション(＝表そのもの)。
public struct Session: Equatable, Sendable, Codable {
    /// 表の列。参加中のメンバー名だけが並ぶ
    public private(set) var players: [String]
    public private(set) var rounds: [Round]
    /// ONにすると点数の末尾1桁を小数として表示する(例: 323 → 32.3)。
    /// 保持する値は常に整数で、表示のときだけ解釈を変える
    public var decimalMode: Bool

    public init(players: [String], decimalMode: Bool = false) {
        self.players = players
        self.rounds = [Round(playerCount: players.count)]
        self.decimalMode = decimalMode
    }

    // MARK: - 合計

    /// 実際に打った局数。最後にぶら下がっている入力待ちの空行は数えない
    public var playedRoundCount: Int {
        rounds.filter { round in
            round.entries.contains { $0.value != nil || $0.isResting }
        }.count
    }

    public var totals: [Int] {
        players.indices.map { column in
            rounds.reduce(0) { $0 + (($1.entries[column].value) ?? 0) }
        }
    }

    // MARK: - 入力

    /// 点数を確定する。自動計算と行の追加もここで済ませる
    public mutating func enter(_ value: Int, at position: Position) {
        rounds[position.round].entries[position.column] = .entered(value)
        rounds[position.round].recompute()
        appendRoundIfNeeded()
    }

    /// 「お休み」の手動切り替え。5〜6人打ちの自動お休みとは別に、上書き用として残してある
    public mutating func toggleResting(at position: Position) {
        let entry = rounds[position.round].entries[position.column]
        rounds[position.round].entries[position.column] = entry.isResting ? .empty : .resting
        rounds[position.round].recompute()
        appendRoundIfNeeded()
    }

    /// 最終局が埋まったら次の空行を用意する。「＋」ボタンを無くすための仕組み
    public mutating func appendRoundIfNeeded() {
        guard let last = rounds.last, last.isComplete else { return }
        rounds.append(Round(playerCount: players.count))
    }

    // MARK: - 5〜6人打ちの「4人目を指定」

    /// 3人分入力済みで、まだ誰が4人目か決まっていない状態か。
    /// ちょうど4人の局(通常の四人打ち)では常にfalseになり、タップを待たず自動で次のマスへ進む
    public func needsWinnerDesignation(at roundIndex: Int) -> Bool {
        let round = rounds[roundIndex]
        let playing = round.playingColumns
        return playing.count > 4 && playing.filter { round.entries[$0].isEntered }.count == 3
    }

    /// そのマスをタップして「実際に打った4人目」に指定できるか
    public func canDesignateWinner(at position: Position) -> Bool {
        rounds[position.round].entries[position.column].isOpen
            && needsWinnerDesignation(at: position.round)
    }

    /// 実際に打った4人目として確定し、残りの未入力メンバーはその局だけお休みにする。
    /// 点数は3人分から逆算されるので、数字の入力は要らない
    public mutating func designateWinner(at position: Position) {
        for column in rounds[position.round].entries.indices where column != position.column {
            if rounds[position.round].entries[column].isOpen {
                rounds[position.round].entries[column] = .resting
            }
        }
        rounds[position.round].recompute()
        appendRoundIfNeeded()
    }

    // MARK: - カーソルの自動移動

    /// 右隣を優先し、無ければ左側、それも無ければ次の局の先頭から探す
    public func nextOpenPosition(after position: Position) -> Position? {
        let round = rounds[position.round]

        if let column = ((position.column + 1)..<round.entries.count).first(where: { round.entries[$0].isOpen }) {
            return Position(round: position.round, column: column)
        }
        if let column = stride(from: position.column - 1, through: 0, by: -1).first(where: { round.entries[$0].isOpen }) {
            return Position(round: position.round, column: column)
        }
        let nextIndex = position.round + 1
        if rounds.indices.contains(nextIndex),
           let column = rounds[nextIndex].entries.indices.first(where: { rounds[nextIndex].entries[$0].isOpen }) {
            return Position(round: nextIndex, column: column)
        }
        return nil
    }

    // MARK: - 参加メンバーの変更

    /// 参加者が変わっても、名前をキーに既存の入力を引き継いで列を組み直す
    public mutating func setPlayers(_ newPlayers: [String]) {
        rounds = rounds.map { round in
            var rebuilt = Round(playerCount: newPlayers.count)
            for (newColumn, name) in newPlayers.enumerated() {
                if let oldColumn = players.firstIndex(of: name) {
                    rebuilt.entries[newColumn] = round.entries[oldColumn]
                }
            }
            rebuilt.recompute()
            return rebuilt
        }
        players = newPlayers
        appendRoundIfNeeded()
    }

    /// 打っていない局を消す。1局しか無い場合は行ごと消さず中身だけ空にする
    public mutating func removeRound(at index: Int) {
        guard rounds.indices.contains(index) else { return }
        if rounds.count == 1 {
            rounds[0] = Round(playerCount: players.count)
            return
        }
        rounds.remove(at: index)
        appendRoundIfNeeded()
    }

    /// 全リセット(新規セッション)
    public mutating func reset() {
        rounds = [Round(playerCount: players.count)]
    }
}
