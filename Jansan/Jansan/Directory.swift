import Foundation
import SwiftData
import JansanCore

/// 記録の入れ物。「田中宅」「会社の卓」のように、卓ごと・面子ごとに分ける。
///
/// 自分で作ったものと、他の人から ID＋パスワードで受け取ったもの（購読）が
/// 同じ形で並ぶ。**「他の人の記録を見る」は別のモードではなく、ディレクトリの1種類。**
///
/// すべての属性に既定値があるのは SavedGame と同じ理由。CloudKit と同期する
/// SwiftData のモデルは必須の属性を持てない（→ 引き継ぎ書 4-70c）。
@Model
final class Directory {
    /// 既存の記録は「マイ記録」に入る。このIDは固定で、全端末で同じ
    static let defaultUID = UUID(uuidString: "00000000-0000-0000-0000-00000000A001")!
    static let defaultName = "マイ記録"

    /// 「新しい対局を始める」で消える前の表を、黙って控えておく場所。
    /// 押し間違えても戻せるようにするためのもので、保存先には選べない
    static let autoBackupUID = UUID(uuidString: "00000000-0000-0000-0000-00000000A002")!
    static let autoBackupName = "自動バックアップ"
    /// 控えは溜め続けない。古いものから捨てる
    static let autoBackupLimit = 30

    var uid: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date.distantPast
    var updatedAt: Date = Date.distantPast
    /// 一覧の並び。小さいほど上
    var sortOrder: Int = 0

    // MARK: 共有（自分が公開する側）

    var isShared: Bool = false
    var shareID: String = ""
    var sharePassword: String = ""
    /// 最後に CloudKit へ送った時刻。nil なら一度も送っていない
    var lastPublishedAt: Date?
    /// 送り損ねている変更がある。オフラインで保存したときなど
    var needsPublish: Bool = false
    /// 同じ ID＋パスワードの組を、他の人に上書きされないための印。
    /// 公開レコードに平文で入れる。中身の秘密ではなく「誰のものか」の札
    var ownerToken: String = ""

    // MARK: 購読（他の人のを見る側）

    var isSubscribed: Bool = false
    var lastFetchedAt: Date?
    /// 受け取った側では、送り主の表示モードをそのまま使う
    var decimalMode: Bool = false

    init(uid: UUID = UUID(), name: String, sortOrder: Int = 0, createdAt: Date = .now) {
        self.uid = uid
        self.name = name
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.ownerToken = UUID().uuidString
    }

    var isDefault: Bool { uid == Self.defaultUID }
    var isAutoBackup: Bool { uid == Self.autoBackupUID }

    /// 自分で書き込めるか。購読したものは読むだけ
    var isEditable: Bool { !isSubscribed }

    /// 保存先として選べるか。自動バックアップは仕組みが入れる場所なので選ばせない
    var isSelectableDestination: Bool { isEditable && !isAutoBackup }

    /// 一覧に添える1行。**パスワードも出す。**
    /// （自動バックアップだけは別の説明にする）
    /// 共有相手に伝えるとき、設定画面を開き直さずに読めるようにするため
    var subtitle: String {
        if isAutoBackup { return "新しい対局を始める前の控え" }
        if isSubscribed { return "ID: \(shareID) ・ パスワード: \(sharePassword)" }
        if isShared { return "共有中 ・ ID: \(shareID) ・ パスワード: \(sharePassword)" }
        return "この端末とiCloud"
    }
}

/// ディレクトリの出し入れ。View から SwiftData を直接いじる箇所を減らす
enum DirectoryStore {

    /// 「マイ記録」が無ければ作る。**起動時に必ず通す。**
    ///
    /// CloudKit で同期していると、2台が同時に作って2件になることがある。
    /// uid が同じものが複数あれば古い方を残し、他は消す。
    @MainActor
    static func ensureDefault(in context: ModelContext) {
        let target = Directory.defaultUID
        let found = (try? context.fetch(FetchDescriptor<Directory>(
            predicate: #Predicate { $0.uid == target }
        ))) ?? []
        if found.isEmpty {
            context.insert(Directory(uid: target, name: Directory.defaultName, sortOrder: -1))
            try? context.save()
        } else if found.count > 1 {  // CloudKit で2台が同時に作ると重複しうる
            for extra in found.sorted(by: { $0.createdAt < $1.createdAt }).dropFirst() {
                context.delete(extra)
            }
            try? context.save()
        }
    }

    @MainActor
    static func all(in context: ModelContext) -> [Directory] {
        (try? context.fetch(FetchDescriptor<Directory>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        ))) ?? []
    }

    @MainActor
    static func directory(uid: UUID, in context: ModelContext) -> Directory? {
        try? context.fetch(FetchDescriptor<Directory>(predicate: #Predicate { $0.uid == uid })).first
    }

    /// そのディレクトリの記録。directoryId が nil の古い記録は「マイ記録」に属する
    @MainActor
    static func games(of directory: Directory, in context: ModelContext) -> [SavedGame] {
        let uid = directory.uid
        let all = (try? context.fetch(FetchDescriptor<SavedGame>(
            predicate: #Predicate { !$0.isDraft },
            sortBy: [SortDescriptor(\.savedAt, order: .reverse)]
        ))) ?? []
        return all.filter { ($0.directoryId ?? Directory.defaultUID) == uid }
    }

    /// 件数つきの1行。一覧と保存先の選択で同じ文言を使う
    @MainActor
    static func subtitle(of directory: Directory, in context: ModelContext) -> String {
        "\(gameCount(of: directory, in: context)) 件 ・ \(directory.subtitle)"
    }

    @MainActor
    static func gameCount(of directory: Directory, in context: ModelContext) -> Int {
        games(of: directory, in: context).count
    }

    /// 購読したディレクトリの中身を、受け取った塊で置き換える。
    /// 消してから入れ直す。差分で合わせようとすると、向こうで消した対局が残る
    @MainActor
    static func replaceGames(of directory: Directory, with backup: BackupFile, in context: ModelContext) {
        for old in games(of: directory, in: context) { context.delete(old) }
        for game in backup.games {
            guard let record = try? SavedGame(snapshot: game.snapshot, isDraft: false,
                                              savedAt: game.savedAt, playedAt: game.playedAt,
                                              note: game.note, uid: game.uid) else { continue }
            record.directoryId = directory.uid
            context.insert(record)
        }
        try? context.save()
    }

    /// 「新しい対局を始める」の前に、いまの表を黙って控える。
    ///
    /// **利用者は普通に保存してから始めるが、押し間違えることがある。**
    /// そのときに戻せる場所を1つ持たせておく。控えは古いものから捨てて溜めすぎない。
    @MainActor
    static func autoBackup(_ snapshot: GameSnapshot, in context: ModelContext) {
        // 何も打っていない表を控えても意味がない
        guard snapshot.session.playedRoundCount > 0 else { return }

        let directory = ensure(uid: Directory.autoBackupUID,
                               name: Directory.autoBackupName,
                               sortOrder: 1000, in: context)
        guard let record = try? SavedGame(snapshot: snapshot, isDraft: false) else { return }
        record.directoryId = directory.uid
        record.note = "自動保存"
        context.insert(record)

        // 古いものから捨てる。games(of:) は保存日時の新しい順
        let kept = games(of: directory, in: context)
        if kept.count > Directory.autoBackupLimit {
            for old in kept.dropFirst(Directory.autoBackupLimit) { context.delete(old) }
        }
        try? context.save()
    }

    /// 決まったUIDのディレクトリを用意する。無ければ作る
    @MainActor
    @discardableResult
    static func ensure(uid: UUID, name: String, sortOrder: Int, in context: ModelContext) -> Directory {
        if let found = directory(uid: uid, in: context) { return found }
        let directory = Directory(uid: uid, name: name, sortOrder: sortOrder)
        context.insert(directory)
        try? context.save()
        return directory
    }

    /// 送るための塊を作る
    @MainActor
    static func document(of directory: Directory, in context: ModelContext) -> SharedDirectoryDocument {
        let games = games(of: directory, in: context).compactMap { record -> BackupGame? in
            guard let snapshot = try? record.snapshot() else { return nil }
            return BackupGame(uid: record.uid, playedAt: record.effectivePlayedAt,
                              savedAt: record.savedAt, note: record.note, snapshot: snapshot)
        }
        // 表示モードは中身の多数派に合わせる。混ざっていても受け取り側で警告が出る
        let decimal = games.filter(\.snapshot.session.decimalMode).count * 2 > games.count
        return SharedDirectoryDocument(name: directory.name, decimalMode: decimal,
                                       backup: BackupFile(games: games))
    }
}
