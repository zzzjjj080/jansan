import SwiftUI

// プロトタイプ(HTML)のCSS変数をそのまま持ってきた配色。
// ライト/ダークの切り替えはOS任せにできるので、Web版のような手動のテーマ監視は要らない。
enum Palette {
    static let bg = adaptive(0xF5_F3_EE, 0x10_12_10)
    static let surface = adaptive(0xFF_FF_FF, 0x18_1B_17)
    static let surface2 = adaptive(0xEE_ED_E9, 0x1D_1F_1C)
    static let ink = adaptive(0x1C_21_1D, 0xEE_F1_EA)
    static let inkDim = adaptive(0x6B_75_68, 0x8B_94_88)
    static let line = adaptive(0xDD_E1_D8, 0x2A_2F_28)
    static let accent = adaptive(0x2F_7D_5C, 0x4F_B4_88)
    static let accentInk = adaptive(0xFF_FF_FF, 0x0B_12_0D)
    static let negative = adaptive(0xC9_3B_3B, 0xE2_63_5F)

    /// トップのハイライト(緑系)とラスのハイライト(赤系)
    static let topTint = adaptive(0xE3_EF_E8, 0x1B_2E_24)
    static let topInk = adaptive(0x2F_7D_5C, 0x7F_D4_AE)
    static let lastTint = adaptive(0xF7_E2_E2, 0x33_1D_1D)

    static let resting = adaptive(0xAE_B4_A7, 0x5B_63_57)
    static let restingBg = adaptive(0xEC_EA_E3, 0x1E_22_1D)

    static let keyBg = adaptive(0xEE_F0_EA, 0x1E_22_19)
    /// お休みキー
    static let toneA = adaptive(0xF1_E6_CF, 0x3A_32_20)
    static let toneAInk = adaptive(0x8A_6A_1F, 0xE3_C0_7A)
    /// ⌫ と入力中のプレビュー
    static let toneB = adaptive(0xE4_E8_EE, 0x23_28_33)
    static let toneBInk = adaptive(0x4B_55_68, 0xAA_B4_C6)
    /// 閉じるキー
    static let toneC = adaptive(0xE2_DE_FA, 0x33_2C_55)
    static let toneCInk = adaptive(0x5B_4F_B0, 0xBC_AE_F5)

    /// 推移グラフの線の色。人数ぶん循環させる
    static let playerColors: [Color] = [
        adaptive(0x3F_AE_7C, 0x4F_C0_8E),
        adaptive(0x5B_8F_D6, 0x6F_A2_E6),
        adaptive(0xE0_A6_40, 0xE8_B6_5C),
        adaptive(0xD1_63_8F, 0xE0_7A_A4),
        adaptive(0x4F_B0_C0, 0x63_C2_D2),
        adaptive(0x9B_7F_E0, 0xAE_94_EE),
    ]

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
