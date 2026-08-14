import UIKit

/// テンキーの触覚フィードバック。
///
/// 押すたびに `UIImpactFeedbackGenerator` を作ると、内部のエンジンが毎回起動し直しになり
/// 初動が鈍くなる。連打すると取りこぼしも出る。インスタンスを持ち回して、
/// 一度鳴らすたびに次の `prepare()` を仕込んでおくと、指の速さに追従する。
///
/// シミュレータには触覚デバイスが無いため、確認は実機でしかできない。
@MainActor
final class Haptics {
    /// 数字キー。硬く短い「カチッ」が電卓の打鍵に近い
    private let key = UIImpactFeedbackGenerator(style: .rigid)
    /// 確定・お休みなど、盤面が動いたとき。キーより一段強くして区別する
    private let commit = UIImpactFeedbackGenerator(style: .medium)

    /// テンキーを開いた時など、打ち始める直前に呼んでおく
    func warmUp() {
        key.prepare()
        commit.prepare()
    }

    func tap() {
        key.impactOccurred()
        key.prepare()
    }

    func confirm() {
        commit.impactOccurred()
        commit.prepare()
    }
}
