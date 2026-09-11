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
        case settings, howTo, export, pickDirectory
        var id: String { rawValue }
    }

    @State private var didSave = false
    @State private var saveConfirm = false
    @State private var newSessionConfirm = false
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
                .alert("新しい対局を始めますか", isPresented: $newSessionConfirm) {
                    Button("やめる", role: .cancel) {}
                    Button("記録に残して始める") { startNewSession(archive: true) }
                    Button("始める", role: .destructive) { startNewSession(archive: false) }
                } message: {
                    Text(newSessionMessage)
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

    /// 上の帯の高さ。**5つとも同じ高さに揃える。**
    /// 指の的としてはこれが下限（Apple の目安が44pt）。ここは削らず、
    /// 代わりに余白と記号の大きさを詰める
    private let barHeight: CGFloat = 44

    private var appBar: some View {
        HStack(spacing: 4) {
            // いちばん左が保存。その隣に保存先。「残す」「どこに」が並ぶ
            Button {
                saveConfirm = true
            } label: {
                Group {
                    if didSave {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 21, weight: .semibold))
                    } else {
                        FloppySaveIcon(size: 21)
                    }
                }
                .foregroundStyle(Palette.accent)
                .frame(width: 44, height: barHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("saveGame")
            .accessibilityLabel("この対局を記録に残す")
            .sensoryFeedback(.success, trigger: didSave) { _, new in new }

            // 保存先は「表示」と「変更ボタン」を1つにする。
            // 別々にすると、そこで変えられることに気づかない
            Button {
                sheet = .pickDirectory
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 15, weight: .semibold))
                    Text(currentDirectoryName)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(Palette.accent)
                .padding(.horizontal, 9)
                .frame(height: barHeight)
                .background(Palette.accent.opacity(0.12), in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("pickDirectory")
            .accessibilityLabel("保存先: \(currentDirectoryName)")
            .accessibilityHint("タップすると保存先を変えられます")
            // ボタンが増えて幅が足りなくなると、まず保存先の名前が潰れる。
            // 名前が読めないと何に入るのか分からないので、ここを最優先で残す
            .layoutPriority(2)

            // 打ち方（三麻／四麻）だけをここで切り替える。
            // 参加人数は毎回変えるものではないので、設定の「メンバー登録」に置く
            Menu {
                // 打ち方だけ。参加人数は設定の「メンバー登録」で決める
                ForEach(Session.playersPerRoundChoices, id: \.self) { count in
                    Button {
                        board.setPlayersPerRound(count)
                    } label: {
                        Label(Self.styleName(count),
                              systemImage: board.playersPerRound == count ? "checkmark" : "")
                    }
                    .disabled(count > board.session.players.count)
                }
            } label: {
                HStack(spacing: 4) {
                    Text(playStyleCaption)
                        .font(.system(size: 15, weight: .bold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(Palette.accent)
                .padding(.horizontal, 8)
                .frame(height: barHeight)
                .background(Palette.accent.opacity(0.12), in: Capsule())
                .contentShape(Capsule())
            }
            .accessibilityIdentifier("playStyle")
            .accessibilityLabel("\(playStyleCaption)。タップで三麻と四麻を切り替えられます")
            .layoutPriority(1)

            Spacer(minLength: 0)

            // 右は「次へ」と「設定」。集計はディレクトリごとに見るので、
            // 入力中の表だけのグラフは置かない（フォルダを開いて見る）
            // 時計回りの矢印は「やり直す」にも読めた。新しい表が出ることを絵で出す
            barButton("plus.rectangle.on.rectangle", id: "newSession",
                      label: "新しい対局を始める") {
                newSessionConfirm = true
            }

            barButton("gearshape.fill", id: "openSettings", label: "設定") {
                sheet = .settings
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.line).frame(height: 0.5)
        }
    }

    /// 上のボタン。**指で押す的を44pt角にする。**
    /// 以前は17ptの記号そのものが的で、狙って外すことがあった
    private func barButton(_ symbol: String, id: String, label: String,
                           filled: Bool = false,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: filled ? "checkmark.circle.fill" : symbol)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: 44, height: barHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityLabel(label)
    }

    /// 打ち方の呼び方。**三麻・四麻が一般的**なのでそちらに合わせる
    static func styleName(_ playersPerRound: Int) -> String {
        switch playersPerRound {
        case 3: "三麻"
        case 4: "四麻"
        default: "\(playersPerRound)人打ち"
        }
    }

    /// 上に出す見出し。参加人数が打つ人数と同じなら打ち方だけでよい。
    /// 多いときは「四麻・5人」のように並べて、毎局ひとり抜けることが分かるようにする
    private var playStyleCaption: String {
        let style = Self.styleName(board.playersPerRound)
        let participants = board.session.players.count
        return participants == board.playersPerRound ? style : "\(style)・\(participants)人"
    }

    private var newSessionMessage: String {
        let rounds = board.session.playedRoundCount
        guard rounds > 0 else { return "いまの表はまだ空です。そのまま新しい対局を始められます。" }
        return "いまの表（\(board.session.players.count)人打ち・\(rounds)局）は消えます。"
            + "念のため「\(Directory.autoBackupName)」に控えを取るので、押し間違えても記録から戻せます。"
    }

    /// 新しい対局を始める。**消える前に必ず控えを取る。**
    /// 普通は保存してから始めるが、押し間違えたときの戻り道が要る
    private func startNewSession(archive: Bool) {
        DirectoryStore.autoBackup(board.currentSnapshot, in: context)
        if archive { save() }
        board.resetSession()
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
