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
    @State private var justSaved = false
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
        .task {
            // 前回の続きがあればここで復元される
            board.attach(context: context)
        }
        .overlay(alignment: .top) {
            if justSaved {
                Text("保存しました")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Palette.accentInk)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Palette.accent, in: Capsule())
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: justSaved)
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
            HStack(spacing: 14) {
                // テンキーを閉じたあと開き直すための入口
                if !board.isKeypadVisible {
                    Button {
                        board.isKeypadVisible = true
                    } label: {
                        Image(systemName: "keyboard")
                    }
                }
                Button {
                    board.archiveCurrentGame()
                    justSaved = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.6))
                        justSaved = false
                    }
                } label: {
                    Image(systemName: "square.and.arrow.down")
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
