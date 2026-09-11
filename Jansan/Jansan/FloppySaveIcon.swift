import SwiftUI

/// 昔ながらのフロッピーディスク（保存）のアイコン。
///
/// **SF Symbols にフロッピーは無い**ので自分で描く。
/// 穴（シャッターとラベル）は塗りを抜いて作るので、どんな地の色の上でも成り立つ。
struct FloppySaveIcon: View {
    var size: CGFloat = 21

    var body: some View {
        ZStack {
            body_
                .frame(width: size, height: size)

            // 上のシャッター。右に寄せるのが実物の見え方
            Rectangle()
                .frame(width: size * 0.30, height: size * 0.26)
                .offset(x: size * 0.05, y: -size * 0.30)
                .blendMode(.destinationOut)

            // 下のラベル
            RoundedRectangle(cornerRadius: size * 0.04)
                .frame(width: size * 0.54, height: size * 0.30)
                .offset(y: size * 0.26)
                .blendMode(.destinationOut)
        }
        .compositingGroup()
        .frame(width: size, height: size)
    }

    /// 本体。右上の角を斜めに落とすのがフロッピーらしさ
    private var body_: some View {
        Path { p in
            let s = size
            let r = s * 0.11        // 角丸
            let cut = s * 0.24      // 右上の欠き
            p.move(to: CGPoint(x: r, y: 0))
            p.addLine(to: CGPoint(x: s - cut, y: 0))
            p.addLine(to: CGPoint(x: s, y: cut))
            p.addLine(to: CGPoint(x: s, y: s - r))
            p.addQuadCurve(to: CGPoint(x: s - r, y: s), control: CGPoint(x: s, y: s))
            p.addLine(to: CGPoint(x: r, y: s))
            p.addQuadCurve(to: CGPoint(x: 0, y: s - r), control: CGPoint(x: 0, y: s))
            p.addLine(to: CGPoint(x: 0, y: r))
            p.addQuadCurve(to: CGPoint(x: r, y: 0), control: CGPoint(x: 0, y: 0))
            p.closeSubpath()
        }
    }
}

#Preview {
    HStack(spacing: 20) {
        FloppySaveIcon(size: 21)
        FloppySaveIcon(size: 40)
        FloppySaveIcon(size: 80)
    }
    .foregroundStyle(.green)
    .padding()
}
