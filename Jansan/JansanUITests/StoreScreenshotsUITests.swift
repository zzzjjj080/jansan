import XCTest

/// App Store 用のスクリーンショットを撮る。**普段のテストでは走らせない。**
///
/// `TEST_RUNNER_STORE_SHOTS=1 xcodebuild test -only-testing:JansanUITests/StoreScreenshotsUITests`
/// で走らせ、添付の画像を取り出して `store/MakeScreenshots.swift` に通す。
/// アプリを消してから走らせること（名簿が初期の名前に戻り、デモの記録だけになる）
final class StoreScreenshotsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(ProcessInfo.processInfo.environment["STORE_SHOTS"] == "1",
                          "ストア用の撮影は STORE_SHOTS=1 のときだけ走らせる")
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openSettings(_ app: XCUIApplication) {
        let gear = app.buttons["openSettings"]
        XCTAssertTrue(gear.waitForExistence(timeout: 20), "設定ボタンが無い")
        gear.tap()
        if !app.navigationBars["設定"].waitForExistence(timeout: 8) { gear.tap() }
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 15), "設定が開かない")
    }

    @discardableResult
    private func scrollTo(_ app: XCUIApplication, _ element: XCUIElement, tries: Int = 20) -> Bool {
        for _ in 0..<tries {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    /// 設定の開発用ボタンで、デモの点数を入れる（Debug ビルドだけにある）
    private func seed(_ app: XCUIApplication, rounds: Int) {
        openSettings(app)
        let button = app.buttons["デモデータを\(rounds)局入れる"]
        if !scrollTo(app, button) {
            shot(app, "NG-デモデータのボタンが無い")
            XCTFail("デモデータのボタンが無い（Debugビルドで走らせること）")
            return
        }
        button.tap()
    }

    private func save(_ app: XCUIApplication) {
        let save = app.buttons["saveGame"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), "保存ボタンが無い")
        save.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "保存の確認が出ない")
        alert.buttons.matching(NSPredicate(format: "label ENDSWITH 'に残す'")).firstMatch.tap()
        XCTAssertFalse(alert.waitForExistence(timeout: 3), "確認が閉じていない")
    }

    private func openRecordsTab(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["openSettings"].waitForExistence(timeout: 20), "入力画面が出ない")
        app.segmentedControls.firstMatch.buttons["記録"].tap()
    }

    /// マイ記録の uid は固定（Directory.defaultUID）
    private let defaultUID = "00000000-0000-0000-0000-00000000A001"

    func testCaptureStoreScreenshots() {
        let app = XCUIApplication()
        app.launchArguments = ["-didShowHowTo", "YES"]
        app.launch()

        // 01 入力画面。12局の表を入れた直後に撮り、そのまま記録に残す
        // （撮るためだけにもう1回入れ直すと、4回目の設定でボタンに届かず落ちたことがある）
        seed(app, rounds: 12)
        sleep(1)
        shot(app, "01-main")
        save(app)

        // 集計に数字が並ぶよう、局数の違う記録をあと2回ぶん残す（勝つ人が回ごとに変わる）
        for rounds in [8, 3] {
            seed(app, rounds: rounds)
            save(app)
        }

        // 02 集計のハイライト
        openRecordsTab(app)
        let stats = app.buttons["openStats-\(defaultUID)"]
        XCTAssertTrue(stats.waitForExistence(timeout: 15), "マイ記録の集計ボタンが無い")
        stats.tap()
        XCTAssertTrue(app.buttons["全期間"].waitForExistence(timeout: 15), "集計が開かない")
        sleep(1)
        shot(app, "02-stats")

        // 04 画像で送る（個人成績に進む前に撮る。戻る操作を挟まない）
        let make = app.buttons["makeImages"]
        XCTAssertTrue(make.waitForExistence(timeout: 10), "画像で送るの入口が無い")
        make.tap()
        XCTAssertTrue(app.images["sharePreview0"].waitForExistence(timeout: 20), "画像ができていない")
        sleep(1)
        shot(app, "04-share")
        app.navigationBars["画像で送る"].buttons["閉じる"].tap()

        // 03 個人成績
        let open = app.buttons["openPlayerDetails"]
        XCTAssertTrue(open.waitForExistence(timeout: 10), "個人成績の入口が無い")
        XCTAssertTrue(scrollTo(app, open), "個人成績の入口に届かない")
        open.tap()
        XCTAssertTrue(app.staticTexts["着順"].waitForExistence(timeout: 10), "個人成績が開かない")
        sleep(1)
        shot(app, "03-player")

        // 05 CSVの取り込み。いったん起動し直して、記録の一覧から入る
        app.terminate()
        app.launch()
        openRecordsTab(app)
        let detail = app.buttons["openDirectory-\(defaultUID)"]
        XCTAssertTrue(detail.waitForExistence(timeout: 15), "マイ記録の詳細ボタンが無い")
        detail.tap()
        XCTAssertTrue(app.navigationBars["マイ記録"].waitForExistence(timeout: 10), "マイ記録が開かない")
        app.buttons["directoryMenu"].tap()
        let importItem = app.buttons["importCSV"]
        XCTAssertTrue(importItem.waitForExistence(timeout: 5), "CSVの取り込みが無い")
        importItem.tap()
        let field = app.textViews["csvPasteField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "貼り付け欄が無い")
        field.tap()
        field.typeText("No,中村,五十嵐,斎藤,佐々木\n1,30,10,-10,-30\n2,-20,40,0,-20\n3,52,-12,-25,-15\n合計,62,38,-35,-65\n")
        app.buttons["previewCSV"].tap()
        XCTAssertTrue(app.buttons["commitCSV"].waitForExistence(timeout: 10), "取り込む内容が出ない")
        sleep(1)
        shot(app, "05-import")
    }
}
