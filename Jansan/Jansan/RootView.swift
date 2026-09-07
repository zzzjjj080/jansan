import SwiftUI
import SwiftData
import JansanCore

/// アプリの入口。「入力」と「記録」の2タブ。
///
/// **起動時に選ばせる画面は置かない。** 雀算を開く場面の9割は卓で点数を入れるときで、
/// いちばん多い動作の手前に関所を置きたくない。起動したら表が出て、記録は1タップ隣。
///
/// 「他の人の記録を見る」は3つ目のタブにしない。記録タブの中で、自分のディレクトリと
/// 受け取ったディレクトリが同じ形で並ぶ。
struct RootView: View {
    /// 表の状態は両タブで共有する。記録タブから「読み込む」と入力タブの表が変わるため
    @State private var board = ScoreBoard(
        roster: Roster(
            names: ["中村", "五十嵐", "斎藤", "佐々木", "石井", "小野寺"],
            activeCount: 4
        )
    )
    @AppStorage("appTheme") private var appTheme = AppTheme.system
    /// 起動時は必ず「入力」。前回のタブを覚えない。
    /// 卓で開いたときに記録タブから始まると、まず戻す操作が要る
    @State private var selectedTab = Tab.input
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    enum Tab: String {
        case input, records
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            // タブの中身に accessibilityIdentifier を付けてはいけない。
            // 子孫のボタン全部の識別子がそれで上書きされ、UIテストが何も見つけられなくなる
            ContentView(board: board, appTheme: $appTheme, goToRecords: { selectedTab = .records })
                .tabItem { Label("入力", systemImage: "square.grid.3x3.topleft.filled") }
                .tag(Tab.input)

            RecordsView(board: board, goToInput: { selectedTab = .input })
                .tabItem { Label("記録", systemImage: "books.vertical.fill") }
                .tag(Tab.records)
        }
        .tint(Palette.accent)
        .preferredColorScheme(appTheme.colorScheme)
        // タブを切り替えたときの手応え。全アプリ共通のルール
        .sensoryFeedback(.selection, trigger: selectedTab)
        .task {
            // 「マイ記録」は必ずある状態にしてから画面を出す
            DirectoryStore.ensureDefault(in: context)
            board.attach(context: context)
            await SharePublisher.publishPending(in: context)
        }
        // オフラインで保存した分は、次に前面に来たときに送る
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await SharePublisher.publishPending(in: context) }
            }
        }
    }
}
