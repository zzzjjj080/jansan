import Foundation

extension Session {
    /// 表をそのままCSVにする。メモやスプレッドシートに貼り付けて使う想定。
    ///
    /// 入力待ちの空行は出さない。お休みは空欄にして、点数0と区別できるようにする。
    public func csv() -> String {
        var lines = [(["No"] + players).joined(separator: ",")]

        for (index, round) in rounds.enumerated() {
            let hasContent = round.entries.contains { $0.value != nil || $0.isResting }
            guard hasContent else { continue }
            let cells = round.entries.map { entry -> String in
                guard !entry.isResting, let value = entry.value else { return "" }
                return ScoreFormatter.string(value, decimalMode: decimalMode)
            }
            lines.append(([String(index + 1)] + cells).joined(separator: ","))
        }

        let totalCells = totals.map { ScoreFormatter.string($0, decimalMode: decimalMode) }
        lines.append((["合計"] + totalCells).joined(separator: ","))
        return lines.joined(separator: "\n")
    }
}
