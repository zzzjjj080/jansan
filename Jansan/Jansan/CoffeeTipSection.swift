import SwiftUI

/// `Form` / `List` の中に置く「コーヒーを奢る」。
///
/// **アプリ固有の色や触覚に依存しない。** そのままコピーして、`tint` だけ合わせればよい。
/// 独自レイアウトの設定画面（`ScrollView` + `VStack`）に入れる場合は
/// `CoffeeTip-Akiwaku.swift.txt` のほうを下敷きにする。
///
/// ```swift
/// @State private var tipJar = TipJar(productID: "com.zzzjjj080.Jansan.coffee")
/// ...
/// Form {
///     // 他のセクション
///     CoffeeTipSection(tipJar: tipJar)   // いちばん下
/// }
/// ```
struct CoffeeTipSection: View {
    @Bindable var tipJar: TipJar

    /// 見出しとアイコンの色。アプリの配色に合わせて変えてよい
    var tint: Color = .orange

    var body: some View {
        Section {
            switch tipJar.state {
            case .thanks:
                Label("ありがとうございます", systemImage: "cup.and.saucer.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                Button("閉じる") { tipJar.dismissThanks() }
                    .font(.footnote.weight(.semibold))
            case .failed(let message):
                Text(message).font(.footnote).foregroundStyle(.red)
                Button("閉じる") { tipJar.dismissThanks() }
                    .font(.footnote.weight(.semibold))
            case .unavailable:
                Text("いまは受け付けられません")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            default:
                button
            }
            gratitude
        } header: {
            Text("このアプリが気に入ったら")
                .foregroundStyle(tint)
        }
        .task { await tipJar.load() }
        // 購入が通った瞬間だけ鳴らす。承認待ちが後から届く場合もここを通る。
        .sensoryFeedback(.success, trigger: tipJar.cups)
    }

    private var button: some View {
        Button {
            Task { await tipJar.tip() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "cup.and.saucer.fill")
                    .foregroundStyle(tint)
                Text("開発者にコーヒーを奢る")
                    .fontWeight(.semibold)
                Spacer(minLength: 8)
                if let price = tipJar.displayPrice {
                    Text(price)
                        .fontWeight(.bold)
                        .foregroundStyle(tint)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            // Spacer は描画を持たないので、これが無いと余白を押しても反応しない
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(tipJar.product == nil || tipJar.state == .purchasing)
        .accessibilityIdentifier("buyCoffee")
    }

    /// 奢ってくれた人にだけ出すお礼。1杯目と2杯目以降で言い方を変える。
    ///
    /// 消耗型はStoreKitが復元しないので、機種変更すると 0 に戻ってこの行は消える。
    /// 消えても嘘にはならない書き方にしてある。
    @ViewBuilder
    private var gratitude: some View {
        switch tipJar.cups {
        case 0:
            EmptyView()
        case 1:
            Text("奢ってくれてありがとうございました")
                .font(.caption).foregroundStyle(tint)
        default:
            Text("\(tipJar.cups) 回も奢ってくれてありがとうございました")
                .font(.caption).foregroundStyle(tint)
        }
    }
}

/// 作業中の画面の隅に置く、控えめな1行版。
///
/// 設定画面のカードと違って主張しない。雀算のエクスポート画面のように、
/// 「使い終わった直後だが、作業の邪魔をしたくない」場所で使う。
struct CoffeeTipLink: View {
    @Bindable var tipJar: TipJar
    var tint: Color = .orange

    var body: some View {
        Group {
            switch tipJar.state {
            case .thanks:
                Text("ありがとうございます")
                    .foregroundStyle(tint)
            case .unavailable, .failed:
                EmptyView()
            default:
                Button {
                    Task { await tipJar.tip() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "cup.and.saucer.fill")
                        Text("開発者にコーヒーを奢る")
                        if let price = tipJar.displayPrice {
                            Text(price)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(tint)
                .disabled(tipJar.product == nil || tipJar.state == .purchasing)
                .accessibilityIdentifier("buyCoffeeCompact")
            }
        }
        .font(.footnote)
        .task { await tipJar.load() }
        .sensoryFeedback(.success, trigger: tipJar.cups)
    }
}
