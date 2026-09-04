import Testing
import Foundation
@testable import JansanCore

// 取り込みは「間違えると点数が消える」操作なので、壊れる側の挙動もテストで固定する。

private let yonma = ["中村", "五十嵐", "斎藤", "佐々木"]

private func snapshot(_ scores: [Int] = [30, 10, -10, -30], decimalMode: Bool = false) -> GameSnapshot {
    var session = Session(players: yonma, decimalMode: decimalMode)
    for (column, value) in scores.enumerated().dropLast() {
        session.enter(value, at: Position(round: 0, column: column))
    }
    return GameSnapshot(roster: Roster(names: yonma, activeCount: 4),
                        session: session, autoConfirm: true)
}

private func backupGame(uid: UUID = UUID(), decimalMode: Bool = false) -> BackupGame {
    BackupGame(uid: uid, playedAt: Date(timeIntervalSince1970: 1_700_000_000),
               savedAt: Date(timeIntervalSince1970: 1_700_000_100),
               note: "友人宅", snapshot: snapshot(decimalMode: decimalMode))
}

@Suite("バックアップの読み書き")
struct BackupCodecTests {

    @Test("書き出して読み直すと元に戻る")
    func roundTrip() throws {
        let file = BackupFile(games: [backupGame(), backupGame()])
        let restored = try Backup.decode(try Backup.encode(file))

        #expect(restored.games.count == 2)
        #expect(restored.formatVersion == BackupFile.currentFormatVersion)
        #expect(restored.games[0].note == "友人宅")
        #expect(restored.games[0].snapshot.session.totals == [30, 10, -10, -30])
    }

    @Test("CSVは復元できない形式なので、読ませようとすると弾かれる")
    func rejectsCSV() {
        #expect(throws: BackupError.notJSON) {
            try Backup.decode("局,中村,五十嵐\n1,30,10\n")
        }
    }

    @Test("他のアプリのJSONは弾く")
    func rejectsForeignJSON() {
        #expect(throws: BackupError.self) {
            try Backup.decode(#"{"formatVersion":1,"app":"Other","exportedAt":"2026-01-01T00:00:00Z","games":[]}"#)
        }
    }

    @Test("将来の形式は読まずに断る")
    func rejectsNewerFormat() throws {
        var file = BackupFile(games: [])
        file.formatVersion = BackupFile.currentFormatVersion + 1
        let data = try JSONEncoder.iso8601.encode(file)
        #expect(throws: BackupError.tooNew(BackupFile.currentFormatVersion + 1)) {
            try Backup.decode(data)
        }
    }
}

@Suite("取り込みの下見")
struct ImportPlanTests {

    @Test("持っていない対局は追加される")
    func addsNewGames() {
        let plan = Backup.plan(file: BackupFile(games: [backupGame(), backupGame()]),
                               existingUIDs: [], decimalMode: false)
        #expect(plan.added.count == 2)
        #expect(plan.skipped == 0)
    }

    @Test("uid が同じものは飛ばす。二度取り込んでも増えない")
    func skipsDuplicates() {
        let uid = UUID()
        let plan = Backup.plan(file: BackupFile(games: [backupGame(uid: uid)]),
                               existingUIDs: [uid], decimalMode: false)
        #expect(plan.added.isEmpty)
        #expect(plan.skipped == 1)
    }

    @Test("ファイルの中で uid が重複していても1件しか入らない")
    func skipsDuplicatesWithinFile() {
        let uid = UUID()
        let plan = Backup.plan(file: BackupFile(games: [backupGame(uid: uid), backupGame(uid: uid)]),
                               existingUIDs: [], decimalMode: false)
        #expect(plan.added.count == 1)
        #expect(plan.skipped == 1)
    }

    @Test("表示モードが食い違う対局は、取り込む前に知らせる")
    func flagsDecimalMismatch() {
        let plan = Backup.plan(file: BackupFile(games: [backupGame(decimalMode: true)]),
                               existingUIDs: [], decimalMode: false)
        #expect(plan.added.count == 1)
        #expect(plan.decimalMismatch.count == 1, "10倍ズレる記録を見逃している")
    }

    @Test("空の表は取り込まない")
    func rejectsEmptyGames() {
        let empty = BackupGame(uid: UUID(), playedAt: .now, savedAt: .now, note: "",
                               snapshot: GameSnapshot(roster: Roster(members: []),
                                                      session: Session(players: []),
                                                      autoConfirm: true))
        let plan = Backup.plan(file: BackupFile(games: [empty]), existingUIDs: [], decimalMode: false)
        #expect(plan.added.isEmpty)
        #expect(plan.broken == 1)
    }
}

@Suite("取り消し")
struct UndoStackTests {

    @Test("積んだら戻せる")
    func pushAndPop() {
        var stack = UndoStack<Int>()
        #expect(stack.canUndo == false)
        stack.push(1)
        stack.push(2)
        #expect(stack.pop() == 2)
        #expect(stack.pop() == 1)
        #expect(stack.canUndo == false)
        #expect(stack.pop() == nil)
    }

    @Test("上限を超えると古いものから捨てる")
    func respectsLimit() {
        var stack = UndoStack<Int>(limit: 3)
        for i in 1...5 { stack.push(i) }
        #expect(stack.count == 3)
        #expect(stack.pop() == 5)
        #expect(stack.pop() == 4)
        #expect(stack.pop() == 3)
        #expect(stack.canUndo == false)
    }

    @Test("上限に0を渡しても1件は持つ")
    func clampsLimit() {
        var stack = UndoStack<Int>(limit: 0)
        stack.push(1)
        #expect(stack.pop() == 1)
    }
}

private extension JSONEncoder {
    static var iso8601: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}
