import Foundation

/// 点数の表示。
///
/// 保存済みの記録は「保存した時のモード」で表示したいので、モードは必ず引数で受け取る。
/// 現在の設定を暗黙に参照すると、小数モードで保存した記録を整数モードで開いたときに
/// 10倍の点数に見えてしまう(プロトタイプで実際に踏んだ不具合)。
public enum ScoreFormatter {
    public static func string(_ value: Int, decimalMode: Bool) -> String {
        guard decimalMode else { return String(value) }
        let sign = value < 0 ? "-" : ""
        let magnitude = abs(value)
        return "\(sign)\(magnitude / 10).\(magnitude % 10)"
    }

    /// 合計欄など、プラスを明示したい場所用
    public static func signedString(_ value: Int, decimalMode: Bool) -> String {
        let body = string(value, decimalMode: decimalMode)
        return value > 0 ? "+\(body)" : body
    }
}
