import Foundation
import SwiftData
import JansanCore

/// 取り込んだ対局を記録として入れる。**貼り付けからでも写真からでも同じ入れ方**にする。
///
/// 日付は「日付未記入」で入る（写真やCSVからは日付が分からない）。あとから記録の編集で入れられる
enum ImportCommit {

    @MainActor
    @discardableResult
    static func insert(_ games: [CSVImportedGame], into directory: Directory,
                       in context: ModelContext) -> Int {
        var inserted = 0
        let now = Date.now
        for game in games {
            // 一覧は保存日時の新しい順。入れた順に上から並ぶよう、1秒ずつ前にずらす
            guard let record = try? SavedGame(snapshot: game.snapshot, isDraft: false,
                                              savedAt: now.addingTimeInterval(-Double(inserted)),
                                              playedAt: PlayedDate.unknown) else { continue }
            record.directoryId = directory.uid
            context.insert(record)
            inserted += 1
        }
        if inserted > 0, directory.isShared {
            directory.needsPublish = true
            directory.updatedAt = .now
        }
        try? context.save()
        return inserted
    }
}
