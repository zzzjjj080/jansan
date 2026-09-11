import SwiftUI

/// 初回に1枚だけ出す使い方。
///
/// **本格的なガイドは置かない。** テンキーが最初から開いていて「タップして入力」と
/// 出ているので、入力の仕方は触れば分かる。ここに書くのは、
/// **触っても気づけないこと**だけにする。
///
/// 初回に自動で出すが、設定の「使い方」からいつでも開き直せる。
/// 1度きりの案内は「読み飛ばしたら二度と読めない」ので、必ず戻り道を用意する。
struct HowToView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("点数は、マスをタップして数字キーで入れます。残りひとりは合計が0になるよう自動で入ります。")
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkDim)
                        .padding(.bottom, 2)

                    section("入力の画面")
                    row(icon: "folder.fill", tint: Palette.accent,
                        title: "保存先とメンバーは上で変える",
                        body: "上のフォルダを押すと、記録をどこに残すかを選べます。その隣で三麻・四麻と参加人数を切り替えられます。名前の変更は右端の歯車から。")
                    row(icon: "minus", tint: Palette.negative,
                        title: "「−」はマイナスの点数",
                        body: "数字を入れる前か後に押すと符号が入れ替わります。もう一度押すと戻ります。")
                    row(icon: "moon.zzz.fill", tint: Palette.toneAInk,
                        title: "「お休み」は抜け番",
                        body: "その局を打たなかった人に使います。0点とは区別され、平均や着順の計算からも外れます。")

                    section("残す・見る")
                    row(icon: "externaldrive.fill", tint: Palette.accent,
                        title: "打ち終わったら左上で保存",
                        body: "フロッピーのボタンで、その時点の表を記録に残します。記録は「ディレクトリ」に分けられるので、卓や面子ごとに分けておくと集計が混ざりません。")
                    row(icon: "chart.line.uptrend.xyaxis", tint: Palette.accent,
                        title: "集計と画像",
                        body: "「記録」に切り替えてディレクトリを開くと、期間や人数で絞った成績が見られます。そこから3枚の画像にして送れます。")

                    section("仲間と見る")
                    row(icon: "person.2.fill", tint: Palette.toneCInk,
                        title: "IDとパスワードで共有できる",
                        body: "ディレクトリごとに共有をオンにすると、IDとパスワードを知っている人が同じ記録を見られます。相手は見るだけで、書き換えはできません。共有をオンにしない限り、点数が他の人に見えることはありません。")
                    row(icon: "checkmark.icloud.fill", tint: Palette.accent,
                        title: "記録はiCloudに残る",
                        body: "端末が壊れても機種を変えても記録は消えません。設定の「バックアップ」から書き出して控えを取ることもできます。")
                }
                .padding(20)
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
        // 開いた瞬間に軽く鳴らす。初回の1枚なので、ここだけは気づいてほしい
        .sensoryFeedback(.selection, trigger: true)
    }

    private func section(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .bold))
            .kerning(0.5)
            .foregroundStyle(Palette.inkDim)
            .padding(.top, 4)
    }

    private func row(icon: String, tint: Color, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Palette.ink)
                Text(body)
                    .font(.footnote)
                    .foregroundStyle(Palette.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    HowToView()
}
