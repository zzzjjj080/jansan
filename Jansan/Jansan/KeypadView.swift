import SwiftUI

struct KeypadView: View {
    let board: ScoreBoard

    private let keyHeight: CGFloat = 54
    private let spacing: CGFloat = 7

    var body: some View {
        VStack(spacing: spacing) {
            caption

            HStack(spacing: spacing) {
                // 左列は上から「−」「確定」「お休み」。確定は2段ぶんの高さ
                VStack(spacing: spacing) {
                    key("−", background: Palette.negative, foreground: .white, size: 23, weight: .heavy) {
                        board.pressMinus()
                    }
                    .frame(height: keyHeight)

                    key("確定", background: Palette.accent, foreground: Palette.accentInk, size: 17, weight: .bold) {
                        board.commit()
                    }
                    .frame(height: keyHeight * 2 + spacing)

                    key("お休み", background: Palette.toneA, foreground: Palette.toneAInk, size: 13.5, weight: .bold) {
                        board.pressRest()
                    }
                    .frame(height: keyHeight)
                }
                .frame(width: 70)

                VStack(spacing: spacing) {
                    ForEach([["7", "8", "9"], ["4", "5", "6"], ["1", "2", "3"]], id: \.self) { row in
                        HStack(spacing: spacing) {
                            ForEach(row, id: \.self) { digit in
                                digitKey(digit)
                            }
                        }
                        .frame(height: keyHeight)
                    }
                    HStack(spacing: spacing) {
                        digitKey("0")
                        // 入力中の数字が無いときは、マスの中身そのものを消す役割になる
                        key(
                            board.backspaceClearsCell ? "クリア" : "⌫",
                            background: board.backspaceClearsCell ? Palette.lastTint : Palette.toneB,
                            foreground: board.backspaceClearsCell ? Palette.negative : Palette.toneBInk,
                            size: board.backspaceClearsCell ? 13.5 : 17,
                            weight: .bold
                        ) {
                            board.pressBackspace()
                        }
                        key("閉じる", background: Palette.toneC, foreground: Palette.toneCInk, size: 13.5, weight: .heavy) {
                            board.closeKeypad()
                        }
                    }
                    .frame(height: keyHeight)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .background(Palette.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(Palette.line).frame(height: 0.5)
        }
    }

    /// 打つ前は選択中の人の名前、打ち始めたら入力中の数字
    private var caption: some View {
        Text(board.keypadCaption)
            .font(.system(
                size: board.isCaptionPlaceholder ? 13 : 24,
                weight: board.isCaptionPlaceholder ? .semibold : .heavy
            ))
            .monospacedDigit()
            .foregroundStyle(captionColor)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 30)
    }

    private var captionColor: Color {
        if board.isCaptionPlaceholder { return Palette.inkDim }
        return board.isEnteringNegative ? Palette.negative : Palette.accent
    }

    private func digitKey(_ digit: String) -> some View {
        key(digit, background: Palette.keyBg, foreground: Palette.ink, size: 19, weight: .semibold) {
            board.press(digit: digit)
        }
    }

    private func key(
        _ title: String,
        background: Color,
        foreground: Color,
        size: CGFloat,
        weight: Font.Weight,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: size, weight: weight))
                .monospacedDigit()
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(KeyButtonStyle())
    }
}

/// 押した瞬間に軽く縮むだけの控えめな演出
private struct KeyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
