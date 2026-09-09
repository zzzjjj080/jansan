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

    /// 保存ボタンを押して、確認まで通す。
    /// 押した瞬間に入ってしまうと間違いに気づけないので、確認を1枚挟んである
    private func tapSave(_ app: XCUIApplication) {
        let save = app.buttons["saveGame"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), "保存ボタンが無い")
        save.tap()
        // **アラートの中に限定する。** 単に label CONTAINS 'に残す' で探すと、
        // ツールバーの保存ボタン自身（読み上げ名「この対局を記録に残す」）に当たって
        // 保存されないまま通ってしまう
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "保存の確認が出ない")
        let confirm = alert.buttons.matching(NSPredicate(format: "label ENDSWITH 'に残す'")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "確認のボタンが無い")
        confirm.tap()
        XCTAssertFalse(alert.waitForExistence(timeout: 3), "確認が閉じていない")
    }

    /// 保存先を「マイ記録」に戻す。
    /// **@AppStorage は起動をまたいで残る。** 前のテストが保存先を変えたままだと、
    /// 次のテストが別のディレクトリへ保存して「記録が無い」と誤検知する
    private func useDefaultDirectory(_ app: XCUIApplication) {
        let picker = app.buttons["pickDirectory"]
        XCTAssertTrue(picker.waitForExistence(timeout: 20), "保存先のボタンが無い")
        picker.tap()
        XCTAssertTrue(app.navigationBars["保存先"].waitForExistence(timeout: 10), "保存先の選択が開かない")
        let mine = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'マイ記録'")).firstMatch
        XCTAssertTrue(mine.waitForExistence(timeout: 10), "「マイ記録」が選べない")
        mine.tap()
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS '保存先: マイ記録'"))
                        .firstMatch.waitForExistence(timeout: 10), "保存先がマイ記録にならない")
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

    /// 一覧に着いたかどうか。見出しは消したので、＋ の有無で判断する
    private func atDirectoryList(_ app: XCUIApplication, timeout: TimeInterval = 8) -> Bool {
        app.buttons["addDirectory"].waitForExistence(timeout: timeout)
    }

    private func openRecordsTab(_ app: XCUIApplication) {
        // 起動直後は「マイ記録」の用意や復元が走っている。入力画面が出そろうまで待ってから押す
        XCTAssertTrue(app.buttons["openSettings"].waitForExistence(timeout: 20), "入力画面が出ない")
        let tab = app.segmentedControls.firstMatch.buttons["記録"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "「記録」の切り替えが無い")
        // 切り替えのタップは起動直後の処理に飲まれることがある。効かなければ1回だけ押し直す
        for _ in 0..<2 {
            tab.tap()
            if atDirectoryList(app) { return }
            // ディレクトリの中に入ったままだと、そこが出る。一覧まで戻る
            for _ in 0..<3 {
                let back = app.navigationBars.buttons.element(boundBy: 0)
                guard back.exists, back.isHittable else { break }
                back.tap()
                if atDirectoryList(app, timeout: 5) { return }
            }
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
        let caption = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "保存先: " + name)).firstMatch
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
        tapSave(app)

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

        XCTAssertTrue(atDirectoryList(app, timeout: 10), "一覧に戻らない")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch.exists, "消えていない")

        app.segmentedControls.firstMatch.buttons["入力"].tap()
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS '保存先: マイ記録'"))
                        .firstMatch.waitForExistence(timeout: 10), "保存先がマイ記録に戻っていない")
    }
}

// MARK: - 閲覧専用

extension DirectoryUITests {

    /// 記録をタップしても入力中の表は置き換わらないこと。
    /// 「見たい」と「続きを打ちたい」は別の用件なので、既定は見るだけ
    func testTappingRecordOpensReadOnlyView() {
        let app = launchApp()

        useDefaultDirectory(app)

        // 入力に目印を1つ入れておく。これが残っていれば置き換わっていない
        XCTAssertTrue(app.buttons["cell-0-0"].waitForExistence(timeout: 20))
        app.buttons["cell-0-0"].tap()
        for key in ["7", "7"] { app.buttons[key].firstMatch.tap() }
        app.buttons["確定"].tap()
        tapSave(app)

        openRecordsTab(app)
        let mine = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'マイ記録'")).firstMatch
        XCTAssertTrue(mine.waitForExistence(timeout: 10))
        mine.tap()

        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS '人打ち'")).firstMatch
        if !row.waitForExistence(timeout: 10) {
            attach(app, "NG-記録の行が無い")
            let d = XCTAttachment(string: app.debugDescription)
            d.name = "NG-記録の行が無いときの要素"; d.lifetime = .keepAlways; add(d)
            XCTFail("記録の行が無い")
            return
        }
        row.tap()

        // 見るだけの帯が出て、入力用のマスは出ていない
        XCTAssertTrue(app.staticTexts["保存した記録・見るだけ"].waitForExistence(timeout: 10),
                      "見るだけの帯が出ていない")
        XCTAssertFalse(app.buttons["cell-0-0"].exists, "閲覧画面に入力用のマスが出ている")
        XCTAssertTrue(app.buttons["loadIntoInput"].exists, "「入力に読み込む」が無い")
        attach(app, "閲覧専用")

        app.buttons["閉じる"].firstMatch.tap()
        app.segmentedControls.firstMatch.buttons["入力"].tap()

        // 入力の表は触られていない
        XCTAssertEqual(app.buttons["cell-0-0"].value as? String, "77", "入力中の表が置き換わっている")
    }
}

// MARK: - 保存の確認

extension DirectoryUITests {

    /// 保存は押した瞬間には入らず、どこへ入るかを見せてから確定すること。
    /// 共有中なら、相手に届くことも伝える
    func testSaveAsksBeforeStoring() {
        let app = launchApp()
        XCTAssertTrue(app.buttons["cell-0-0"].waitForExistence(timeout: 20))
        app.buttons["cell-0-0"].tap()
        for key in ["1", "2"] { app.buttons[key].firstMatch.tap() }
        app.buttons["確定"].tap()

        app.buttons["saveGame"].tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "確認が出ない")
        XCTAssertTrue(alert.buttons.matching(NSPredicate(format: "label ENDSWITH 'に残す'")).firstMatch.exists,
                      "どこへ残すのかがボタンに出ていない")
        XCTAssertTrue(alert.staticTexts.containing(NSPredicate(format: "label CONTAINS '人打ち'"))
                        .firstMatch.exists, "何を残すのかが書かれていない")
        attach(app, "保存の確認")

        // やめれば入らない
        alert.buttons["やめる"].tap()
        openRecordsTab(app)
        let mine = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'マイ記録'")).firstMatch
        XCTAssertTrue(mine.waitForExistence(timeout: 10))
        XCTAssertTrue(mine.label.contains("0 件"), "やめたのに保存されている: \(mine.label)")
    }
}

// MARK: - 保存先の切り替えと削除

extension DirectoryUITests {

    /// 入力画面のいちばん左のボタンから保存先を変えられること
    func testPickDirectoryFromInput() {
        let app = launchApp()
        let name = uniqueName("先")
        openRecordsTab(app)
        createDirectory(app, named: name)
        app.segmentedControls.firstMatch.buttons["入力"].tap()

        let picker = app.buttons["pickDirectory"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10), "保存先のボタンが無い")
        picker.tap()
        XCTAssertTrue(app.navigationBars["保存先"].waitForExistence(timeout: 10), "保存先の選択が開かない")
        attach(app, "保存先を選ぶ")

        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'pick-'"))
            .element(boundBy: 1).tap()

        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS '保存先: '"))
                        .firstMatch.waitForExistence(timeout: 10), "見出しに保存先が出ない")
    }

    /// 一覧からスワイプで消せること。確認を挟むこと
    func testSwipeDeleteAsksFirst() {
        let app = launchApp()
        let name = uniqueName("削")
        openRecordsTab(app)
        createDirectory(app, named: name)

        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "作った行が無い")
        row.swipeLeft()

        let delete = app.buttons["Delete"].exists ? app.buttons["Delete"] : app.buttons["削除"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "スワイプで削除が出ない")
        delete.tap()

        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "確認せずに消そうとしている")
        alert.buttons["やめる"].tap()
        XCTAssertTrue(row.exists, "やめたのに消えている")

        row.swipeLeft()
        (app.buttons["Delete"].exists ? app.buttons["Delete"] : app.buttons["削除"]).tap()
        app.alerts.firstMatch.buttons["削除する"].tap()
        XCTAssertFalse(row.waitForExistence(timeout: 5), "消えていない")
    }
}

// MARK: - 新しい対局を始める

extension DirectoryUITests {

    /// 新規セッションは確認を挟み、消える前に控えを取ること。
    /// **押し間違えても記録から戻せる**のが要点
    func testNewSessionBacksUpBeforeClearing() {
        let app = launchApp()
        useDefaultDirectory(app)

        // 1局入れる
        XCTAssertTrue(app.buttons["cell-0-0"].waitForExistence(timeout: 20))
        app.buttons["cell-0-0"].tap()
        for key in ["5", "5"] { app.buttons[key].firstMatch.tap() }
        app.buttons["確定"].tap()
        XCTAssertEqual(app.buttons["cell-0-0"].value as? String, "55")

        // やめれば消えない
        app.buttons["newSession"].tap()
        var alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "確認が出ない")
        XCTAssertTrue(alert.staticTexts.containing(
            NSPredicate(format: "label CONTAINS '自動バックアップ'")).firstMatch.exists,
            "控えを取ることが伝わっていない")
        attach(app, "新規セッションの確認")
        alert.buttons["やめる"].tap()
        XCTAssertEqual(app.buttons["cell-0-0"].value as? String, "55", "やめたのに消えている")

        // 始めると表は空になる
        app.buttons["newSession"].tap()
        alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        alert.buttons["始める"].tap()
        XCTAssertEqual(app.buttons["cell-0-0"].value as? String, "未入力", "表が消えていない")

        // 控えが「自動バックアップ」に入っている
        openRecordsTab(app)
        let backup = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH '自動バックアップ'")).firstMatch
        XCTAssertTrue(backup.waitForExistence(timeout: 10), "自動バックアップが作られていない")
        XCTAssertFalse(backup.label.contains("0 件"), "控えが入っていない: \(backup.label)")
        attach(app, "自動バックアップ")
    }

    /// 自動バックアップは保存先には選べないこと。仕組みが入れる場所なので
    func testAutoBackupIsNotSelectableAsDestination() {
        let app = launchApp()
        XCTAssertTrue(app.buttons["pickDirectory"].waitForExistence(timeout: 20))
        app.buttons["pickDirectory"].tap()
        XCTAssertTrue(app.navigationBars["保存先"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH '自動バックアップ'")).firstMatch.exists,
            "自動バックアップが保存先に出ている")
    }
}
