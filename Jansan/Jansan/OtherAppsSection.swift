import SwiftUI

/// 設定のいちばん下に置く、作者の他のアプリへの1行。
///
/// **投げ銭（App内課金）を外した跡地**（2026-09-30 本人判断）。
/// お金の入り口は置かないが、他に作ったものを知ってもらう道は残す
struct OtherAppsSection: View {
    private let url = URL(string: "https://apps.apple.com/jp/developer/jin-nakamura/id6802013586")!

    var body: some View {
        Section {
            Link(destination: url) {
                HStack {
                    Label("作者の他のアプリ", systemImage: "square.grid.2x2")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("otherApps")
        } footer: {
            Text("App Store の作者のページが開きます。")
        }
    }
}
