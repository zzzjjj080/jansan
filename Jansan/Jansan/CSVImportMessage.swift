import Foundation
import JansanCore

/// 取り込みで断るときの文言。**貼り付けからでも写真からでも同じ言い方**にする
enum CSVImportMessage {

    static func text(for error: CSVImportError) -> String {
        switch error {
        case .empty:
            "何も入っていません。"
        case .looksLikeBackup:
            "これはバックアップです。設定の「バックアップ」から取り込んでください。"
        case .scoresBeforeNames(let line):
            "\(line)行目：名前の行より先に点数があります。点数の上に「No,名前,名前,…」の行を入れてください。"
        case .playerCount(let line, let count):
            "\(line)行目：名前が\(count)人ぶんです。3〜\(Roster.maxActive)人の表にしてください。"
        case .emptyName(let line):
            "\(line)行目：名前が空の列があります。"
        case .duplicateName(let line, let name):
            "\(line)行目：「\(name)」が2列あります。集計で混ざるので、名前を分けてください。"
        case .notANumber(let line, let cell):
            "\(line)行目：「\(cell)」を点数として読めません。"
        case .tooManyScores(let line):
            "\(line)行目：名前の数より点数が多くなっています。"
        case .noRounds(let line):
            "\(line)行目の名前の下に、点数の行がありません。"
        }
    }
}
