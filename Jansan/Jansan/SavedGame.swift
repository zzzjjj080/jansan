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
/// **すべての属性に既定値を持たせてある。** CloudKit と同期する SwiftData の
/// モデルは、必須の属性（既定値も省略値も無い属性）を持てない。
/// 1つでも欠けると起動時にコンテナの初期化が失敗し、**アプリが立ち上がらなくなる。**
@Model
final class SavedGame {
    var savedAt: Date = Date.distantPast
    var isDraft: Bool = false
    var playerNames: [String] = [String]()
    var totals: [Int] = [Int]()
    /// 実際に打った局数。既存の記録との互換のため既定値を持たせる
    var roundCount: Int = 0
    /// 保存した時点の小数点モード。現在の設定で解釈すると10倍に見えてしまうため一緒に残す
    var decimalMode: Bool = false
    var payload: Data = Data()

    /// 取り込みの重複判定に使う安定したID。
    /// 既存の記録にも自動で1つ入る（それぞれ別のUUIDになるので判定に使える）
    var uid: UUID = UUID()

    /// 対局した日。
    ///
    /// **`savedAt`（保存日時）とは別物。** 後日まとめて入力すると保存日時が
    /// 実際の対局日とズレるため、こちらだけ編集できるようにしてある。
    /// 既存の記録は nil で入ってくるので、そのときは savedAt を使う。
    var playedAt: Date?

    /// ひとことメモ。場所・面子・その日の出来事など
    var note: String = ""

    /// 表示や集計に使う対局日。未設定なら保存日時で代用する
    var effectivePlayedAt: Date { playedAt ?? savedAt }

    init(snapshot: GameSnapshot, isDraft: Bool, savedAt: Date = .now,
         playedAt: Date? = nil, note: String = "", uid: UUID = UUID()) throws {
        self.savedAt = savedAt
        self.playedAt = playedAt
        self.note = note
        self.uid = uid
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
        effectivePlayedAt.formatted(
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

    /// 検索の対象。名前・メモ・日付をまとめて1本の文字列にしておく。
    /// 部分一致で引ければ十分なので、項目ごとの検索は作らない
    var searchText: String {
        ([dateLabel, shapeLabel, note] + playerNames).joined(separator: " ").lowercased()
    }

    /// 保存した日時。対局日と違うことを示すために編集画面へ出す
    var savedAtLabel: String {
        savedAt.formatted(
            .dateTime.year().month(.twoDigits).day(.twoDigits)
                .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
                .locale(Locale(identifier: "ja_JP"))
        )
    }

    /// 日付だけの表記。対局日の編集欄に出す
    var playedDayLabel: String {
        effectivePlayedAt.formatted(
            .dateTime.year().month().day().locale(Locale(identifier: "ja_JP"))
        )
    }

    /// 対局日を手で変えたかどうか。保存日時と違うときだけ画面に添える
    var hasCustomPlayedAt: Bool {
        guard let playedAt else { return false }
        return !Calendar.current.isDate(playedAt, inSameDayAs: savedAt)
    }

    /// 「中村 +12.3 / 五十嵐 -8.0」のような一覧用の1行
    var summaryLine: String {
        zip(playerNames, totals)
            .map { "\($0) \(ScoreFormatter.signedString($1, decimalMode: decimalMode))" }
            .joined(separator: " / ")
    }
}
