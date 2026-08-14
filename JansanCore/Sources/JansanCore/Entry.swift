import Foundation

/// 1局における1人分のマス。
///
/// プロトタイプ(HTML)では `{value, manual, auto, resting}` の4つのフラグで表していたが、
/// 「手入力なのに休み」「自動計算なのに値が無い」といったあり得ない組み合わせが作れてしまう。
/// Swiftではenumにして、そもそも表現できないようにする。
public enum Entry: Equatable, Sendable, Codable {
    /// まだ入力されていない(入力待ち)
    case empty
    /// その局に参加していない
    case resting
    /// 手で入力された点数
    case entered(Int)
    /// 残り1人になったので合計0から逆算された点数
    case derived(Int)

    public var value: Int? {
        switch self {
        case .empty, .resting: nil
        case .entered(let v), .derived(let v): v
        }
    }

    public var isResting: Bool { self == .resting }

    /// 手入力されたマス。自動計算のやり直しでは書き換えない
    public var isEntered: Bool {
        if case .entered = self { return true }
        return false
    }

    /// 入力待ちのマス。カーソルの自動移動先になる
    public var isOpen: Bool { self == .empty }
}
