import Foundation
import CloudKit
import JansanCore

/// CloudKit の公開データベースとのやり取り。**ここだけがアプリ側に残る通信。**
///
/// 鍵・レコード名・封のし方は Core（ShareCrypto）にある。ここは運ぶだけ。
///
/// レコード名はパスワードを知らないと作れないので、公開DBに置いても
/// 他人には見つけられない。中身も封がしてある。
@MainActor
enum ShareClient {

    static let containerID = "iCloud.com.zzzjjj080.Jansan"
    static let recordType = "SharedDirectory"

    private static var database: CKDatabase {
        CKContainer(identifier: containerID).publicCloudDatabase
    }

    enum Failure: Error, Equatable {
        /// iCloud にサインインしていない
        case noAccount
        /// その ID＋パスワードの組は、別の人が既に使っている
        case takenByOthers
        /// 見つからない（ID かパスワードが違う）
        case notFound
        /// 開けない（パスワード違いか、壊れている）
        case cannotOpen
        /// 通信できない
        case network(String)

        var message: String {
            switch self {
            case .noAccount: "iCloudにサインインしていないため、共有できません。iPhoneの設定からサインインしてください。"
            case .takenByOthers: "そのIDとパスワードの組は、すでに他の人が使っています。どちらかを変えてください。"
            case .notFound: "見つかりませんでした。IDとパスワードを確かめてください。"
            case .cannotOpen: "開けませんでした。パスワードが違うか、送り主が中身を作り直しています。"
            case .network(let s): "通信できませんでした。\(s)"
            }
        }
    }

    /// iCloud にサインインしているか。公開DBは読むだけならサインイン不要だが、
    /// 書く側には要る
    static func accountAvailable() async -> Bool {
        (try? await CKContainer(identifier: containerID).accountStatus()) == .available
    }

    // MARK: - 送る（オーナー）

    /// ディレクトリの中身を丸ごと公開DBへ置く。
    ///
    /// 既に同じレコードがあって、札（ownerToken）が自分のものでなければ**上書きしない。**
    /// 同じ ID＋パスワードを偶然選んだ他人の記録を消してしまわないため。
    static func publish(_ document: SharedDirectoryDocument,
                        id: String, password: String, ownerToken: String) async throws {
        guard await accountAvailable() else { throw Failure.noAccount }

        let recordID = CKRecord.ID(recordName: ShareCrypto.recordName(id: id, password: password))
        let record: CKRecord
        do {
            let existing = try await database.record(for: recordID)
            guard (existing["ownerToken"] as? String) == ownerToken else { throw Failure.takenByOthers }
            record = existing
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: recordType, recordID: recordID)
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure.network(describe(error))
        }

        let sealed = try document.sealed(id: id, password: password)
        // 1MB を超える塊は CKAsset でしか置けない。最初から Asset にしておけば境目を気にしない
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try sealed.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        record["payload"] = CKAsset(fileURL: url)
        record["ownerToken"] = ownerToken
        record["updatedAt"] = Date.now
        record["gameCount"] = document.backup.games.count

        do {
            _ = try await database.save(record)
        } catch {
            throw Failure.network(describe(error))
        }
    }

    /// 公開をやめる。レコードごと消す
    static func unpublish(id: String, password: String) async throws {
        let recordID = CKRecord.ID(recordName: ShareCrypto.recordName(id: id, password: password))
        do {
            _ = try await database.deleteRecord(withID: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            // もう無い。目的は達している
        } catch {
            throw Failure.network(describe(error))
        }
    }

    // MARK: - 受け取り票（何人が受け取っているか）

    /// この端末の乱数。受け取り票に書く。端末ごとに1つで、作り直さない
    private static var installID: String {
        let key = "shareInstallID"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    /// その共有の票を全枠まとめて取る。無い枠は入らない
    private static func receipts(share: String) async throws -> [String: CKRecord] {
        let ids = ShareReceipt.allRecordNames(share: share).map { CKRecord.ID(recordName: $0) }
        var found: [String: CKRecord] = [:]
        for (recordID, result) in try await database.records(for: ids) {
            if case .success(let record) = result { found[recordID.recordName] = record }
        }
        return found
    }

    /// 受け取った端末が票を置く。もう置いてあれば「最後に見た日時」だけ更新する。
    ///
    /// **失敗しても黙る。** 票は人数を数えるためのおまけで、受け取り自体を止める理由にならない。
    /// iCloud にサインインしていない端末は書けないので、数に入らない
    static func recordReceipt(id: String, password: String) async {
        guard await accountAvailable() else { return }
        let share = ShareCrypto.recordName(id: id, password: password)
        let mine = installID
        guard let found = try? await receipts(share: share) else { return }

        // 先に自分の票を探す。空いた枠に作り直すと、1台で2枚になる
        var candidates: [CKRecord] = []
        if let own = found.values.first(where: { ($0["installID"] as? String) == mine }) {
            candidates = [own]
        } else {
            candidates = ShareReceipt.slotOrder(installID: mine)
                .map { ShareReceipt.recordName(share: share, slot: $0) }
                .filter { found[$0] == nil }
                .prefix(3)
                .map { name in
                    let record = CKRecord(recordType: ShareReceipt.recordType, recordID: CKRecord.ID(recordName: name))
                    record["installID"] = mine
                    record["share"] = share
                    return record
                }
        }
        for record in candidates {
            record["lastSeenAt"] = Date.now
            do {
                _ = try await database.save(record)
                return
            } catch let error as CKError where error.code == .serverRecordChanged {
                continue   // 同じ瞬間に他の端末がその枠を取った。次の空きへ
            } catch {
                return
            }
        }
    }

    /// 受け取るのをやめた端末が、自分の票を消す
    static func removeReceipt(id: String, password: String) async {
        let share = ShareCrypto.recordName(id: id, password: password)
        let mine = installID
        guard let found = try? await receipts(share: share) else { return }
        for record in found.values where (record["installID"] as? String) == mine {
            _ = try? await database.deleteRecord(withID: record.recordID)
        }
    }

    /// 送った側に出す「何人が受け取っているか」。通信できなければ nil
    static func receiptSummary(id: String, password: String) async -> ShareReceipt.Summary? {
        let share = ShareCrypto.recordName(id: id, password: password)
        guard let found = try? await receipts(share: share) else { return nil }
        return ShareReceipt.Summary(lastSeen: found.values.compactMap { $0["lastSeenAt"] as? Date })
    }

    // MARK: - 受け取る（購読）

    /// 共有レコードの札（ownerToken）だけを読む。更新の知らせを頼むときの目印に使う
    static func ownerToken(id: String, password: String) async -> String? {
        let recordID = CKRecord.ID(recordName: ShareCrypto.recordName(id: id, password: password))
        guard let result = try? await database.records(for: [recordID], desiredKeys: ["ownerToken"]),
              case .success(let record)? = result[recordID] else { return nil }
        return record["ownerToken"] as? String
    }

    static func fetch(id: String, password: String) async throws -> SharedDirectoryDocument {
        let recordID = CKRecord.ID(recordName: ShareCrypto.recordName(id: id, password: password))
        let record: CKRecord
        do {
            record = try await database.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            throw Failure.notFound
        } catch {
            throw Failure.network(describe(error))
        }
        guard let asset = record["payload"] as? CKAsset, let url = asset.fileURL,
              let sealed = try? Data(contentsOf: url) else {
            throw Failure.cannotOpen
        }
        do {
            return try SharedDirectoryDocument.opened(sealed, id: id, password: password)
        } catch {
            throw Failure.cannotOpen
        }
    }

    private static func describe(_ error: Error) -> String {
        if let ck = error as? CKError {
            switch ck.code {
            case .networkUnavailable, .networkFailure: return "インターネットに接続できません。"
            case .notAuthenticated: return "iCloudにサインインしていません。"
            case .quotaExceeded: return "iCloudの容量が足りません。"
            default: return ck.localizedDescription
            }
        }
        return error.localizedDescription
    }
}
