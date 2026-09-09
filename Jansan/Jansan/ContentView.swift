import SwiftUI
import SwiftData
import JansanCore

/// 「入力」タブ。表とテンキー。
struct ContentView: View {
    let board: ScoreBoard
    @Binding var appTheme: AppTheme
    /// 記録タブへ移る。保存したあとの導線に使う
    var goToRecords: () -> Void = {}

    /// **1つの view に .sheet を何枚も重ねない。**
    /// 重ねると、あるものを出そうとしたのに中身が空のシートが出ることがある
    /// （確認ダイアログを足した時点で実際に起きた）。出すものを1つの値で持つ
    @State private var sheet: SheetKind?

    private enum SheetKind: String, Identifiable {
        case settings, stats, howTo, export, pickDirectory
        var id: String { rawValue }
    }

    @State private var didSave = false
    @State private var saveConfirm = false
    @AppStorage("currentDirectory") private var currentDirectoryID = Directory.defaultUID.uuidString
    @Query private var directories: [Directory]
    /// 初回だけ自動で出す。以後は設定の「使い方」から
    @AppStorage("didShowHowTo") private var didShowHowTo = false
    @Environment(\.modelContext) private var context

    var body: some View {
        VStack(spacing: 0) {
            // **確認ダイアログはシートと同じ view に付けない。**
            // 同じ chain に置くと、ダイアログを閉じたあとシートが開かなくなる
            // （設定が二度と開かず、UIテストで再現した）。付け先を分ける
            appBar
                // **confirmationDialog は使わない。** 小さい view に付けると
                // ポップオーバーになり、「やめる」が消えてタップで閉じるしかなくなる。
                // alert なら iPhone では必ず中央に2つのボタンが出る
                .alert("この対局を記録に残しますか", isPresented: $saveConfirm) {
                    Button("やめる", role: .cancel) {}
                    Button("「\(currentDirectoryName)」に残す") { save() }
                } message: {
                    Text(saveMessage)
                }
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
        .sheet(item: $sheet) { kind in
            switch kind {
            case .settings: SettingsView(board: board, appTheme: $appTheme)
            case .stats:    StatsView(board: board)
            case .howTo:    HowToView()
            case .export:   ExportView(board: board)
            case .pickDirectory: DirectoryPickerView()
            }
        }
        .task {
            // 初回だけ使い方を出す。復元（RootView）より後に置いて、表が描けてから重ねる
            if !didShowHowTo {
                didShowHowTo = true
                sheet = .howTo
            }
        }
    }

    private var appBar: some View {
        VStack(spacing: 6) {
            // 1段目は文字だけ。2段目をボタン専用にして、指の的を大きく取る
            HStack(spacing: 6) {
                Text("\(board.session.players.count)人打ち")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Palette.ink)
                Text("・")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.line)
                Text("保存先: \(currentDirectoryName)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.inkDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)

            HStack(spacing: 0) {
                // いちばん左が保存先の変更、その右が保存。よく使う2つを端に置く
                barButton("folder.fill", id: "pickDirectory", label: "保存先を変える") {
                    sheet = .pickDirectory
                }
                barButton(didSave ? "checkmark.circle.fill" : "arrow.up.folder.fill",
                          id: "saveGame", label: "この対局を記録に残す") {
                    saveConfirm = true
                }
                .sensoryFeedback(.success, trigger: didSave) { _, new in new }

                Spacer(minLength: 0)

                // 戻せるものが無いときは薄く出す。消すと他のボタンの位置がずれて押し間違えるため
                barButton("arrow.uturn.backward", id: "undo", label: "取り消す") {
                    board.undoLastChange()
                }
                .disabled(!board.canUndo)
                .opacity(board.canUndo ? 1 : 0.3)

                barButton("chart.line.uptrend.xyaxis", id: "openStats", label: "ビュー") {
                    sheet = .stats
                }

                barButton("gearshape.fill", id: "openSettings", label: "設定") {
                    sheet = .settings
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.line).frame(height: 0.5)
        }
    }

    /// 上のボタン。**指で押す的を44pt角にする。**
    /// 以前は17ptの記号そのものが的で、狙って外すことがあった
    private func barButton(_ symbol: String, id: String, label: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: 54, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityLabel(label)
    }

    /// 保存先が共有中なら、相手に届くことまで書く。
    /// 「入れたつもりが人に見られていた」を起こさないため
    private var saveMessage: String {
        let rounds = board.session.playedRoundCount
        let base = "\(board.session.players.count)人打ち・\(rounds)局を「\(currentDirectoryName)」に残します。"
        guard let dir = currentDirectory, dir.isShared else {
            return base + "入力中の表はそのまま続けられます。"
        }
        return base + "このディレクトリは共有中（ID: \(dir.shareID)）なので、受け取っている人にも届きます。"
    }

    private var currentDirectory: Directory? {
        directories.first { $0.uid.uuidString == currentDirectoryID }
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
