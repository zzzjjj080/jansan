import XCTest

/// 設定のいちばん下まわり。**投げ銭を外した跡**（2026-09-30）に何が出るかを固定する。
///
/// 以前は `CoffeeTipUITests` が投げ銭と一緒にここを見ていた。投げ銭を消したので、
/// 残す価値のある「ご意見の入口」と「作者の他のアプリ」だけをこちらへ移した
final class FeedbackUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        // 初回の「使い方」が上に出ると設定ボタンが押せない
        app.launchArguments = ["-didShowHowTo", "YES"]
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
        // 起動直後の1回目は飲まれることがある。効かなければ1回だけ押し直す
        if !app.navigationBars["設定"].waitForExistence(timeout: 8) { gear.tap() }
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 15), "設定画面が開かない")
    }

    private func scrollToBottom(_ app: XCUIApplication, times: Int = 6) {
        for _ in 0..<times { app.swipeUp() }
    }

    /// 報告ボタンが設定に出ていること。mailto は開かず、存在と宛先の表示だけ見る
    func testFeedbackButtonAppears() {
        let app = launchApp()
        openSettings(app)
        scrollToBottom(app)

        let send = app.buttons["sendFeedback"]
        XCTAssertTrue(send.waitForExistence(timeout: 15), "報告ボタンが無い")
        // 設定の下には削除・版の印が続く。いちばん下まで送ると、報告ボタンは画面の上に外れる
        for _ in 0..<6 where !send.isHittable { app.swipeDown() }
        XCTAssertTrue(send.isHittable, "報告ボタンが押せる状態にない")
        XCTAssertTrue(
            app.staticTexts.containing(
                NSPredicate(format: "label CONTAINS 'zzzjjj080@gmail.com'")
            ).firstMatch.exists,
            "メールが開かないときの宛先が出ていない"
        )
        attach(app, "フィードバックの入口")
    }

    /// **投げ銭は無くなり、代わりに作者の他のアプリへの1行がある**こと。
    /// 押すと App Store が開くので、ここでは押さずに存在だけ見る
    func testTipIsGoneAndOtherAppsLinkIsThere() {
        let app = launchApp()
        openSettings(app)
        scrollToBottom(app)

        let others = app.buttons["otherApps"]
        XCTAssertTrue(others.waitForExistence(timeout: 15), "作者の他のアプリの行が無い")

        XCTAssertFalse(app.buttons.containing(
            NSPredicate(format: "label CONTAINS 'コーヒー'")).firstMatch.exists,
            "投げ銭が残っている")
        XCTAssertFalse(app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS '奢'")).firstMatch.exists,
            "投げ銭の文言が残っている")
        attach(app, "作者の他のアプリ")
    }
}
