import SwiftUI
import JansanCore

struct ContentView: View {
    @State private var board = ScoreBoard(players: ["中村", "五十嵐", "斎藤", "佐々木"])

    var body: some View {
        VStack(spacing: 0) {
            appBar
            ScoreTableView(board: board)
                .padding(.horizontal, 10)
                .padding(.top, 10)
            if board.isKeypadVisible {
                KeypadView(board: board)
                    .transition(.move(edge: .bottom))
            }
        }
        .background(Palette.surface)
        .animation(.easeOut(duration: 0.2), value: board.isKeypadVisible)
    }

    private var appBar: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("雀算")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Palette.ink)
                Text("\(board.session.players.count)人打ち・\(board.session.rounds.count)局分表示中")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.inkDim)
            }
            Spacer()
            // テンキーを閉じたあと開き直すための入口。設定や書き出しは今後ここに並べる
            if !board.isKeypadVisible {
                Button("テンキー") { board.isKeypadVisible = true }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Palette.accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.line).frame(height: 0.5)
        }
    }
}

#Preview {
    ContentView()
}
