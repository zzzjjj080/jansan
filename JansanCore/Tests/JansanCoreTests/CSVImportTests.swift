import Testing
import Foundation
@testable import JansanCore

// 書き出し（CSV）をそのまま貼って戻せることが要。書き出しの形を変えたら、ここが落ちて気づける

private let yonma = ["中村", "五十嵐", "斎藤", "佐々木"]

private func played(decimalMode: Bool = false) -> Session {
    var session = Session(players: yonma, decimalMode: decimalMode)
    session.enter(-32, at: Position(round: 0, column: 0))
    session.enter(71, at: Position(round: 0, column: 1))
    session.enter(-50, at: Position(round: 0, column: 2))
    session.enter(120, at: Position(round: 1, column: 3))
    session.enter(-40, at: Position(round: 1, column: 2))
    session.enter(-30, at: Position(round: 1, column: 1))
    return session
}

@Suite("CSVの取り込み・書き出しとの往復")
struct CSVImportRoundTripTests {

    @Test("書き出したCSVを貼ると、同じ表に戻る")
    func roundTrip() throws {
        let original = played()
        let games = try CSVImport.parse(original.csv())

        #expect(games.count == 1)
        let session = games[0].session
        #expect(session.players == yonma)
        #expect(session.totals == original.totals)
        #expect(session.csv() == original.csv())
        #expect(session.decimalMode == false)
        #expect(session.playersPerRound == 4)
        #expect(games[0].unbalancedRounds.isEmpty)
        #expect(games[0].shortRounds.isEmpty)
        #expect(games[0].totalMismatch == false)
        // 入力に読み込んだとき続きが打てるよう、最後に空行がある
        #expect(session.rounds.count == 3)
        #expect(games[0].snapshot.roster.activeNames == yonma)
    }

    @Test("小数点モードの表は小数点モードのまま戻る。10倍にならない")
    func decimalRoundTrip() throws {
        let original = played(decimalMode: true)
        let session = try CSVImport.parse(original.csv())[0].session
        #expect(session.decimalMode)
        #expect(session.totals == original.totals)
        #expect(session.csv() == original.csv())
    }

    @Test("5人で四麻。空欄はお休みとして戻る")
    func fivePlayersResting() throws {
        var original = Session(players: yonma + ["田中"])
        original.toggleResting(at: Position(round: 0, column: 4))
        original.enter(30, at: Position(round: 0, column: 0))
        original.enter(10, at: Position(round: 0, column: 1))
        original.enter(-15, at: Position(round: 0, column: 2))

        let game = try CSVImport.parse(original.csv())[0]
        #expect(game.session.playersPerRound == 4)
        #expect(game.session.rounds[0].entries[4] == .resting)
        #expect(game.session.totals == original.totals)
        #expect(game.shortRounds.isEmpty)
    }

    @Test("4人で三麻。どの局も3人ぶんなら三麻として戻る")
    func fourPlayersSanma() throws {
        var original = Session(players: yonma, playersPerRound: 3)
        original.toggleResting(at: Position(round: 0, column: 3))
        original.enter(30, at: Position(round: 0, column: 0))
        original.enter(-10, at: Position(round: 0, column: 1))

        let session = try CSVImport.parse(original.csv())[0].session
        #expect(session.playersPerRound == 3)
        #expect(session.totals == original.totals)
    }

    @Test("3人の表は三麻")
    func threePlayers() throws {
        let session = try CSVImport.parse("No,A,B,C\n1,30,-10,-20")[0].session
        #expect(session.playersPerRound == 3)
    }

    @Test("複数の表をまとめて貼ると、表ごとに1件になる")
    func multipleTables() throws {
        var other = Session(players: ["A", "B", "C"])
        other.enter(10, at: Position(round: 0, column: 0))
        other.enter(5, at: Position(round: 0, column: 1))

        let games = try CSVImport.parse(played().csv() + "\n\n" + other.csv())
        #expect(games.count == 2)
        #expect(games[1].session.players == ["A", "B", "C"])
        #expect(games[1].session.totals == [10, 5, -15])
    }
}

@Suite("CSVの取り込み・書き出し以外の形")
struct CSVImportLenientTests {

    @Test("表計算ソフトからのコピー（タブ区切り・番号なし・合計なし）")
    func spreadsheetPaste() throws {
        let session = try CSVImport.parse("中村\t五十嵐\t斎藤\t佐々木\n30\t10\t-10\t-30\n")[0].session
        #expect(session.players == yonma)
        #expect(session.totals == [30, 10, -10, -30])
    }

    @Test("見出しに No が無くても、行が1列多ければ1列目は番号")
    func indexWithoutHeaderLabel() throws {
        let session = try CSVImport.parse("A,B,C,D\n1,30,10,-10,-30")[0].session
        #expect(session.totals == [30, 10, -10, -30])
    }

    @Test("全角の数字・＋・－・▲ を読む")
    func fullWidthAndTriangle() throws {
        let session = try CSVImport.parse("No,A,B,C\n1,＋３０,▲１０,－２０")[0].session
        #expect(session.totals == [30, -10, -20])
    }

    @Test("題名の行があっても読み飛ばす")
    func titleLineIsIgnored() throws {
        let games = try CSVImport.parse("田中宅 9/12\nNo,A,B,C,D\n1,30,10,-10,-30")
        #expect(games.count == 1)
        #expect(games[0].session.players == ["A", "B", "C", "D"])
    }

    @Test("Windows の改行と BOM が付いていても読む")
    func crlfAndBOM() throws {
        let games = try CSVImport.parse("\u{FEFF}No,A,B,C\r\n1,1,2,-3\r\n")
        #expect(games[0].session.totals == [1, 2, -3])
    }

    @Test("合計が0にならない局と、合計行の食い違いを知らせる")
    func warnings() throws {
        let game = try CSVImport.parse("No,A,B,C,D\n1,30,10,-10,-20\n合計,30,10,-10,-30")[0]
        #expect(game.unbalancedRounds == [1])
        #expect(game.totalMismatch)
    }

    @Test("四麻で3人ぶんしか無い局を知らせる")
    func shortRound() throws {
        let game = try CSVImport.parse("No,A,B,C,D\n1,30,10,-10,-30\n2,20,-10,-10,")[0]
        #expect(game.session.playersPerRound == 4)
        #expect(game.shortRounds == [2])
    }
}

@Suite("CSVの取り込み・AIへのお願い文")
struct CSVImportPromptTests {

    @Test("お願い文に載せた例は、そのまま取り込める")
    func exampleParses() throws {
        let games = try CSVImport.parse(CSVImport.aiPromptExample)
        #expect(games.count == 1)
        #expect(games[0].session.players == ["中村", "五十嵐", "斎藤", "佐々木", "田中"])
        #expect(games[0].session.playersPerRound == 4)
        #expect(games[0].unbalancedRounds.isEmpty)
        #expect(games[0].shortRounds.isEmpty)
        #expect(games[0].totalMismatch == false)
    }

    @Test("お願い文に例が入っている")
    func promptContainsExample() {
        #expect(CSVImport.aiPrompt.contains(CSVImport.aiPromptExample))
    }
}

@Suite("CSVの取り込み・断るもの")
struct CSVImportErrorTests {

    @Test("空")
    func empty() {
        #expect(throws: CSVImportError.empty) { try CSVImport.parse("  \n ") }
    }

    @Test("バックアップ（JSON）は別の入口へ案内する")
    func backupJSON() {
        #expect(throws: CSVImportError.looksLikeBackup) { try CSVImport.parse(#"{"app":"Jansan"}"#) }
    }

    @Test("名前の行が無い")
    func scoresFirst() {
        #expect(throws: CSVImportError.scoresBeforeNames(line: 1)) { try CSVImport.parse("1,30,10\n") }
    }

    @Test("2人では表にならない")
    func tooFewPlayers() {
        #expect(throws: CSVImportError.playerCount(line: 1, count: 2)) {
            try CSVImport.parse("No,A,B\n1,30,-30")
        }
    }

    @Test("同じ名前が2列あると集計で混ざるので断る")
    func duplicateName() {
        #expect(throws: CSVImportError.duplicateName(line: 1, name: "A")) {
            try CSVImport.parse("No,A,A,B\n1,1,2,-3")
        }
    }

    @Test("数ではない点数は、行と中身を示して断る")
    func notANumber() {
        #expect(throws: CSVImportError.notANumber(line: 2, cell: "abc")) {
            try CSVImport.parse("No,A,B,C\n1,30,abc,-30")
        }
    }

    @Test("名前より点数が多い")
    func tooManyScores() {
        #expect(throws: CSVImportError.tooManyScores(line: 2)) {
            try CSVImport.parse("No,A,B,C\n1,1,2,-3,5")
        }
    }

    @Test("名前だけで点数が無い")
    func noRounds() {
        #expect(throws: CSVImportError.noRounds(line: 1)) { try CSVImport.parse("No,A,B,C") }
    }
}

@Suite("CSVの取り込み・重複と日付")
struct CSVImportDuplicateAndDateTests {

    @Test("すでにある表と、貼り付けの中で重なった表は飛ばす")
    func duplicates() throws {
        let csv = played().csv()
        let games = try CSVImport.parse(csv + "\n" + csv)
        #expect(CSVImport.duplicates(games, existing: []) == [false, true])
        #expect(CSVImport.duplicates(games, existing: [CSVImport.fingerprint(of: played())]) == [true, true])
    }

    @Test("日付未記入の印")
    func unknownDate() {
        #expect(PlayedDate.isUnknown(PlayedDate.unknown))
        #expect(PlayedDate.isUnknown(Date()) == false)
        #expect(PlayedDate.isUnknown(nil) == false)
    }

    @Test("日付未記入はバックアップを通っても未記入のまま")
    func unknownDateSurvivesBackup() throws {
        let game = BackupGame(uid: UUID(), playedAt: PlayedDate.unknown, savedAt: Date(),
                              note: "", snapshot: try CSVImport.parse(played().csv())[0].snapshot)
        let restored = try Backup.decode(try Backup.encode(BackupFile(games: [game])))
        #expect(PlayedDate.isUnknown(restored.games[0].playedAt))
    }

    @Test("日付未記入は「今月」などの期間に入らず、全期間には入る")
    func unknownDateInPeriods() {
        let now = Date()
        #expect(StatsPeriod.all.contains(PlayedDate.unknown, now: now))
        #expect(StatsPeriod.thisYear.contains(PlayedDate.unknown, now: now) == false)
        #expect(StatsPeriod.last30Days.contains(PlayedDate.unknown, now: now) == false)
    }
}
