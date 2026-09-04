//
//  JansanApp.swift
//  Jansan
//
//  Created by jin on 2026/08/14.
//

import SwiftUI
import SwiftData

@main
struct JansanApp: App {
    /// 保存先。**iCloudに同期する。**
    ///
    /// 端末が壊れたり機種を変えたりしても記録が消えないようにするため。
    /// 送り先は利用者自身のiCloudの**プライベートデータベース**で、
    /// 開発者からも他の利用者からも見えない。
    ///
    /// **CloudKitと同期するモデルは、必須の属性を持てない。**
    /// 1つでも既定値の無い属性があるとコンテナの初期化に失敗し、
    /// アプリが起動しなくなる（→ SavedGame）。
    ///
    /// iCloudにサインインしていない端末でも、同期しないだけで普通に動く。
    /// **そこで失敗しても記録を触れなくするわけにはいかない**ので、
    /// 初期化に失敗したら端末内だけの保存に切り替えて起動を続ける。
    /// iCloud同期を使うかどうか。
    ///
    /// **`Jansan.xcodeproj` の `CODE_SIGN_ENTITLEMENTS` と必ず対で切り替える。**
    /// 片方だけ変えると、同期しないのに CloudKit のエラーがログに出続けるか、
    /// エンタイトルメントがあるのに同期しないかのどちらかになる。
    ///
    /// **いまは false。** CloudKitコンテナ `iCloud.com.zzzjjj080.Jansan` が
    /// まだ Apple 側に作られていないため。コンテナの作成は App Store Connect API に
    /// 口が無く、Xcode か developer.apple.com からしか作れない（引き継ぎ書 4-28）。
    /// 作られたら、ここと `CODE_SIGN_ENTITLEMENTS` を同時に戻す。
    private static let useICloudSync = false

    /// 保存先。
    ///
    /// **CloudKitと同期するモデルは、必須の属性を持てない。**
    /// 1つでも既定値の無い属性があるとコンテナの初期化に失敗し、
    /// アプリが起動しなくなる（→ SavedGame）。
    ///
    /// 同期を切っていても、切り替えたときにそのまま動くよう、
    /// モデル側の制約は満たしたままにしてある。
    private let container: ModelContainer = {
        let schema = Schema([SavedGame.self])

        func make(_ database: ModelConfiguration.CloudKitDatabase) throws -> ModelContainer {
            try ModelContainer(for: schema,
                               configurations: ModelConfiguration(schema: schema, cloudKitDatabase: database))
        }

        // iCloudにサインインしていない端末でも、同期しないだけで普通に動く。
        // **そこで失敗して記録を触れなくするわけにはいかない**ので、必ず端末内保存へ落とす
        if useICloudSync, let container = try? make(.automatic) {
            return container
        }
        do {
            return try make(.none)
        } catch {
            fatalError("保存先を用意できませんでした: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
