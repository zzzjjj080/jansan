import SwiftUI
import SwiftData
import JansanCore

/// 「入力」タブ。表とテンキー。
struct ContentView: View {
    let board: ScoreBoard
    @Binding var appTheme: AppTheme
    /// 記録タブへ移る。保存したあとの導線に使う
    var goToRecords: () -> Void = {}

    @State private var showSettings = false
    @State private var showStats = false
    @State private var showExport = false
    @State private var didSave = false
    @AppStorage("currentDirectory") private var currentDirectoryID = Directory.defaultUID.uuidString
    @Query private var directories: [Directory]
    /// 初回だけ自動で出す。以後は設定の「使い方」から
    @AppStorage("didShowHowTo") private var didShowHowTo = false
    @State private var showHowTo = false
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
        .preferredColorScheme(appTheme.colorScheme)
        .animation(.easeOut(duration: 0.2), value: board.isKeypadVisible)
        .sheet(isPresented: $showSettings) {
            SettingsView(board: board, appTheme: $appTheme)
        }
        .sheet(isPresented: $showStats) {
            StatsView(board: board)
        }
        .sheet(isPresented: $showExport) {
            ExportView(board: board)
        }
        .sheet(isPresented: $showHowTo) {
            HowToView()
        }
        .task {
            // 初回だけ使い方を出す。復元（RootView）より後に置いて、表が描けてから重ねる
            if !didShowHowTo {
                didShowHowTo = true
                showHowTo = true
            }
        }
    }

    private var appBar: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("雀算")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Palette.ink)
                Text("\(board.session.players.count)人打ち・\(board.session.rounds.count)局分表示中・保存先: \(currentDirectoryName)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.inkDim)
                    .lineLimit(1)
            }
            Spacer()
            // テンキーを閉じてもマスをタップすれば開くので、開き直すボタンは置かない
            HStack(spacing: 18) {
                // 戻せるものが無いときは薄く出す。消すと他のボタンの位置がずれて押し間違えるため
                Button {
                    board.undoLastChange()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(!board.canUndo)
                .opacity(board.canUndo ? 1 : 0.3)
                .accessibilityIdentifier("undo")
                .accessibilityLabel("取り消す")

                Button {
                    showStats = true
                } label: {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                }
                // 打ち終わったら押す。設定の奥にあったのを表のすぐ上に出した
                Button {
                    save()
                } label: {
                    Image(systemName: didSave ? "checkmark.circle.fill" : "square.and.arrow.down")
                }
                .accessibilityIdentifier("saveGame")
                .accessibilityLabel("この対局を記録に残す")
                .sensoryFeedback(.success, trigger: didSave) { _, new in new }
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                }
                .accessibilityIdentifier("openSettings")
                .accessibilityLabel("設定")
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

    private var currentDirectoryName: String {
        directories.first { $0.uid.uuidString == currentDirectoryID }?.name ?? Directory.defaultName
    }

    /// 保存先のディレクトリへ残す。消えてしまったディレクトリを指していたら「マイ記録」へ
    private func save() {
        let target = UUID(uuidString: currentDirectoryID)
        let exists = directories.contains { $0.uid == target && $0.isEditable }
        board.archiveCurrentGame(into: exists ? target : nil)
        if !exists { currentDirectoryID = Directory.defaultUID.uuidString }
        didSave = true
        // 共有中のディレクトリなら、その場で送る。失敗しても次の前面化で送り直す
        if let dir = directories.first(where: { $0.uid == target }), dir.isShared {
            Task { await SharePublisher.publish(dir, in: context) }
        }
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            didSave = false
        }
    }
}
