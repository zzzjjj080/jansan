import Foundation
import Observation
import StoreKit

/// カンパ（投げ銭）の窓口。
///
/// 消耗型（Consumable）にしてあるので、気が向いたときに何度でも送れる。
/// 送ったからといってアプリの機能が変わることはなく、記録として残すものも無い。
@MainActor
@Observable
final class TipJar {
    /// App Store Connect で作る製品ID。ここを変えるなら向こうも揃える
    static let productID = "com.zzzjjj080.Jansan.tip100"

    enum State: Equatable {
        case idle
        case loading
        case unavailable
        case purchasing
        case thanks
        case failed(String)
    }

    private(set) var product: Product?
    private(set) var state: State = .idle

    /// 表示する金額はStoreKitが返すものをそのまま使う。
    /// 国によって価格も通貨も変わるため、アプリ側で「¥100」と決め打ちしてはいけない
    var displayPrice: String? { product?.displayPrice }

    func load() async {
        guard product == nil, state != .loading else { return }
        state = .loading
        do {
            product = try await Product.products(for: [Self.productID]).first
            state = product == nil ? .unavailable : .idle
        } catch {
            state = .unavailable
        }
    }

    func tip() async {
        guard let product else { return }
        state = .purchasing
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    state = .failed("購入を確認できませんでした")
                    return
                }
                // 消耗型は finish を呼ばないと未処理の取引として残り続ける
                await transaction.finish()
                state = .thanks
            case .userCancelled:
                state = .idle
            case .pending:
                // 承認待ち（ファミリー共有の購入承認など）。完了はStoreKitから後で届く
                state = .idle
            @unknown default:
                state = .idle
            }
        } catch {
            state = .failed("購入できませんでした")
        }
    }

    func dismissThanks() {
        state = .idle
    }
}
