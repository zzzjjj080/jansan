import Testing
import Foundation
@testable import JansanCore

@Suite("自動バックアップの保存期間")
struct AutoBackupRetentionTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    @Test("1か月以内の控えは残す")
    func keepsWithinAMonth() {
        let now = date(2026, 9, 14)
        #expect(!AutoBackupRetention.isExpired(savedAt: date(2026, 9, 13), now: now, calendar: calendar))
        #expect(!AutoBackupRetention.isExpired(savedAt: date(2026, 8, 15), now: now, calendar: calendar))
    }

    @Test("ちょうど1か月のものは残し、それより前は消す")
    func boundary() {
        let now = date(2026, 9, 14)
        #expect(!AutoBackupRetention.isExpired(savedAt: date(2026, 8, 14), now: now, calendar: calendar))
        #expect(AutoBackupRetention.isExpired(savedAt: date(2026, 8, 14, 11), now: now, calendar: calendar))
        #expect(AutoBackupRetention.isExpired(savedAt: date(2026, 7, 1), now: now, calendar: calendar))
    }

    @Test("日数ではなく暦の1か月で数える（3月末から見た2月）")
    func calendarMonth() {
        // 3/31 の1か月前は 2/28。30日前（3/1）ではない
        let now = date(2026, 3, 31)
        #expect(!AutoBackupRetention.isExpired(savedAt: date(2026, 2, 28), now: now, calendar: calendar))
        #expect(AutoBackupRetention.isExpired(savedAt: date(2026, 2, 27), now: now, calendar: calendar))
    }
}
