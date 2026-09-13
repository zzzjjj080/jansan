import Foundation

/// 「自動バックアップ」の控えをいつまで残すか。
///
/// **記録されてから1か月たったら消す**（本人の指示）。控えは押し間違えたときに戻すためのもので、
/// 1か月も気づかなければもう要らない。日数（30日）ではなく暦の1か月で数える。
public enum AutoBackupRetention {

    /// 控えを残す期間（月）
    public static let months = 1

    /// この日時までに記録された控えは消す
    public static func cutoff(now: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .month, value: -months, to: now) ?? now
    }

    /// 消す控えか。ちょうど1か月のものは残す
    public static func isExpired(savedAt: Date, now: Date, calendar: Calendar = .current) -> Bool {
        savedAt < cutoff(now: now, calendar: calendar)
    }
}
