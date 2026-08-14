import SwiftUI
import JansanCore

struct ExportView: View {
    let board: ScoreBoard
    @Environment(\.dismiss) private var dismiss
    @State private var didCopy = false

    private var text: String { board.session.csv() }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Text("現在の表をCSVにしています。コピーしてメモやスプレッドシートに貼り付けたり、そのまま共有できます。")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.inkDim)
                    .frame(maxWidth: .infinity, alignment: .leading)

                ScrollView([.vertical, .horizontal]) {
                    Text(text)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Palette.ink)
                        .textSelection(.enabled)
                        .padding(12)
                }
                // 中央寄せだと読みにくいので左上に貼り付ける
                .defaultScrollAnchor(.topLeading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 12))

                HStack(spacing: 10) {
                    Button {
                        UIPasteboard.general.string = text
                        didCopy = true
                        Task {
                            try? await Task.sleep(for: .seconds(1.6))
                            didCopy = false
                        }
                    } label: {
                        Label(didCopy ? "コピーしました" : "コピー", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    // メール・メモ・AirDropなど、送り先は共有シートに任せる
                    ShareLink(item: text, subject: Text("雀算 スコア")) {
                        Label("共有", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .font(.system(size: 14, weight: .bold))
            }
            .padding(16)
            .navigationTitle("書き出し（CSV）")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}
