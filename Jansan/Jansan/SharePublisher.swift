import Foundation
import SwiftData
import JansanCore

/// 共有中のディレクトリに溜まった変更を送る。
///
/// 保存のたびに呼ぶが、**失敗しても記録は手元に残る**（needsPublish が立ったまま）。
/// 次にアプリが前面に来たときにもう一度試す。オフラインで打っても困らないように。
@MainActor
enum SharePublisher {

    /// いま送っている最中のディレクトリ。二重送信を避ける
    private static var inFlight = Set<UUID>()

    /// needsPublish が立っている自分のディレクトリを全部送る
    static func publishPending(in context: ModelContext) async {
        let pending = DirectoryStore.all(in: context).filter { $0.isShared && $0.needsPublish && !$0.isSubscribed }
        for directory in pending {
            await publish(directory, in: context)
        }
    }

    /// 受け取っているディレクトリを全部、静かに取り直す。
    /// 一覧を開いたときに走らせて、件数の表示が古いままにならないようにする
    static func refreshSubscriptions(in context: ModelContext) async {
        for directory in DirectoryStore.all(in: context) where directory.isSubscribed {
            guard let doc = try? await ShareClient.fetch(id: directory.shareID,
                                                        password: directory.sharePassword) else { continue }
            directory.name = doc.name
            directory.decimalMode = doc.decimalMode
            directory.lastFetchedAt = .now
            DirectoryStore.replaceGames(of: directory, with: doc.backup, in: context)
        }
    }

    static func publish(_ directory: Directory, in context: ModelContext) async {
        guard directory.isShared, !inFlight.contains(directory.uid) else { return }
        inFlight.insert(directory.uid)
        defer { inFlight.remove(directory.uid) }

        let doc = DirectoryStore.document(of: directory, in: context)
        do {
            try await ShareClient.publish(doc, id: directory.shareID, password: directory.sharePassword,
                                          ownerToken: directory.ownerToken)
            directory.lastPublishedAt = .now
            directory.needsPublish = false
            try? context.save()
        } catch {
            // 印は立てたまま。設定画面に「まだ送っていない変更があります」と出る
            directory.needsPublish = true
            try? context.save()
        }
    }
}
