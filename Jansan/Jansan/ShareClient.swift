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

    // MARK: - 受け取る（購読）

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
