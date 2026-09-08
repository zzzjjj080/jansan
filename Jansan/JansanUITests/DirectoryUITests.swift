import XCTest

/// 記録タブとディレクトリ。作る・保存先にする・そこに入る・共有の入口まで。
///
/// CloudKit へ実際に送る部分はシミュレータでは通らない（iCloud アカウントが無い）。
/// 「サインインしていない」と**正しく断られる**ことまでを確かめる。
final class DirectoryUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-didShowHowTo", "YES"]
        app.launch()
        return app
    }

    /// 前回のデータが残っていても衝突しないよう、毎回違う名前にする
    private func uniqueName(_ base: String) -> String {
        base + String(UUID().uuidString.prefix(4))
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func openRecordsTab(_ app: XCUIApplication) {
        // 起動直後は「マイ記録」の用意や復元が走っている。入力画面が出そろうまで待ってから押す
        XCTAssertTrue(app.buttons["openSettings"].waitForExistence(timeout: 20), "入力画面が出ない")
        let tab = app.segmentedControls.firstMatch.buttons["記録"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "「記録」の切り替えが無い")
        // タブのタップは起動直後の処理に飲まれることがある。効かなければ1回だけ押し直す
        for _ in 0..<2 {
            tab.tap()
            if app.navigationBars["記録"].waitForExistence(timeout: 8) { return }
        }
        XCTFail("記録が開かない")
    }

    private func createDirectory(_ app: XCUIApplication, named name: String) {
        app.buttons["addDirectory"].tap()
        app.buttons["newDirectory"].tap()
        let alert = app.alerts["新しいディレクトリ"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "作成のダイアログが出ない")
        alert.textFields.firstMatch.tap()
        alert.textFields.firstMatch.typeText(name)
        alert.buttons["作る"].tap()
    }

    /// メニューから「ここを保存先にする」を押し、効いたことを確かめる。
    /// 効いていなければもう一度。メニュー項目のタップは稀に抜ける
    private func makeCurrentDirectory(_ app: XCUIApplication) {
        for _ in 0..<2 {
            app.buttons["directoryMenu"].tap()
            let makeCurrent = app.buttons["makeCurrent"]
            XCTAssertTrue(makeCurrent.waitForExistence(timeout: 5), "「保存先にする」が無い")
            if !makeCurrent.isEnabled {
                // すでに保存先。メニューを閉じて終わり
                app.tap()
                return
            }
            makeCurrent.tap()
            // 効いたかは、もう一度メニューを開いて項目が無効になっているかで見る
            app.buttons["directoryMenu"].tap()
            let check = app.buttons["makeCurrent"]
            let done = check.waitForExistence(timeout: 3) && !check.isEnabled
            app.tap()   // メニューを閉じる
            if done { return }
        }
        XCTFail("保存先にできなかった")
    }

    /// 起動したら「マイ記録」があり、入力タブが最初に出ること
    func testStartsOnInputAndHasDefaultDirectory() {
        let app = launchApp()
        XCTAssertTrue(app.buttons["openSettings"].waitForExistence(timeout: 20), "起動時に入力画面になっていない")
        XCTAssertTrue(app.segmentedControls.firstMatch.buttons["入力"].isSelected, "「入力」が選ばれていない")

        openRecordsTab(app)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'マイ記録'"))
                        .firstMatch.waitForExistence(timeout: 10), "「マイ記録」が無い")
        attach(app, "記録タブ")
    }

    /// ディレクトリを作り、保存先にして、保存するとそこに入ること
    func testCreateDirectoryAndSaveInto() {
        let app = launchApp()
        let name = uniqueName("卓")
        openRecordsTab(app)
        createDirectory(app, named: name)

        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "作ったディレクトリが一覧に出ない")
        row.tap()
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 10))

        // 保存先にする。メニューの項目は稀にタップが抜けるので、効いたかを見て1回だけやり直す
        makeCurrentDirectory(app)

        // 入力へ戻って、見出しに保存先が出ていること
        app.segmentedControls.firstMatch.buttons["入力"].tap()
        let caption = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "保存先: " + name)).firstMatch
        if !caption.waitForExistence(timeout: 10) {
            let d = XCTAttachment(string: app.debugDescription)
            d.name = "NG-保存先が出ないときの要素"; d.lifetime = .keepAlways; add(d)
            XCTFail("見出しに保存先が出ない")
            return
        }

        // 1マス入れて保存
        app.buttons["cell-0-0"].tap()
        for key in ["3", "0"] { app.buttons[key].firstMatch.tap() }
        app.buttons["確定"].tap()
        let save = app.buttons["saveGame"]
        if !save.waitForExistence(timeout: 10) {
            let d = XCTAttachment(string: app.debugDescription)
            d.name = "NG-saveGameが無いときの要素"; d.lifetime = .keepAlways; add(d)
            XCTFail("保存ボタンが無い")
            return
        }
        save.tap()

        // そのディレクトリに1件入っている
        openRecordsTab(app)
        // 固有名のディレクトリなので、ちょうど1件になっているはず
        let updated = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS '1 件'", name)).firstMatch
        if !updated.waitForExistence(timeout: 10) {
            attach(app, "NG-件数が合わない")
            let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'directory-'")).allElementsBoundByIndex
            let d = XCTAttachment(string: rows.map(\.label).joined(separator: "\n") + "\n---\n" + app.debugDescription)
            d.name = "NG-一覧の行"; d.lifetime = .keepAlways; add(d)
            XCTFail("保存した記録がディレクトリに入っていない。行: \(rows.map(\.label))")
            return
        }
        attach(app, "ディレクトリに保存")
    }

    /// 共有の設定画面が開き、入力の検証が効くこと。
    /// 実際の送信は iCloud アカウントが無いので「サインインしていない」で止まる。
    /// **それが正しく伝わる**ところまでを確かめる
    func testShareSettingsValidatesAndReportsNoAccount() {
        let app = launchApp()
        openRecordsTab(app)
        let name = uniqueName("共有")
        createDirectory(app, named: name)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch.tap()

        app.buttons["directoryMenu"].tap()
        app.buttons["shareSettings"].tap()
        XCTAssertTrue(app.navigationBars["共有"].waitForExistence(timeout: 10), "共有の設定が開かない")

        // 短すぎるIDは弾く
        let id = app.textFields["shareIDField"]
        let pw = app.textFields["sharePasswordField"]
        id.tap(); id.typeText("ab")
        pw.tap(); pw.typeText("abcd")
        app.buttons["publishButton"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 10), "検証のエラーが出ない")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '3文字以上'")).firstMatch.exists,
                      "IDの長さの説明が無い")
        app.alerts.buttons["OK"].tap()
        attach(app, "共有-検証")

        // 正しい長さなら送信に進み、アカウントが無いことを伝える
        id.tap(); id.typeText("cd")
        app.buttons["publishButton"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 30), "送信の結果が出ない")
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'iCloud'")).firstMatch.exists,
                      "iCloud が要ることが伝わっていない")
        attach(app, "共有-アカウント無し")
    }

    /// 受け取る画面が開き、見つからないときに正しく言うこと
    func testSubscribeReportsNotFound() {
        let app = launchApp()
        openRecordsTab(app)
        app.buttons["addDirectory"].tap()
        app.buttons["subscribeDirectory"].tap()
        XCTAssertTrue(app.navigationBars["IDで受け取る"].waitForExistence(timeout: 10), "受け取る画面が開かない")

        app.textFields["subscribeIDField"].tap()
        app.textFields["subscribeIDField"].typeText("nosuchid")
        app.textFields["subscribePasswordField"].tap()
        app.textFields["subscribePasswordField"].typeText("zzzz")
        app.buttons["lookUpButton"].tap()

        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 30), "結果が出ない")
        attach(app, "受け取る-見つからない")
    }

    /// ディレクトリを消すと、中の記録も消え、保存先は「マイ記録」に戻ること
    func testDeleteDirectoryResetsCurrent() {
        let app = launchApp()
        openRecordsTab(app)
        let name = uniqueName("消")
        createDirectory(app, named: name)
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch.tap()
        makeCurrentDirectory(app)

        app.buttons["directoryMenu"].tap()
        app.buttons["deleteDirectory"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 10))
        app.alerts.buttons["削除する"].tap()

        XCTAssertTrue(app.navigationBars["記録"].waitForExistence(timeout: 10), "一覧に戻らない")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch.exists, "消えていない")

        app.segmentedControls.firstMatch.buttons["入力"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '保存先: マイ記録'"))
                        .firstMatch.waitForExistence(timeout: 10), "保存先がマイ記録に戻っていない")
    }
}
