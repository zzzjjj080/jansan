import SwiftUI
import SwiftData

/// 設定の「共有の更新を知らせる」。受け取っているフォルダに記録が足されたら通知を出す
struct ShareNotifySection: View {
    @Environment(\.modelContext) private var context
    @AppStorage(ShareNotifier.enabledKey) private var enabled = true

    var body: some View {
        Section {
            Toggle("共有の更新を知らせる", isOn: $enabled)
                .accessibilityIdentifier("notifyShareUpdates")
                .onChange(of: enabled) {
                    // オンにしたら頼み直し、オフにしたら取り消す
                    Task { await ShareNotifier.syncAll(in: context) }
                }
        } header: {
            Text("共有")
        } footer: {
            Text("・他の人から受け取っているフォルダに記録が足されると、通知でお知らせします\n・iCloudにサインインしている端末で届きます\n・最初に受け取ったときに、通知の許可をたずねます")
        }
    }
}
