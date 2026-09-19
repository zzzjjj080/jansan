import Foundation

/// 対局日が分からない記録の印。
///
/// **SavedGame に新しい属性を足さずに表す。** CloudKit と同期するモデルに属性を足すと、
/// 本番のスキーマを CloudKit Console で配備し直すまで、その値が同期されない（本人の手作業になる）。
/// すでにある `playedAt` に、実際の対局日とは重ならない日付を入れて見分ける
public enum PlayedDate {
    /// 1970-01-01 00:00 UTC。バックアップ（ISO 8601）や CloudKit を通っても秒単位で崩れない
    public static let unknown = Date(timeIntervalSince1970: 0)

    public static func isUnknown(_ date: Date?) -> Bool {
        guard let date else { return false }
        return abs(date.timeIntervalSince1970) < 1
    }

    /// 記録の一覧の並び。**対局日の新しい順。日付未記入は最後。**
    ///
    /// 対局日が無い古い記録（`nil`）は保存日時を対局日とみなす。
    /// 対局日が同じなら保存の新しい順、日付未記入どうしも保存の新しい順
    public static func newestFirst(played lhsPlayed: Date?, saved lhsSaved: Date,
                                   before rhsPlayed: Date?, saved rhsSaved: Date) -> Bool {
        let lhsUnknown = isUnknown(lhsPlayed), rhsUnknown = isUnknown(rhsPlayed)
        if lhsUnknown != rhsUnknown { return rhsUnknown }
        let lhsDate = lhsUnknown ? lhsSaved : (lhsPlayed ?? lhsSaved)
        let rhsDate = rhsUnknown ? rhsSaved : (rhsPlayed ?? rhsSaved)
        return lhsDate != rhsDate ? lhsDate > rhsDate : lhsSaved > rhsSaved
    }
}

/// CSV から読み取った1つの表
public struct CSVImportedGame: Equatable, Sendable {
    public var session: Session
    /// 合計が0にならない局。CSV に番号があればその番号、無ければ上から数えた番号
    public var unbalancedRounds: [Int]
    /// 打つ人数より点数が少ない局。途中で終わった局など
    public var shortRounds: [Int]
    /// 「合計」の行があり、局から計算し直した合計と合わない
    public var totalMismatch: Bool

    public var snapshot: GameSnapshot {
        GameSnapshot(roster: Roster(names: session.players, activeCount: session.players.count),
                     session: session, autoConfirm: true)
    }

    /// 同じ表を二度入れないための鍵
    public var fingerprint: String { CSVImport.fingerprint(of: session) }
}

public enum CSVImportError: Error, Equatable {
    /// 何も貼られていない
    case empty
    /// バックアップ（JSON）が貼られた。入口が別
    case looksLikeBackup
    /// 名前の行より先に点数が来た
    case scoresBeforeNames(line: Int)
    case playerCount(line: Int, count: Int)
    case emptyName(line: Int)
    case duplicateName(line: Int, name: String)
    case notANumber(line: Int, cell: String)
    /// 名前の数より点数の欄が多い
    case tooManyScores(line: Int)
    /// 名前の行はあるが、点数の行が1つも無い
    case noRounds(line: Int)
}

/// 書き出し（CSV）を貼り戻す。
///
/// **書き出しの形をそのまま読めることが第一。** そのうえで、表計算ソフトから
/// コピーしたもの（タブ区切り）や、手で打った全角の数字・「▲」も受ける。
/// CSV には日付が無いので、日付は呼び出し側で「未記入」にする
public enum CSVImport {

    /// 入力画面で扱える人数と同じ
    public static let playerRange = 3...Roster.maxActive

    public static func parse(_ text: String) throws -> [CSVImportedGame] {
        let normalized = text
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let body = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { throw CSVImportError.empty }
        guard !body.hasPrefix("{") else { throw CSVImportError.looksLikeBackup }

        var games: [CSVImportedGame] = []
        var pending: PendingTable?
        var lastHeaderLine = 1

        for (offset, raw) in normalized.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = offset + 1
            let cells = splitCells(String(raw))
            guard cells.contains(where: { !$0.isEmpty }) else { continue }

            if isTotalLabel(cells[0]) {
                pending?.totalCells = Array(cells.dropFirst())
                continue
            }
            // 写真からの読み取りでは「合計」が「合卵9」のように化け、隣の数字とくっつくことがある。
            // 点数の行がすでにあり、残りが全部数字なら合計の行とみなして飛ばす（合計は数え直せる）
            if isGarbledTotalRow(cells, hasRows: pending?.rows.isEmpty == false) {
                continue
            }

            if cells.contains(where: { number($0) != nil }) {
                guard pending != nil else { throw CSVImportError.scoresBeforeNames(line: line) }
                try pending!.addRow(cells, line: line)
            } else {
                // 名前の行。前の表に点数があれば1件として閉じる。
                // 点数が1行も無ければ題名などとみなして捨てる（題名は要らないが、あっても困らない）
                if let table = pending, !table.rows.isEmpty {
                    games.append(try table.finish())
                }
                pending = PendingTable(header: cells, headerLine: line)
                lastHeaderLine = line
            }
        }

        if let table = pending, !table.rows.isEmpty {
            games.append(try table.finish())
        }
        guard !games.isEmpty else { throw CSVImportError.noRounds(line: lastHeaderLine) }
        return games
    }

    // MARK: - AI に変換してもらうためのお願い文

    /// お願い文に載せる例。**取り込めることをテストで確かめている。**
    /// 例が読めない形だと、AI がその通りに出してきたものも読めない
    public static let aiPromptExample = """
    No,中村,五十嵐,斎藤,佐々木,田中
    1,30,10,-10,-30,
    2,-20,40,,-20,0
    合計,10,50,-10,-50,0
    """

    /// 写真や他のアプリの画面と一緒に、ChatGPT や Claude などへ送ってもらう文
    public static let aiPrompt = """
    添付した麻雀の成績（写真・スクリーンショット・文章）を、下の形式のCSVに書き換えてください。

    形式
    ・1行目は「No,名前,名前,…」。参加した全員の名前を並べる（3〜6人）
    ・2行目からは1行が1局。「局の番号,点数,点数,…」
    ・点数はその局の収支（+30、-10 など）。持ち点（25000 など）しか無いときは、そのまま書き写す
    ・その局を打っていない人（抜け番）は空欄にする
    ・小数はそのまま書く（例: 32.3）
    ・最後に「合計,…」の行を付ける
    ・対局が複数あるときは、空行を1行はさんで続ける
    ・日付・説明・記号（```など）は付けず、CSVだけを出力する
    ・読み取れない数字があれば、CSVの後に「読めなかった所」として書く

    例
    \(aiPromptExample)
    """

    /// 書き出しと同じ形にしたもの。表の中身が同じなら同じ文字列になる
    public static func fingerprint(of session: Session) -> String {
        session.csv()
    }

    /// それぞれが「すでにある」かどうか。貼り付けの中で重なっている分も飛ばす
    public static func duplicates(_ games: [CSVImportedGame], existing: Set<String>) -> [Bool] {
        var seen = existing
        return games.map { !seen.insert($0.fingerprint).inserted }
    }

    // MARK: - 1行・1マスの読み取り

    /// 見出しの1列目がこれなら、各行の1列目は局の番号
    static let indexLabels: Set<String> = ["", "no", "no.", "#", "局", "番号"]

    static func isTotalLabel(_ cell: String) -> Bool {
        ["合計", "計", "total"].contains(cell.lowercased())
    }

    /// 読み取りで崩れた合計の行か。**名前の行を巻き添えにしない**ように、
    /// 「点数の行がすでにある」「残りが全部数字」の両方がそろったときだけ合計とみなす
    static func isGarbledTotalRow(_ cells: [String], hasRows: Bool) -> Bool {
        guard hasRows, let first = cells.first, number(first) == nil else { return false }
        let lower = first.lowercased()
        let looksLikeTotal = first.hasPrefix("合") || first.hasPrefix("計")
            || lower.hasPrefix("total") || lower.hasPrefix("sum")
        guard looksLikeTotal else { return false }
        let rest = cells.dropFirst().filter { !$0.isEmpty }
        return !rest.isEmpty && rest.allSatisfy { number($0) != nil }
    }

    /// タブがあればタブで、無ければカンマで区切る。表計算ソフトからのコピーはタブになる
    static func splitCells(_ line: String) -> [String] {
        let parts: [Substring] = line.contains("\t")
            ? line.split(separator: "\t", omittingEmptySubsequences: false)
            : line.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "," || $0 == "，" })
        return parts.map { part in
            var cell = part.trimmingCharacters(in: .whitespaces)
            if cell.count >= 2, cell.hasPrefix("\""), cell.hasSuffix("\"") {
                cell = String(cell.dropFirst().dropLast())
            }
            return cell
        }
    }

    /// 1マスを数として読む。全角の数字・「＋」「－」「▲」（マイナスの印）も受ける
    static func number(_ cell: String) -> Double? {
        var text = ""
        for scalar in cell.unicodeScalars {
            switch scalar.value {
            case 0xFF10...0xFF19:
                text.unicodeScalars.append(Unicode.Scalar(scalar.value - 0xFEE0)!)
            case 0xFF0D, 0x2212, 0x25B2:   // －  −  ▲
                text.append("-")
            case 0xFF0B:
                text.append("+")
            case 0xFF0E:
                text.append(".")
            case 0x20, 0x3000:
                continue
            default:
                text.unicodeScalars.append(scalar)
            }
        }
        var digits = Substring(text)
        if let first = digits.first, first == "+" || first == "-" { digits = digits.dropFirst() }
        let parts = digits.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } })
        else { return nil }
        return Double(text)
    }

    /// 保持する点数は整数。小数点モードでは末尾1桁が小数（32.3 → 323）
    static func points(_ value: Double, decimalMode: Bool) -> Int {
        decimalMode ? Int((value * 10).rounded()) : Int(value.rounded())
    }
}

/// 読み取り途中の表
private struct PendingTable {
    struct Row {
        let line: Int
        let label: Int?
        /// 名前の数に揃えた点数の欄
        let cells: [String]
    }

    let headerLine: Int
    var hasIndex: Bool
    let players: [String]
    var rows: [Row] = []
    var totalCells: [String]?

    init(header: [String], headerLine: Int) {
        self.headerLine = headerLine
        hasIndex = CSVImport.indexLabels.contains((header.first ?? "").lowercased())
        var names = hasIndex ? Array(header.dropFirst()) : header
        while names.last?.isEmpty == true { names.removeLast() }
        players = names
    }

    mutating func addRow(_ cells: [String], line: Int) throws {
        if rows.isEmpty {
            try validatePlayers()
            // 見出しに「No」が無くても、点数の行が名前より1列多ければ1列目は番号
            if !hasIndex, Self.usedCount(cells) == players.count + 1 { hasIndex = true }
        }

        let values = hasIndex ? Array(cells.dropFirst()) : cells
        if values.count > players.count, values[players.count...].contains(where: { !$0.isEmpty }) {
            throw CSVImportError.tooManyScores(line: line)
        }
        for cell in values.prefix(players.count) where !cell.isEmpty && CSVImport.number(cell) == nil {
            throw CSVImportError.notANumber(line: line, cell: cell)
        }
        let padded = Array((values + Array(repeating: "", count: max(0, players.count - values.count)))
            .prefix(players.count))
        let label = hasIndex ? cells.first.flatMap { Int($0) } : nil
        rows.append(Row(line: line, label: label, cells: padded))
    }

    private func validatePlayers() throws {
        guard CSVImport.playerRange.contains(players.count) else {
            throw CSVImportError.playerCount(line: headerLine, count: players.count)
        }
        if players.contains(where: \.isEmpty) { throw CSVImportError.emptyName(line: headerLine) }
        var seen = Set<String>()
        for name in players where !seen.insert(name).inserted {
            throw CSVImportError.duplicateName(line: headerLine, name: name)
        }
    }

    /// 末尾の空欄を除いた列数。書き出しはお休みの人が最後だと「,」で終わる
    private static func usedCount(_ cells: [String]) -> Int {
        var count = cells.count
        while count > 0, cells[count - 1].isEmpty { count -= 1 }
        return count
    }

    func finish() throws -> CSVImportedGame {
        // 1マスでも小数点があれば小数点モードの表。整数の欄は「.0」とみなす
        let decimalMode = (rows.flatMap(\.cells) + (totalCells ?? [])).contains { cell in
            CSVImport.number(cell) != nil && (cell.contains(".") || cell.contains("．"))
        }
        func convert(_ cell: String) -> Int? {
            CSVImport.number(cell).map { CSVImport.points($0, decimalMode: decimalMode) }
        }

        var rounds: [Round] = []
        var labels: [Int] = []
        for row in rows {
            // 空欄はお休み。書き出しがお休みを空欄にしているのと対になる
            let entries = row.cells.map { cell in convert(cell).map(Entry.entered) ?? .resting }
            guard entries.contains(where: { !$0.isResting }) else { continue }
            rounds.append(Round(entries: entries))
            labels.append(row.label ?? rounds.count)
        }
        guard !rounds.isEmpty else { throw CSVImportError.noRounds(line: headerLine) }

        // 三麻か四麻か。参加が3人か、どの局も3人しか点数が無ければ三麻
        let mostPlaying = rounds.map { $0.playingColumns.count }.max() ?? 4
        let perRound = (players.count <= 3 || mostPlaying <= 3) ? 3 : 4

        let session = Session(players: players, rounds: rounds,
                              decimalMode: decimalMode, playersPerRound: perRound)

        let unbalanced = zip(rounds, labels).filter { $0.0.isUnbalanced }.map(\.1)
        let short = zip(rounds, labels).filter { $0.0.playingColumns.count < perRound }.map(\.1)

        var mismatch = false
        if let totalCells {
            let given = totalCells.prefix(players.count).map(convert)
            mismatch = given.count != players.count || zip(given, session.totals).contains { $0.0 != $0.1 }
        }

        return CSVImportedGame(session: session, unbalancedRounds: unbalanced,
                               shortRounds: short, totalMismatch: mismatch)
    }
}
