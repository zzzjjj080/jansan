import XCTest

/// 投げ銭とフィードバックを、実際にタップして確かめる。
///
/// **`.storekit` はスキームで指定している**（`../../../Coffee.storekit`）。
/// `xcrun simctl launch` では効かないので、確認は必ずここから行う（引き継ぎ書 11-9）。
///
/// **シミュレータのストアフロントは米国**になるため価格は `$0.99` と出る。
/// `_storefront: "JPN"` を書いても変わらない。実機・本番では App Store Connect の
/// ¥200 が出るので、ここは追わない。価格を決め打ちしていない証明にもなる。
final class CoffeeTipUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launchApp(arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        return app
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func openSettings(_ app: XCUIApplication) {
        let gear = app.buttons["openSettings"]
        XCTAssertTrue(gear.waitForExistence(timeout: 20), "設定ボタンが見つからない")
        gear.tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 15), "設定画面が開かない")
    }

    /// 設定のいちばん下まで送る。Form なので一度では届かない
    private func scrollToBottom(_ app: XCUIApplication, times: Int = 6) {
        for _ in 0..<times { app.swipeUp() }
    }

    /// 設定のいちばん下に、価格つきで出ていること。
    /// **ここで撮る1枚が App内課金の審査用スクリーンショットになる。**
    func testCoffeeRowAppearsWithPrice() {
        let app = launchApp()
        openSettings(app)
        scrollToBottom(app)

        let coffee = app.buttons["buyCoffee"]
        XCTAssertTrue(coffee.waitForExistence(timeout: 15), "コーヒーの行が見つからない")

        // 商品が読めていればボタンが有効になり、ラベルに価格が入る
        XCTAssertTrue(coffee.isEnabled, "ボタンが無効。商品が読めていない（StoreKit設定のパスを疑う）")

        // 価格は StoreKit が返した文字列をそのまま出す。決め打ちしない
        let priceShown = expectation(
            for: NSPredicate(format: "label CONTAINS '$' OR label CONTAINS '¥'"),
            evaluatedWith: coffee
        )
        XCTAssertEqual(XCTWaiter().wait(for: [priceShown], timeout: 20), .completed,
                       "価格が出ていない。label=[\(coffee.label)]")

        XCTAssertTrue(app.staticTexts["このアプリが気に入ったら"].exists, "見出しが出ていない")
        attach(app, "審査用-投げ銭の入口")
    }

    /// 押したら購入まで通ること。
    ///
    /// **シミュレータでは原理的に通らない。** `.storekit` をスキームに書いても
    /// `xcodebuild test` では読まれない（設定を丸ごと外しても結果が同じだった）。
    /// タップすると実際のApp Storeへ行き、別プロセスの
    /// 「Apple Accountにサインイン」が出て止まる。`app` からは見えないので
    /// テスト側で押すこともできない。
    ///
    /// 通すには **Sandboxテスターでサインインした実機**が要る（引き継ぎ書 11-8）。
    /// そのときにそのまま使えるよう、中身は残して skip にしてある。
    func testTappingCoffeeCompletesPurchase() throws {
#if targetEnvironment(simulator)
        throw XCTSkip("シミュレータでは実際のApp Storeに繋がるため通らない。Sandboxテスターでサインインした実機で走らせること")
#else
        let app = launchApp()
        openSettings(app)
        scrollToBottom(app)

        let coffee = app.buttons["buyCoffee"]
        XCTAssertTrue(coffee.waitForExistence(timeout: 15))
        XCTAssertTrue(coffee.isEnabled, "商品が読めていない")
        coffee.tap()

        // 確認シートの表記はOSの言語で変わる。出たものを押す
        for label in ["購入", "Purchase", "確認", "Confirm", "OK"] {
            let b = app.buttons[label]
            if b.waitForExistence(timeout: 4), b.isHittable { b.tap(); break }
        }

        let thanks = app.staticTexts["ありがとうございます"]
        if !thanks.waitForExistence(timeout: 30) {
            attach(app, "NG-購入後にお礼が出ない")
            let d = XCTAttachment(string: app.debugDescription)
            d.name = "NG-そのときの画面の要素"; d.lifetime = .keepAlways; add(d)
            XCTFail("購入後のお礼が出ない")
            return
        }
        attach(app, "購入後のお礼")
#endif
    }

    /// 1杯目のお礼。杯数は UserDefaults なので起動引数で差し込める（引き継ぎ書 11-10）
    func testGratitudeAfterOneCup() {
        let app = launchApp(arguments: ["-tipjar.cups", "1"])
        openSettings(app)
        scrollToBottom(app)
        XCTAssertTrue(app.staticTexts["奢ってくれてありがとうございました"].waitForExistence(timeout: 10),
                      "1杯目のお礼が出ていない")
    }

    /// 2杯目以降は回数を添える
    func testGratitudeAfterManyCups() {
        let app = launchApp(arguments: ["-tipjar.cups", "3"])
        openSettings(app)
        scrollToBottom(app)
        XCTAssertTrue(app.staticTexts["3 回も奢ってくれてありがとうございました"].waitForExistence(timeout: 10),
                      "回数入りのお礼が出ていない")
        attach(app, "3杯ぶんのお礼")
    }

    /// 報告ボタンが設定に出ていること。mailto は開かず、存在と宛先の表示だけ見る
    func testFeedbackButtonAppears() {
        let app = launchApp()
        openSettings(app)
        scrollToBottom(app)

        let send = app.buttons["sendFeedback"]
        XCTAssertTrue(send.waitForExistence(timeout: 15), "報告ボタンが無い")
        XCTAssertTrue(send.isHittable, "報告ボタンが押せる状態にない")
        XCTAssertTrue(
            app.staticTexts.containing(
                NSPredicate(format: "label CONTAINS 'zzzjjj080@gmail.com'")
            ).firstMatch.exists,
            "メールが開かないときの宛先が出ていない"
        )
        attach(app, "フィードバックの入口")
    }
}
