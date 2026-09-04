import Foundation
import SwiftData
import JansanCore

/// 保存の実体。
///
/// 2種類を1つのモデルで扱う:
/// - isDraft = true  … 入力途中の作業状態。常に1件だけ持ち、起動時に自動で復元する
/// - isDraft = false … 「保存」で明示的に残した記録。履歴として一覧に出る
///
/// 一覧表示に使う項目は普通のプロパティに出しておき、復元用の全体は payload に入れる。
@Model
final class SavedGame {
    var savedAt: Date
    var isDraft: Bool
    var playerNames: [String]
    var totals: [Int]
    /// 実際に打った局数。既存の記録との互換のため既定値を持たせる
    var roundCount: Int = 0
    /// 保存した時点の小数点モード。現在の設定で解釈すると10倍に見えてしまうため一緒に残す
    var decimalMode: Bool
    var payload: Data

    init(snapshot: GameSnapshot, isDraft: Bool, savedAt: Date = .now) throws {
        self.savedAt = savedAt
        self.isDraft = isDraft
        self.playerNames = snapshot.session.players
        self.totals = snapshot.session.totals
        self.roundCount = snapshot.session.playedRoundCount
        self.decimalMode = snapshot.session.decimalMode
        self.payload = try JSONEncoder().encode(snapshot)
    }

    func snapshot() throws -> GameSnapshot {
        try JSONDecoder().decode(GameSnapshot.self, from: payload)
    }

    /// 端末の言語設定に関係なく日本語表記にする。アプリのUIが日本語で統一されているため
    var dateLabel: String {
        savedAt.formatted(
            .dateTime
                .year().month(.twoDigits).day(.twoDigits)
                .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
                .locale(Locale(identifier: "ja_JP"))
        )
    }

    /// 「4人打ち・8局」のような見出し
    var shapeLabel: String {
        "\(playerNames.count)人打ち・\(roundCount)局"
    }

    /// 「中村 +12.3 / 五十嵐 -8.0」のような一覧用の1行
    var summaryLine: String {
        zip(playerNames, totals)
            .map { "\($0) \(ScoreFormatter.signedString($1, decimalMode: decimalMode))" }
            .joined(separator: " / ")
    }
}
