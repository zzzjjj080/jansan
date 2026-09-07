import Foundation
import CryptoKit

/// 共有の「ID＋パスワード」まわり。鍵の作り方とレコード名の決め方をここに閉じ込める。
///
/// 守り方の要点は1つ。**レコード名そのものを ID とパスワードの両方から作る。**
/// パスワードを知らない人はレコードに辿り着けず、存在するかどうかも分からない。
/// 総当たりするには CloudKit へ毎回問い合わせるしかなく、Apple 側で頭打ちになる。
/// これがあるからパスワードは短いままでよい（4文字で足りる）。
///
/// ID も パスワードも **大小を区別しない**。口頭で伝えるとき「大文字ですか」と
/// 聞き返さずに済むようにするため。
public enum ShareCrypto {

    public static let idLength = 3...20
    public static let passwordLength = 4...20

    /// 小文字にして、半角英数以外を落とす。入力欄の揺れをここで吸収する
    public static func normalize(_ raw: String) -> String {
        raw.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    public enum ValidationError: Error, Equatable {
        case idTooShort, idTooLong, passwordTooShort, passwordTooLong
    }

    /// 入力を整えて検証する。通ればそのまま保存してよい値が返る
    public static func validate(id rawID: String, password rawPassword: String) throws -> (id: String, password: String) {
        let id = normalize(rawID)
        let password = normalize(rawPassword)
        guard id.count >= idLength.lowerBound else { throw ValidationError.idTooShort }
        guard id.count <= idLength.upperBound else { throw ValidationError.idTooLong }
        guard password.count >= passwordLength.lowerBound else { throw ValidationError.passwordTooShort }
        guard password.count <= passwordLength.upperBound else { throw ValidationError.passwordTooLong }
        return (id, password)
    }

    /// 方式を変えたときに古いレコードと混ざらないよう、名前と鍵の両方に混ぜる
    private static let scheme = "jansan-share-v1"

    /// CloudKit のレコード名。**ID だけからは決まらない。**
    public static func recordName(id: String, password: String) -> String {
        let input = Data("\(scheme)|name|\(normalize(id))|\(normalize(password))".utf8)
        return SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }

    /// 中身を暗号化する鍵。レコード名とは別の導出にして、名前から鍵を逆算できないようにする
    static func key(id: String, password: String) -> SymmetricKey {
        let secret = SymmetricKey(data: Data("\(normalize(id))|\(normalize(password))".utf8))
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: secret,
            salt: Data("\(scheme)|salt".utf8),
            info: Data("\(scheme)|key".utf8),
            outputByteCount: 32
        )
    }

    public enum CryptoError: Error, Equatable {
        /// パスワードが違うか、中身が壊れている。利用者にはどちらも「開けない」でよい
        case cannotOpen
    }

    /// AES-GCM で封をする。nonce・暗号文・タグを1本にまとめた形（combined）で返す
    public static func seal(_ plain: Data, id: String, password: String) throws -> Data {
        let box = try AES.GCM.seal(plain, using: key(id: id, password: password))
        guard let combined = box.combined else { throw CryptoError.cannotOpen }
        return combined
    }

    public static func open(_ sealed: Data, id: String, password: String) throws -> Data {
        do {
            let box = try AES.GCM.SealedBox(combined: sealed)
            return try AES.GCM.open(box, using: key(id: id, password: password))
        } catch {
            throw CryptoError.cannotOpen
        }
    }
}

/// 共有レコードの中身。ディレクトリ1つぶんを丸ごと1つの塊にする。
///
/// 対局ごとにレコードを分けない。1塊にすれば**既に作ってあるバックアップの形式を
/// そのまま使え**、取り込み側も既存の `Backup.plan` で重複を弾ける。
/// 麻雀の記録は数百件でも数百KBなので、毎回丸ごと送っても問題ない。
public struct SharedDirectoryDocument: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var name: String
    public var decimalMode: Bool
    public var backup: BackupFile

    public init(name: String, decimalMode: Bool, backup: BackupFile) {
        self.formatVersion = Self.currentFormatVersion
        self.name = name
        self.decimalMode = decimalMode
        self.backup = backup
    }

    /// 暗号化して送れる形にする
    public func sealed(id: String, password: String) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try ShareCrypto.seal(try encoder.encode(self), id: id, password: password)
    }

    /// 受け取った塊を開く。パスワード違いと壊れたデータは区別せず `cannotOpen`
    public static func opened(_ sealed: Data, id: String, password: String) throws -> SharedDirectoryDocument {
        let plain = try ShareCrypto.open(sealed, id: id, password: password)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let doc = try? decoder.decode(SharedDirectoryDocument.self, from: plain) else {
            throw ShareCrypto.CryptoError.cannotOpen
        }
        return doc
    }
}
