import SwiftUI
import JansanCore

/// 使い方。**文章を読ませない。** 実物と同じ絵を並べて、目で追えば分かるようにする。
///
/// 初回に自動で出し、以後は設定の「使い方」から開き直せる。
/// 1度きりの案内は「読み飛ばしたら二度と読めない」ので、必ず戻り道を用意する。
struct HowToView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    scoreEntry
                    topBar
                    flow
                    styles
                    sharing
                }
                .padding(18)
            }
            .background(Palette.bg)
            .navigationTitle("雀算の使い方")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }.bold()
                }
            }
        }
        .sensoryFeedback(.selection, trigger: true)
    }

    // MARK: - 1. 点数の入れ方

    private var scoreEntry: some View {
        block("点数を入れる", "最後のひとりは打たなくていい") {
            VStack(spacing: 10) {
                MiniTable(
                    players: ["中村", "五十嵐", "斎藤", "佐々木"],
                    values: ["-32", "71", "-50", "11"],
                    derivedColumn: 3
                )
                caption("3人ぶん入れると、合計が0になるよう残りが自動で入ります（薄い色のマス）")
            }
        }
    }

    // MARK: - 2. 上のボタン

    private var topBar: some View {
        block("上のボタン", nil) {
            VStack(spacing: 0) {
                iconRow(.floppy, "記録に残す", "打ち終わったらここ")
                divider
                iconRow(.symbol("folder.fill"), "保存先", "どのフォルダに残すかを選ぶ")
                divider
                iconRow(.text("四麻"), "打ち方", "三麻と四麻を切り替える")
                divider
                iconRow(.symbol("plus.rectangle.on.rectangle"), "新しい対局", "表を空にして次の半荘へ")
                divider
                iconRow(.symbol("gearshape.fill"), "設定", "メンバー・見た目・書き出し")
            }
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line))
        }
    }

    // MARK: - 3. 流れ

    private var flow: some View {
        block("残す・見る", nil) {
            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    step("入力", "tablecells")
                    arrow
                    step("保存", "externaldrive.fill")
                    arrow
                    step("記録", "folder.fill")
                    arrow
                    step("集計", "chart.line.uptrend.xyaxis")
                }
                caption("記録は「ディレクトリ」に分けられます。卓や面子ごとに分けると集計が混ざりません")
            }
        }
    }

    // MARK: - 4. 三麻と四麻

    private var styles: some View {
        block("三麻と四麻", "打つ人数と、集まった人数は別") {
            VStack(spacing: 0) {
                styleRow("集まった人数", "打ち方", "入れ方", isHeader: true)
                divider
                styleRow("3人", "三麻", "2人ぶんで自動")
                divider
                styleRow("4人", "四麻", "3人ぶんで自動")
                divider
                styleRow("4人", "三麻", "2人ぶん＋打った人をタップ")
                divider
                styleRow("5人", "四麻", "3人ぶん＋打った人をタップ")
            }
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line))
        }
    }

    // MARK: - 5. 共有

    private var sharing: some View {
        block("仲間と見る", "共有をオンにしたときだけ") {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    phone("自分", "共有する", Palette.accent)
                    VStack(spacing: 2) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .bold))
                        Text("ID・パスワード")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(Palette.inkDim)
                    phone("仲間", "IDで受け取る", Palette.toneCInk)
                }
                caption("相手は見るだけで、書き換えはできません。共有をオンにしない限り、点数が他の人に見えることはありません")
            }
        }
    }

    // MARK: - 部品

    private func block<Content: View>(_ title: String, _ subtitle: String?,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Palette.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.accent)
                }
            }
            content()
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Palette.inkDim)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var divider: some View {
        Rectangle().fill(Palette.line).frame(height: 0.5).padding(.leading, 52)
    }

    private enum Glyph {
        case symbol(String), text(String), floppy
    }

    private func iconRow(_ glyph: Glyph, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 12) {
            Group {
                switch glyph {
                case .symbol(let name):
                    Image(systemName: name).font(.system(size: 18, weight: .semibold))
                case .text(let label):
                    Text(label).font(.system(size: 13, weight: .heavy))
                case .floppy:
                    FloppySaveIcon(size: 18)
                }
            }
            .foregroundStyle(Palette.accent)
            .frame(width: 40)

            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 14, weight: .bold)).foregroundStyle(Palette.ink)
                Text(detail).font(.system(size: 12)).foregroundStyle(Palette.inkDim)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
        .padding(.trailing, 12)
        .accessibilityElement(children: .combine)
    }

    private func step(_ title: String, _ symbol: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: 40, height: 36)
                .background(Palette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
            Text(title).font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.ink)
        }
        .accessibilityElement(children: .combine)
    }

    private var arrow: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Palette.line)
            .accessibilityHidden(true)
    }

    private func styleRow(_ a: String, _ b: String, _ c: String, isHeader: Bool = false) -> some View {
        HStack(spacing: 0) {
            Text(a).frame(width: 86, alignment: .leading)
            Text(b).frame(width: 54, alignment: .leading)
            Text(c).frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: isHeader ? 11 : 12.5, weight: isHeader ? .bold : .medium))
        .foregroundStyle(isHeader ? Palette.inkDim : Palette.ink)
        .padding(.horizontal, 12)
        .padding(.vertical, isHeader ? 7 : 9)
        .background(isHeader ? Palette.surface2 : Color.clear)
        .accessibilityElement(children: .combine)
    }

    private func phone(_ title: String, _ action: String, _ tint: Color) -> some View {
        VStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 7)
                .stroke(tint, lineWidth: 1.5)
                .frame(width: 44, height: 64)
                .overlay {
                    Image(systemName: "tablecells")
                        .font(.system(size: 17))
                        .foregroundStyle(tint)
                }
            Text(title).font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.ink)
            Text(action).font(.system(size: 10)).foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// 使い方に出す小さな表。実物と同じ見え方にして、説明を短くする
private struct MiniTable: View {
    let players: [String]
    let values: [String]
    /// 自動で入ったマス。薄い色で示す
    let derivedColumn: Int

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(players.enumerated()), id: \.offset) { _, name in
                    Text(name)
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                }
            }
            .background(Palette.surface2)

            HStack(spacing: 0) {
                ForEach(Array(values.enumerated()), id: \.offset) { column, value in
                    Text(value)
                        .font(.system(size: 15, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(column == derivedColumn ? Palette.accent : Palette.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(column == derivedColumn ? Palette.accent.opacity(0.14) : Color.clear)
                }
            }
        }
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.line))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("表の例。中村 −32、五十嵐 71、斎藤 −50。佐々木の 11 は自動で入る")
    }
}

#Preview {
    HowToView()
}
