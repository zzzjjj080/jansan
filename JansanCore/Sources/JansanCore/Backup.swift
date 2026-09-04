import Foundation

/// バックアップに入れる1件。
///
/// CSVは人が読むためのもので、**そこから表を復元することはできない**
/// （合計行つき・お休みは空欄・小数変換済み）。復元用はこちらを使う。
public struct BackupGame: Codable, Equatable, Sendable {
    /// 取り込みの重複判定に使う。同じ `uid` が既にあれば飛ばす
    public var uid: UUID
    /// 対局した日
    public var playedAt: Date
    /// 保存した日時
    public var savedAt: Date
    public var note: String
    public var snapshot: GameSnapshot

    public init(uid: UUID, playedAt: Date, savedAt: Date, note: String, snapshot: GameSnapshot) {
        self.uid = uid
        self.playedAt = playedAt
        self.savedAt = savedAt
        self.note = note
        self.snapshot = snapshot
    }
}

/// バックアップファイルの中身。
///
/// `formatVersion` は将来の読み替えのために最初から持たせる。
/// 後から足すと、それ以前に書き出したファイルを見分けられない。
public struct BackupFile: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var app: String
    public var exportedAt: Date
    public var games: [BackupGame]

    public init(games: [BackupGame], exportedAt: Date = .now) {
        self.formatVersion = Self.currentFormatVersion
        self.app = "Jansan"
        self.exportedAt = exportedAt
        self.games = games
    }
}

/// 取り込んだ結果の内訳。**そのまま画面に出せる粒度**にしてある
public struct ImportResult: Equatable, Sendable {
    /// 新しく入る対局
    public var added: [BackupGame]
    /// uid が既にあったので飛ばした件数
    public var skipped: Int
    /// 読めなかった件数
    public var broken: Int
    /// 表示モードが食い違う対局。混ぜると10倍ズレるので、取り込む前に知らせる
    public var decimalMismatch: [BackupGame]

    public init(added: [BackupGame] = [], skipped: Int = 0, broken: Int = 0,
                decimalMismatch: [BackupGame] = []) {
        self.added = added
        self.skipped = skipped
        self.broken = broken
        self.decimalMismatch = decimalMismatch
    }
}

public enum BackupError: Error, Equatable {
    /// JSONとして読めない
    case notJSON
    /// 雀算のバックアップではない
    case notJansanBackup
    /// このアプリより新しい形式
    case tooNew(Int)
}

public enum Backup {

    public static func encode(_ file: BackupFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(file)
    }

    /// 文字列から読む。**貼り付け欄がiPhoneでは最速**なので、Dataではなく文字列も受ける
    public static func decode(_ text: String) throws -> BackupFile {
        guard let data = text.data(using: .utf8) else { throw BackupError.notJSON }
        return try decode(data)
    }

    public static func decode(_ data: Data) throws -> BackupFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let file = try decoder.decode(BackupFile.self, from: data)
            guard file.app == "Jansan" else { throw BackupError.notJansanBackup }
            guard file.formatVersion <= BackupFile.currentFormatVersion else {
                throw BackupError.tooNew(file.formatVersion)
            }
            return file
        } catch let error as BackupError {
            throw error
        } catch {
            // JSONではあるが構造が違う場合もここに来る。利用者にはどちらも同じ意味
            throw (try? JSONSerialization.jsonObject(with: data)) == nil
                ? BackupError.notJSON
                : BackupError.notJansanBackup
        }
    }

    /// 取り込む前に、何が起きるかを数えておく。**確定する前に見せるための関数**
    ///
    /// - Parameters:
    ///   - existingUIDs: すでに持っている対局の uid
    ///   - decimalMode: 取り込み先の表示モード。食い違う対局を拾い出す
    public static func plan(
        file: BackupFile,
        existingUIDs: Set<UUID>,
        decimalMode: Bool
    ) -> ImportResult {
        var result = ImportResult()
        var seen = existingUIDs

        for game in file.games {
            // 空の表は取り込んでも意味がない
            guard game.snapshot.session.players.isEmpty == false else {
                result.broken += 1
                continue
            }
            guard seen.contains(game.uid) == false else {
                result.skipped += 1
                continue
            }
            seen.insert(game.uid)
            result.added.append(game)
            if game.snapshot.session.decimalMode != decimalMode {
                result.decimalMismatch.append(game)
            }
        }
        return result
    }
}
