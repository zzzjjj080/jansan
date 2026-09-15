import Testing
import Foundation
@testable import JansanCore

@Suite("受け取り票（何人が受け取っているか）")
struct ShareReceiptTests {

    @Test("枠の探し方は端末ごとに決まっていて、全枠を1回ずつ回る")
    func slotOrderCoversAllSlotsOnce() {
        let order = ShareReceipt.slotOrder(installID: "端末A")
        #expect(order.count == ShareReceipt.slotCount)
        #expect(Set(order).count == ShareReceipt.slotCount)
        // 起動し直しても同じ順番（hashValue のように変わらない）
        #expect(ShareReceipt.slotOrder(installID: "端末A") == order)
    }

    @Test("違う端末は、たいてい違う枠から探し始める")
    func differentDevicesStartAtDifferentSlots() {
        let starts = Set((0..<20).map { ShareReceipt.slotOrder(installID: "device-\($0)").first! })
        #expect(starts.count > 10)
    }

    @Test("レコード名は共有のレコード名＋枠の番号")
    func recordNames() {
        let share = ShareCrypto.recordName(id: "taku", password: "pass")
        #expect(ShareReceipt.recordName(share: share, slot: 7) == share + "-r7")
        let all = ShareReceipt.allRecordNames(share: share)
        #expect(all.count == ShareReceipt.slotCount)
        #expect(Set(all).count == ShareReceipt.slotCount)
        #expect(all.allSatisfy { $0.count <= 255 })
    }

    @Test("要約は票の枚数と、いちばん新しい日時")
    func summary() {
        let a = Date(timeIntervalSince1970: 1_000), b = Date(timeIntervalSince1970: 5_000)
        #expect(ShareReceipt.Summary(lastSeen: [a, b]) == ShareReceipt.Summary(lastSeen: [b, a]))
        #expect(ShareReceipt.Summary(lastSeen: [a, b]).count == 2)
        #expect(ShareReceipt.Summary(lastSeen: [a, b]).lastSeen == b)
        #expect(ShareReceipt.Summary(lastSeen: []).lastSeen == nil)
    }
}
