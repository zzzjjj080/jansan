import SwiftUI

/// 画面の明るさの設定。端末の設定に従うか、明示的に選ぶか。
///
/// 卓の照明が暗い店ではダーク固定にしたい、といった要望があるので、
/// OS任せだけでなく手動でも選べるようにしている。
enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "端末に合わせる"
        case .light: "ライト"
        case .dark: "ダーク"
        }
    }

    /// nil を返すと端末の設定に従う
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
