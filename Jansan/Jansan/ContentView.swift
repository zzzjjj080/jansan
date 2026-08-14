import SwiftUI
import JansanCore

struct ContentView: View {
    @State private var board = ScoreBoard(
        roster: Roster(
            names: ["中村", "五十嵐", "斎藤", "佐々木", "石井", "小野寺"],
            activeCount: 4
        )
    )
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var showStats = false
    @State private var showExport = false
    @Environment(\.modelContext) private var context

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
        .sheet(isPresented: $showSettings) {
            SettingsView(board: board, showHistory: $showHistory)
        }
        .sheet(isPresented: $showHistory) {
            HistoryView(board: board)
        }
        .sheet(isPresented: $showStats) {
            StatsView(board: board)
        }
        .sheet(isPresented: $showExport) {
            ExportView(board: board)
        }
        .task {
            // 前回の続きがあればここで復元される
            board.attach(context: context)
        }
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
            // テンキーを閉じてもマスをタップすれば開くので、開き直すボタンは置かない
            HStack(spacing: 18) {
                Button {
                    showStats = true
                } label: {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                }
                Button {
                    showExport = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                }
            }
            .font(.system(size: 17))
            .foregroundStyle(Palette.accent)
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
