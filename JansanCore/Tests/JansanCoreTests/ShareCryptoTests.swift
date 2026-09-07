import Testing
import Foundation
@testable import JansanCore

// 共有の守りは「レコード名にパスワードが要る」の1点にかかっている。ここを固定する。

@Suite("共有のID・パスワード")
struct ShareValidationTests {

    @Test("大小と記号は吸収する")
    func normalizes() {
        #expect(ShareCrypto.normalize("Act-D 01") == "actd01")
        #expect(ShareCrypto.normalize("ＡＢＣ") == "", "全角は落とす")
    }

    @Test("IDは3〜20文字、パスワードは4〜20文字")
    func lengths() {
        #expect(throws: ShareCrypto.ValidationError.idTooShort) {
            try ShareCrypto.validate(id: "ab", password: "abcd")
        }
        #expect(throws: ShareCrypto.ValidationError.passwordTooShort) {
            try ShareCrypto.validate(id: "abc", password: "abc")
        }
        #expect(throws: ShareCrypto.ValidationError.idTooLong) {
            try ShareCrypto.validate(id: String(repeating: "a", count: 21), password: "abcd")
        }
        let ok = try? ShareCrypto.validate(id: "ActD", password: "ActD")
        #expect(ok?.id == "actd" && ok?.password == "actd")
    }
}

@Suite("レコード名と鍵")
struct ShareRecordNameTests {

    @Test("大小違いは同じレコードになる")
    func caseInsensitive() {
        #expect(ShareCrypto.recordName(id: "ActD", password: "PASS") ==
                ShareCrypto.recordName(id: "actd", password: "pass"))
    }

    @Test("パスワードが違えば別のレコード。IDだけでは辿り着けない")
    func passwordChangesName() {
        #expect(ShareCrypto.recordName(id: "actd", password: "aaaa") !=
                ShareCrypto.recordName(id: "actd", password: "aaab"))
    }

    @Test("レコード名は64桁の16進")
    func shape() {
        let name = ShareCrypto.recordName(id: "actd", password: "actd")
        #expect(name.count == 64)
        #expect(name.allSatisfy { $0.isHexDigit })
    }

    @Test("封をして開けると元に戻る")
    func roundTrip() throws {
        let plain = Data("麻雀の記録".utf8)
        let sealed = try ShareCrypto.seal(plain, id: "actd", password: "actd")
        #expect(sealed != plain)
        #expect(try ShareCrypto.open(sealed, id: "ActD", password: "ACTD") == plain)
    }

    @Test("パスワードが違うと開かない")
    func wrongPassword() throws {
        let sealed = try ShareCrypto.seal(Data("x".utf8), id: "actd", password: "actd")
        #expect(throws: ShareCrypto.CryptoError.cannotOpen) {
            try ShareCrypto.open(sealed, id: "actd", password: "actx")
        }
    }

    @Test("壊れたデータも「開かない」の一言で済ませる")
    func corrupted() {
        #expect(throws: ShareCrypto.CryptoError.cannotOpen) {
            try ShareCrypto.open(Data([1, 2, 3]), id: "actd", password: "actd")
        }
    }
}

@Suite("共有ディレクトリの塊")
struct SharedDocumentTests {

    private func sampleBackup() -> BackupFile {
        var session = Session(players: ["中村", "五十嵐", "斎藤", "佐々木"])
        session.enter(30, at: Position(round: 0, column: 0))
        session.enter(10, at: Position(round: 0, column: 1))
        session.enter(-10, at: Position(round: 0, column: 2))
        let snap = GameSnapshot(roster: Roster(names: session.players, activeCount: 4),
                                session: session, autoConfirm: true)
        return BackupFile(games: [BackupGame(uid: UUID(), playedAt: .now, savedAt: .now,
                                             note: "", snapshot: snap)])
    }

    @Test("名前と表示モードと対局が丸ごと往復する")
    func roundTrip() throws {
        let doc = SharedDirectoryDocument(name: "田中宅", decimalMode: true, backup: sampleBackup())
        let sealed = try doc.sealed(id: "actd", password: "actd")
        let back = try SharedDirectoryDocument.opened(sealed, id: "actd", password: "actd")
        #expect(back.name == "田中宅")
        #expect(back.decimalMode == true)
        #expect(back.backup.games.count == 1)
        #expect(back.backup.games[0].snapshot.session.totals == [30, 10, -10, -30])
    }

    @Test("パスワード違いは中身を見せない")
    func wrongPassword() throws {
        let doc = SharedDirectoryDocument(name: "田中宅", decimalMode: false, backup: sampleBackup())
        let sealed = try doc.sealed(id: "actd", password: "actd")
        #expect(throws: ShareCrypto.CryptoError.cannotOpen) {
            try SharedDirectoryDocument.opened(sealed, id: "actd", password: "zzzz")
        }
    }
}
