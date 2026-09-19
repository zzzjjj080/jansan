import Foundation
import Security
import SwiftUI

/// AI で読み取るための設定。**鍵はキーチェーンに置き、他の設定と混ぜない。**
///
/// 鍵が入っていなければ、写真の取り込みは端末の中の読み取りだけで動く
@MainActor
@Observable
final class AISettings {
    static let shared = AISettings()

    private let defaults = UserDefaults.standard

    var provider: AIProvider {
        didSet {
            defaults.set(provider.rawValue, forKey: "aiProvider")
            key = (try? AIKeychain.read(provider)) ?? ""
            model = defaults.string(forKey: modelKey) ?? provider.defaultModel
        }
    }

    /// いま選んでいる先の鍵。書き込みは setKey で行う
    private(set) var key: String

    var model: String {
        didSet { defaults.set(model, forKey: modelKey) }
    }

    private var modelKey: String { "aiModel-\(provider.rawValue)" }

    var hasKey: Bool { !key.isEmpty }

    private init() {
        let stored = AIProvider(rawValue: defaults.string(forKey: "aiProvider") ?? "") ?? .claude
        provider = stored
        key = (try? AIKeychain.read(stored)) ?? ""
        model = defaults.string(forKey: "aiModel-\(stored.rawValue)") ?? stored.defaultModel
    }

    /// 空にすると消す。失敗は握り潰さず、画面に出す
    func setKey(_ newKey: String) throws {
        let trimmed = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try AIKeychain.delete(provider)
        } else {
            try AIKeychain.write(trimmed, for: provider)
        }
        key = trimmed
    }

    var reader: AIReader? {
        hasKey ? AIReader(provider: provider, key: key, model: model) : nil
    }
}

/// 鍵の保管。**UserDefaults には置かない**（バックアップや書き出しに混ざる）
enum AIKeychain {
    struct Failure: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "鍵を保存できませんでした（\(status)）" }
    }

    private static let service = "com.zzzjjj080.Jansan.ai"

    private static func query(_ provider: AIProvider) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: provider.rawValue]
    }

    static func read(_ provider: AIProvider) throws -> String {
        var q = query(provider)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = item as? Data else { throw Failure(status: status) }
        return String(decoding: data, as: UTF8.self)
    }

    static func write(_ key: String, for provider: AIProvider) throws {
        try delete(provider)
        var q = query(provider)
        q[kSecValueData as String] = Data(key.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else { throw Failure(status: status) }
    }

    static func delete(_ provider: AIProvider) throws {
        let status = SecItemDelete(query(provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
    }
}
