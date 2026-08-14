import SwiftUI
import JansanCore

// 配線確認用の仮画面。次のステップで本物の表とテンキーに差し替える。
struct ContentView: View {
    private let session: Session = {
        var session = Session(players: ["中村", "五十嵐", "斎藤", "佐々木"])
        session.enter(-32, at: Position(round: 0, column: 0))
        session.enter(71, at: Position(round: 0, column: 1))
        session.enter(-50, at: Position(round: 0, column: 2))
        return session
    }()

    var body: some View {
        VStack(spacing: 12) {
            Text("雀算")
                .font(.title2.bold())

            Text("JansanCore 接続確認")
                .font(.caption)
                .foregroundStyle(.secondary)

            Grid(horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    ForEach(session.players, id: \.self) { name in
                        Text(name).font(.caption.bold())
                    }
                }
                GridRow {
                    ForEach(Array(session.rounds[0].entries.enumerated()), id: \.offset) { _, entry in
                        Text(entry.value.map { ScoreFormatter.string($0, decimalMode: false) } ?? "·")
                            .monospacedDigit()
                    }
                }
            }
            .padding(.top, 8)

            // 4人目は入力せず、合計0から逆算されているはず
            Text(session.rounds[0].entries[3] == .derived(11) ? "逆算 OK" : "逆算 NG")
                .font(.headline)
                .foregroundStyle(session.rounds[0].entries[3] == .derived(11) ? .green : .red)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
