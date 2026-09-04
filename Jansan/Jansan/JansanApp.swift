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
    /// コンテナ `iCloud.com.zzzjjj080.Jansan` は 2026-09-05 に作成済み。
    /// コンテナの作成だけは App Store Connect API に口が無く、
    /// Xcode か developer.apple.com からしか作れない（引き継ぎ書 4-70b）。
    private static let useICloudSync = true

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
            CloudStatus.isSyncing = true
            return container
        }
        do {
            CloudStatus.isSyncing = false
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


/// iCloudに同期しているかどうか。
///
/// 利用者から見て「自分の記録が守られているか」は知りたいことなので、
/// 設定に出す。**同期が始まっているかを外から確かめる手段が他に無い**ため、
/// 開発中の確認にもここを使う。
enum CloudStatus {
    /// 保存先を用意した時点で決まる。以後は変わらない
    nonisolated(unsafe) static var isSyncing = false

    static var label: String {
        isSyncing ? "iCloudに同期しています" : "この端末にのみ保存しています"
    }

    static var detail: String {
        isSyncing
            ? "記録はお使いのiCloudにも保存されます。端末が壊れても、機種を変えても残ります。保存先はあなた専用の領域で、開発者からも他の利用者からも見えません。"
            : "iCloudにサインインしていないか、同期が使えない状態です。記録はこの端末の中だけにあります。端末を失うと記録も失われるので、「バックアップ」から書き出して控えておくことをおすすめします。"
    }

    static var symbol: String {
        isSyncing ? "checkmark.icloud.fill" : "icloud.slash"
    }
}
