import SwiftUI

/// 初回に1枚だけ出す使い方。
///
/// **本格的なガイドは置かない。** テンキーが最初から開いていて「タップして入力」と
/// 出ているので、入力の仕方は触れば分かる。分からないのは次の3つだけだった。
///
/// - 名前を変えられること
/// - 人数を変えられること
/// - 「−」と「お休み」が何なのか
///
/// 初回に自動で出すが、設定の「使い方」からいつでも開き直せる。
/// 1度きりの案内は「読み飛ばしたら二度と読めない」ので、必ず戻り道を用意する。
struct HowToView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("点数は、マスをタップして数字キーで入れます。3人ぶん入れると、残りのひとりは合計が0になるように自動で入ります。")
                        .font(.subheadline)
                        .foregroundStyle(Palette.inkDim)
                        .padding(.bottom, 2)

                    row(
                        icon: "person.text.rectangle",
                        tint: Palette.accent,
                        title: "名前は変えられます",
                        body: "右上の歯車から「参加メンバー」を開いて、名前を打ち直してください。点数はそのまま残ります。"
                    )
                    row(
                        icon: "person.3.fill",
                        tint: Palette.accent,
                        title: "人数は3〜6人まで",
                        body: "同じ「参加メンバー」で、チェックを入れた人がそのまま表の列になります。5〜6人のときは、3人ぶん入れたあと実際に打った4人目をタップしてください。"
                    )
                    row(
                        icon: "minus",
                        tint: Palette.negative,
                        title: "「−」はマイナスの点数",
                        body: "数字を入れる前か後に押すと、符号が入れ替わります。もう一度押すと元に戻ります。"
                    )
                    row(
                        icon: "moon.zzz.fill",
                        tint: Palette.toneAInk,
                        title: "「お休み」は抜け番",
                        body: "その局を打たなかった人のマスに使います。0点とは区別され、平均や着順の計算からも外れます。"
                    )
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
