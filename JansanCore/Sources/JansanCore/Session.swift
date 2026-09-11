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

    /// **1局を何人で打つか。** 三麻なら3、四麻なら4。
    ///
    /// 参加人数（`players.count`）とは別物。5人が集まって四麻を回すこともあれば、
    /// 4人が集まって三麻を回す（毎局ひとり抜ける）こともある。
    /// 以前はここが4に決め打ちで、参加人数がちょうど3のときしか三麻にならなかった。
    public var playersPerRound: Int = Session.defaultPlayersPerRound

    public static let defaultPlayersPerRound = 4
    /// 選べる打ち方。3人未満では点数の逆算が成り立たない
    public static let playersPerRoundChoices = [3, 4]

    public init(players: [String], decimalMode: Bool = false,
                playersPerRound: Int = Session.defaultPlayersPerRound) {
        self.players = players
        self.rounds = [Round(playerCount: players.count)]
        self.decimalMode = decimalMode
        self.playersPerRound = playersPerRound
    }

    // MARK: - 保存との互換

    private enum CodingKeys: String, CodingKey {
        case players, rounds, decimalMode, playersPerRound
    }

    /// **前の版で保存した表には playersPerRound が無い。**
    /// 合成された init(from:) のままだと、そこで復号が失敗して記録が丸ごと読めなくなる
    /// （引き継ぎ書 4-77）。無ければ四麻として読む
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        players = try c.decode([String].self, forKey: .players)
        rounds = try c.decode([Round].self, forKey: .rounds)
        decimalMode = try c.decode(Bool.self, forKey: .decimalMode)
        playersPerRound = try c.decodeIfPresent(Int.self, forKey: .playersPerRound)
            ?? Session.defaultPlayersPerRound
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

    /// 打ち方（三麻／四麻）を変える。
    ///
    /// **入力済みの局には触らない。** 打ち終わった局の着順を後から書き換えると、
    /// 集計の意味が変わってしまう（過去のデータを後から書き換えない）。
    /// 変わるのは、これから入力する局の「あと1人」の求め方だけ。
    ///
    /// ただし**入力がまったく無い局のお休み印は外す。** 四麻で自動的にお休みに
    /// なっていた人が、三麻に変えたあとも打てないままになるのを防ぐ
    public mutating func setPlayersPerRound(_ count: Int) {
        let target = max(2, min(count, players.count))
        guard target != playersPerRound else { return }
        playersPerRound = target

        for index in rounds.indices {
            let hasInput = rounds[index].entries.contains { $0.value != nil }
            guard !hasInput else { continue }
            for column in rounds[index].entries.indices where rounds[index].entries[column].isResting {
                rounds[index].entries[column] = .empty
            }
        }
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

    /// あと1人ぶんで埋まるのに、その1人が誰か決まっていない状態か。
    ///
    /// 参加人数が打つ人数ちょうどなら常に false になり、タップを待たず自動で次のマスへ進む。
    /// 参加人数の方が多いときだけ、実際に打った最後のひとりをタップで指してもらう。
    public func needsWinnerDesignation(at roundIndex: Int) -> Bool {
        let round = rounds[roundIndex]
        let playing = round.playingColumns
        return playing.count > playersPerRound
            && playing.filter { round.entries[$0].isEntered }.count == playersPerRound - 1
    }

    /// そのマスをタップして「実際に打った4人目」に指定できるか
    public func canDesignateWinner(at position: Position) -> Bool {
        rounds[position.round].entries[position.column].isOpen
            && needsWinnerDesignation(at: position.round)
    }

    /// 実際に打った最後のひとりとして確定し、残りの未入力メンバーはその局だけお休みにする。
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

    /// 列の中身はそのままに、見出しの名前だけ差し替える。
    ///
    /// setPlayers は名前で対応付けるため、改名に使うと別人が現れたと解釈されて
    /// その列の点数が丸ごと消える。名前を変えるだけの操作には必ずこちらを使う。
    public mutating func renamePlayer(at column: Int, to newName: String) {
        guard players.indices.contains(column) else { return }
        players[column] = newName
    }

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

    /// 指定した1マスだけを空に戻す。
    ///
    /// ここでは意図的に再計算しない。消した直後に逆算が走ると、
    /// 消したはずのマスが即座に埋め直されたり、逆算で入っていた別のマスが
    /// 巻き添えで消えたりして、「どれを消したのか」が分からなくなるため。
    /// 計算し直しは recomputeRound(at:) を呼ぶ側のタイミングに任せる。
    public mutating func clear(at position: Position) {
        guard rounds.indices.contains(position.round),
              rounds[position.round].entries.indices.contains(position.column) else { return }
        rounds[position.round].entries[position.column] = .empty
    }

    /// その局を計算し直す。マスを選び直したときに呼ぶ
    public mutating func recomputeRound(at index: Int) {
        guard rounds.indices.contains(index) else { return }
        rounds[index].recompute()
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
