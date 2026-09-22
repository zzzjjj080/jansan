import Foundation
import CloudKit
import SwiftData
import UIKit
import UserNotifications
import JansanCore

/// 受け取っているフォルダが更新されたら知らせる。
///
/// **受け取った端末が CloudKit に「この共有が更新されたら知らせて」と頼んでおく**（CKQuerySubscription）。
/// 送り主が記録を足して共有レコードが書き換わると、Apple の通知が届く。
///
/// 絞り込みには共有レコードの `ownerToken` を使う。**すでに索引（QUERYABLE）がある項目**なので、
/// スキーマの配備をやり直さずに済む。中身は封をしたままで、通知には名前を入れない
/// （名前は購読を作るとき、受け取った側が知っている名前を文面に入れる）
@MainActor
enum ShareNotifier {

    /// 設定「共有の更新を知らせる」の保存キー。既定はオン
    static let enabledKey = "notifyShareUpdates"

    /// 通知を押したとき・画面の手前で受けたときに、一覧へ「取り直して」と伝える
    static let didReceive = Notification.Name("shareUpdateReceived")

    private static var database: CKDatabase {
        CKContainer(identifier: ShareClient.containerID).publicCloudDatabase
    }

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// 購読の名前。共有レコードの名前から決まるので、同じ共有を二重に頼まない
    static func subscriptionID(recordName: String) -> String {
        "share-" + recordName
    }

    /// 購読の中身。**テストから形を確かめる**
    static func makeSubscription(recordName: String, ownerToken: String,
                                 directoryName: String) -> CKQuerySubscription {
        let subscription = CKQuerySubscription(
            recordType: ShareClient.recordType,
            predicate: NSPredicate(format: "ownerToken == %@", ownerToken),
            subscriptionID: subscriptionID(recordName: recordName),
            options: [.firesOnRecordUpdate, .firesOnRecordCreation]
        )
        let info = CKSubscription.NotificationInfo()
        info.title = "共有の記録が更新されました"
        info.alertBody = "「\(directoryName)」に新しい記録が届いています。開くと最新になります。"
        info.soundName = "default"
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        return subscription
    }

    /// 受け取ったフォルダの更新を知らせるよう頼む。**失敗しても受け取りは済んでいる**ので黙る
    static func enable(id: String, password: String, name: String) async {
        guard isEnabled, await ShareClient.accountAvailable() else { return }
        await requestPermission()
        let recordName = ShareCrypto.recordName(id: id, password: password)
        guard let token = await ShareClient.ownerToken(id: id, password: password) else { return }
        let subscription = makeSubscription(recordName: recordName, ownerToken: token, directoryName: name)
        _ = try? await database.save(subscription)
    }

    /// 受け取るのをやめたら、知らせも止める
    static func disable(id: String, password: String) async {
        let recordName = ShareCrypto.recordName(id: id, password: password)
        _ = try? await database.deleteSubscription(withID: subscriptionID(recordName: recordName))
    }

    /// 受け取っているフォルダと、頼んである知らせをそろえる。
    /// **入れ直しや機種変更のあと**でも知らせが届くように、起動のたびに足りないものだけ足す。
    /// 設定でオフにしていれば、頼んである知らせを全部取り消す
    static func syncAll(in context: ModelContext) async {
        guard await ShareClient.accountAvailable() else { return }
        let received = DirectoryStore.all(in: context).filter(\.isSubscribed)
        guard let existing = try? await database.allSubscriptions() else { return }
        let existingIDs = Set(existing.map(\.subscriptionID).filter { $0.hasPrefix("share-") })

        guard isEnabled else {
            for id in existingIDs { _ = try? await database.deleteSubscription(withID: id) }
            return
        }
        let wanted = Dictionary(uniqueKeysWithValues: received.map {
            (subscriptionID(recordName: ShareCrypto.recordName(id: $0.shareID, password: $0.sharePassword)), $0)
        })
        for (id, directory) in wanted where !existingIDs.contains(id) {
            await enable(id: directory.shareID, password: directory.sharePassword, name: directory.name)
        }
        // 受け取るのをやめたのに残っている知らせは消す
        for id in existingIDs where wanted[id] == nil {
            _ = try? await database.deleteSubscription(withID: id)
        }
    }

    /// 通知の許可。**最初に受け取ったときに1回だけ聞く**（起動した瞬間には聞かない）
    static func requestPermission() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        UIApplication.shared.registerForRemoteNotifications()
    }
}

/// 通知を画面の手前でも出し、押されたら一覧に取り直させる
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// アプリを開いているときに届いた知らせも出す（出さないと、更新されたことに気づけない）
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        await MainActor.run { NotificationCenter.default.post(name: ShareNotifier.didReceive, object: nil) }
        return [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        await MainActor.run { NotificationCenter.default.post(name: ShareNotifier.didReceive, object: nil) }
    }
}
