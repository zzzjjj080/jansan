import Foundation

/// 「何人が受け取っているか」を数えるための受け取り票。
///
/// 受け取った端末が、公開DBに**小さな票を1枚だけ**置く（端末ごとの乱数 installID と、最後に見た日時）。
/// 送った側は票の枚数と、いちばん新しい日時を見る。名前は置かない。
///
/// **票の置き場所は、共有レコード名に番号を付けた決まった名前（64枠）にする。**
/// 送った側は64個の名前をまとめて取りに行くだけで数えられるので、
/// 検索用の索引（コンソールでの設定）が要らない。公開DBは作った人しか書き換えられないので、
/// 他の端末が使っている枠は飛ばし、端末ごとに決まった枠から順に探す。
public enum ShareReceipt {

    public static let recordType = "ShareReceipt"

    /// 1つの共有につき数えられる端末の数
    public static let slotCount = 64

    /// 票のレコード名。`share` は `ShareCrypto.recordName(id:password:)`
    public static func recordName(share: String, slot: Int) -> String {
        "\(share)-r\(slot)"
    }

    /// その共有の、全枠のレコード名
    public static func allRecordNames(share: String) -> [String] {
        (0..<slotCount).map { recordName(share: share, slot: $0) }
    }

    /// この端末が枠を探す順番。端末ごとに始まりが決まっていて、全枠を1回ずつ回る。
    /// 同じ端末は何度受け取り直しても同じ枠に当たるので、票が増えていかない
    public static func slotOrder(installID: String) -> [Int] {
        let start = Int(stableHash(installID) % UInt64(slotCount))
        return (0..<slotCount).map { (start + $0) % slotCount }
    }

    /// 起動をまたいで変わらないハッシュ（FNV-1a）。Swift の hashValue は起動ごとに変わるので使えない
    static func stableHash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }

    /// 送った側に出す要約
    public struct Summary: Equatable, Sendable {
        public let count: Int
        /// いちばん最近、誰かが見た日時。票が無ければ nil
        public let lastSeen: Date?

        public init(lastSeen dates: [Date]) {
            count = dates.count
            lastSeen = dates.max()
        }
    }
}
