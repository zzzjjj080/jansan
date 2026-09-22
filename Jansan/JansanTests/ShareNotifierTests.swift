import Testing
import CloudKit
@testable import Jansan

/// 更新の知らせの頼み方。**通信はしない**（CloudKit に渡す形だけを固定する）
@MainActor
struct ShareNotifierTests {

    private let subscription = ShareNotifier.makeSubscription(
        recordName: "abc123", ownerToken: "TOKEN-1", directoryName: "田中宅")

    @Test("共有レコードの札で絞り、同じ共有を二重に頼まない名前にする")
    func identifiesTheShare() {
        #expect(subscription.subscriptionID == "share-abc123")
        #expect(subscription.recordType == ShareClient.recordType)
        #expect(subscription.predicate.predicateFormat.contains("ownerToken"))
        #expect(subscription.predicate.predicateFormat.contains("TOKEN-1"))
    }

    @Test("書き換えたときと作り直したときに知らせる。消したときは知らせない")
    func firesOnUpdateAndCreation() {
        #expect(subscription.querySubscriptionOptions.contains(.firesOnRecordUpdate))
        #expect(subscription.querySubscriptionOptions.contains(.firesOnRecordCreation))
        #expect(!subscription.querySubscriptionOptions.contains(.firesOnRecordDeletion))
    }

    @Test("通知の文面にフォルダの名前が入り、音が鳴る")
    func notificationText() {
        let info = subscription.notificationInfo
        #expect(info?.alertBody?.contains("田中宅") == true)
        #expect(info?.title?.isEmpty == false)
        #expect(info?.soundName == "default")
    }

    @Test("設定の既定はオン")
    func enabledByDefault() {
        UserDefaults.standard.removeObject(forKey: ShareNotifier.enabledKey)
        #expect(ShareNotifier.isEnabled)
    }
}
