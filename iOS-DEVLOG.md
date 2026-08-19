# iPhoneアプリ開発・リリース 引き継ぎ書 v3（統合版）

雀算（麻雀スコア記録）と、ゆるトレ日記（健康カレンダー）の**2本を審査提出まで**やった記録。
2つのチャットで別々に溜まった知見を1つにマージしたもの。**これが正本。**

- **正本：`~/.claude/iOS-DEVLOG.md`**（どのフォルダで作業していても参照できる）
- `/Users/jin/Claude/iOS-DEVLOG.md` は正本へのシンボリックリンク
- GitHubバックアップ：`Jansan/iOS-DEVLOG.md`
- 各アプリの `PLAYBOOK.md` は履歴として残すが、**今後の更新はこのファイルに書く。**

**iPhoneアプリを作るときは、何より先にこのファイルを読むこと。**
`~/.claude/CLAUDE.md` から参照されているので、新しいチャットでも自動で案内が出る。
アプリ固有の話ではなく「次も必ず使う知識」だけを書いた。

**特に「4. 実際に踏んだ罠」「5. リリース手続き」「8. 設計で効いたこと」は必ず読むこと。**
知らないと同じ時間を溶かす。

---

## 0. 新しいチャットでの切り出し方

このファイル全体を貼ったうえで、こう書けばよい。

> 前回までにiPhoneアプリを2本作って審査提出まで終えたときの引き継ぎ書です。
> これを踏まえて、今回は「〇〇」というアプリを作りたい。
> まず要件を整理してから、同じ進め方で始めてください。

---

## 1. 開発環境（このMacの現状）

| 項目 | 状態 |
|---|---|
| Mac | Apple Silicon / macOS 26 |
| Xcode | 26.6 / Swift 6.3 |
| Apple Developer Program | **登録済み**（個人・年$99） |
| **Team ID** | `A7WA598R44` |
| Apple ID（開発者） | zzzjjj080@yahoo.co.jp |
| App Store Connect の数字 | 1070981569（**Team IDとは別物**） |
| GitHub | `zzzjjj080` / SSH鍵設定済み（パスフレーズなし） |
| git identity | jin / zzzjjj080@gmail.com |
| 実機 | **iPhone Air**（iPhone18,4 / iOS 26.6）1台のみ。チーム登録済み |
| Homebrew / gh | **入っていない** |

Claude Codeの権限は `~/.claude/settings.json` で許可済み。
Bash / Read / Edit / Write / Glob / Grep は確認なしで通る。
**sudo が要るコマンドは本人が実行する。**（Macのパスワードは誰にも渡さない）

**Developer Program も実機登録も済んでいるので、3本目は2本目よりさらに速い。**

---

## 2. 進め方（この順番で2本とも成功した）

### ① HTMLで動くプロトタイプを作る

Swiftを書く前に、ブラウザで動くHTML1枚で操作感を作り込む。**これが最も効く。**

- 仕様の迷いをSwift移植前に全部潰せる
- 修正が数秒で反映される
- 画面を見ながら議論できる

ゆるトレ日記では、この段階で採点式・確定ルール・色・レイアウトを**30往復以上**調整した。
Swift移植後の手戻りはほぼゼロ。

**プロトタイプに「調整パネル」を置くと強い。** 数式のパラメータをその場で変えて結果を見られるようにすると、
仕様の議論が「どっちが良さそうか」ではなく「実際にこうなる」で進む。

**プロトタイプにも localStorage の保存を入れる。** リロードで全消えすると検証が続かない。

### ② ロジックだけ先にSwift Packageへ（UI抜き）

`○○Core` というUI非依存のパッケージを作り、計算・判定だけ移してテストを書く。

- Xcodeを開かずに `swift test` で1秒で回せる
- 一番壊れやすい部分がテストで固定される
- UIを何度作り直してもロジックの無事を即確認できる
- 雀算45本 / ゆるトレ日記54本。リファクタが怖くなくなる

**プロトタイプで検算した内容が、そのままテストケースになる。** これが②の最大の利点。

**バグを直したら、まず「そのバグを再現するテスト」を書く。**
雀算の改名バグは `RenameTests.swift` に、
「setPlayers を改名に使うと点数が消える」という**壊れる側の挙動もテストとして残した。**
なぜその関数が要るのかが、後から読んで分かる。

### ③ UIを載せる

`@Observable`（iOS 17+）で状態クラスを1つ。Viewはそれを見るだけ。
`ObservableObject` + `@Published` は不要。

### ④ シミュレータで実際に触る

**「ビルドが通った」で終わらせない。必ずタップして確認する。**
2本とも、これで見つけたバグがある。

### ⑤ 実機に入れる

**触覚フィードバックは実機でしか確認できない。**
`install-device.sh` のような「接続中の端末を自動で選ぶ」スクリプトを最初に作っておくと、
機種変更しても書き換え不要で、修正のたびにすぐ入れられる。

```bash
# 接続中のiPhoneを拾う。列位置に頼るとデバイス名の空白でずれるので、UUID形式で抜く
LINE=$(xcrun devicectl list devices | grep -m1 " connected ")
DEV=$(echo "$LINE" | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}')
```

**運用ルール：チャットでデバッグしたら、その回のうちに手元の実機を最新にする。**
古いビルドが入ったままだと、次に触ったとき直したはずのバグが再現して混乱する。

---

## 3. Xcodeプロジェクトの作り方

### 前作のプロジェクトを複製するのが最速

**新規作成よりも、前のアプリの `.xcodeproj` をコピーして名前を置換するほうが速くて確実。**
ビルド設定（下記）が最初から正しく入っているため。ゆるトレ日記はこの方法で**一発でビルドが通った**。

```bash
cp -R ../Jansan/Jansan/Jansan.xcodeproj NewApp/NewApp.xcodeproj
rm -rf NewApp/NewApp.xcodeproj/xcuserdata NewApp/NewApp.xcodeproj/project.xcworkspace/xcuserdata
find NewApp -type f \( -name "*.pbxproj" -o -name "*.xcscheme" \) -print0 |
  xargs -0 sed -i '' -e 's/JansanCore/NewAppCore/g' -e 's/Jansan/NewApp/g' -e 's/雀算/新アプリ名/g'
```

**Xcode 16以降は `PBXFileSystemSynchronizedRootGroup`** なので、
`.swift` をフォルダに置くだけで自動的にビルド対象になる。pbxprojの編集は不要。

### 必ず確認するビルド設定

| 設定 | 値 | 理由 |
|---|---|---|
| `IPHONEOS_DEPLOYMENT_TARGET` | **18.0** | 初期値は最新OS。そのままだと誰にも届かない |
| `TARGETED_DEVICE_FAMILY` | **1** | 初期値はiPhone+iPad+Vision。iPhone専用にするとスクショも楽 |
| `developmentRegion` | **ja**（`knownRegions` に ja） | これが en だとスワイプ削除が「Delete」のまま |
| `INFOPLIST_KEY_CFBundleDisplayName` | アプリ名 | ホーム画面の表示名 |
| `UISupportedInterfaceOrientations_iPhone` | Portrait | 縦専用なら固定 |
| `DEVELOPMENT_TEAM` | `A7WA598R44` | |

### 権限を使うなら「エンタイトルメント」も要る（重要）

**`Info.plist` の用途説明だけでは動かない。** 機能そのものの有効化が別に必要。
ゆるトレ日記はこれを忘れ、HealthKitの許可ダイアログが**一切出ない**状態で審査に出してしまった。

```xml
<!-- NewApp/NewApp.entitlements -->
<key>com.apple.developer.healthkit</key><true/>
<key>com.apple.developer.healthkit.access</key><array/>
```

```
CODE_SIGN_ENTITLEMENTS = NewApp/NewApp.entitlements;
```

確認コマンド。**これを毎回やる。**

```bash
codesign -d --entitlements - path/to/App.app | tr ',' '\n' | grep -i healthkit
```

`-allowProvisioningUpdates` を付けてビルドすれば、XcodeがApp IDの機能も自動で有効にしてくれる。

---

## 4. 実際に踏んだ罠

### 【最重要】4-1. エラーを握り潰すと、原因が永久に分からない

HealthKitの許可が失敗していたのに、`catch` で握り潰して `return false` していたため、
**ボタンを押しても無反応**になり、原因の特定に時間を要した。

```swift
// ❌ これをやると、後で必ず苦しむ
do { try await store.requestAuthorization(...) } catch { return false }

// ✅ 理由を残し、画面にも出す
private(set) var lastError: String?
do { ... } catch { lastError = error.localizedDescription; return false }
```

**無反応が一番たちが悪い。** 権限・ネットワーク・ファイルI/Oでは必ずエラーを画面に出すこと。

### 4-2. Command Line Toolsだけでは `swift test` が動かない

XCTestもSwift TestingもXcode.appに同梱。CLTだけだとテストが走らない。

### 4-3. `xcode-select -p` は当てにならない

Xcodeを入れても「明示的に選択していない」状態がある。
`-p` はフォールバックで正しいパスを返すのでビルドは通るが、シミュレータ連携が動かない。

```bash
ls -l /var/db/xcode_select_link   # 無ければ未選択
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer   # ユーザー自身が実行
```

### 4-4. シミュレータは1台だけ起動する

2台bootedだとタップが別端末に飛ぶ。`install` の前に `boot` が要る。
（`Unable to lookup in current state: Shutdown` はこれ）

```bash
xcrun simctl list devices booted
xcrun simctl shutdown "iPhone 17"
```

**前作のアプリがシミュレータに残っていると干渉する。** ゆるトレ日記の確認中、
タップが雀算に飛んで混乱した。`xcrun simctl uninstall booted <前作のbundleID>` で外す。

### 4-5. シミュレータへの環境変数は `SIMCTL_CHILD_` 接頭辞

```bash
SIMCTL_CHILD_MYAPP_DEMO=1 xcrun simctl launch booted com.example.App
```

### 4-6. macOSに `timeout` コマンドは無い

GNU coreutils。終了コード127で「実行されていない」のに気づかず時間を溶かす。

### 4-7. `#if DEBUG` が効いているかは実物で確認する

```bash
xcodebuild -configuration Release ... build
strings path/to/App.app/App | grep "デモデータ"   # 何も出なければOK
find path/to/App.app -name "*.storekit"          # 何も出ないこと
```

`.storekit` をプロジェクト管理下（同期フォルダ内）に置いたら、**リリースビルドのapp内に入った。**
`.xcscheme` に手書きでパスを書くのは基準が不明瞭で3回外した。
**Xcodeの Edit Scheme → Run → Options から設定させる**のが確実。

### 4-8. 機能を足したら既存の説明文の整合性を確認する

雀算では「インターネットに接続しません」をプライバシーポリシー・サポートページ・ストア掲載文・READMEの
**4か所**に書いていて、課金を入れて**全部が嘘になった**。
ゆるトレ日記はHealthKitを読むので、雀算のプライバシーポリシーを**そのまま流用できなかった**。
虚偽のプライバシー表示は審査で問題になる典型。

### 4-9. 自動計算と手動クリアは相性が悪い

「1マス消す」と「残りから自動で埋める」を同時に走らせると、
消したマスが即座に埋め直されたり、自動で入っていた別のマスが巻き添えで消えたりする。

**消す操作は消すだけにして、再計算は次に値が確定したときへ回す。**
「選び直したら再計算」も試したが、**巻き添えが遅れて起きるだけで解決しなかった。**

```swift
/// 指定した1マスだけを空に戻す。ここでは意図的に再計算しない。
public mutating func clear(at position: Position) { ... }
```

### 4-10. ForEachに添字を渡すと、削除でアプリが落ちる

`ForEach(items.indices, id: \.self)` は削除で落ちる。件数が減った直後に
SwiftUIが**古い添字のまま再描画**し、配列の範囲外アクセスになる。
雀算ではメンバー削除で実際に落ちた（クラッシュログに
`Array._checkSubscript` → `SettingsView.memberRow` と出る）。

**要素をIdentifiableにして、値そのものを回す。操作もIDで指す。**

```swift
ForEach(roster.members) { member in       // 添字ではなく要素
    Text(member.name)                      // 配列を引き直さない
    Button("削除") { board.remove(id: member.id) }
}
```

消えたIDへの操作は黙って無視されるようにしておくと、取りこぼしがあっても落ちない。

### 4-11. 名前をキーに対応付けると、改名でデータが消える

雀算は「参加者が変わったら名前で列を突き合わせて組み直す」実装だった。
そこへ改名を通したため、**別人が現れたと解釈されて点数が丸ごと消えた。**
しかも入力欄は1文字ごとに反映されるので、**1文字打つたびに消えていた。**

```swift
// ❌ 改名に使ってはいけない（名前で対応付けるため中身が失われる）
session.setPlayers(["中村X", "五十嵐", "斎藤", "佐々木"])

// ✅ 見出しだけ差し替える。列の中身には触らない
session.renamePlayer(at: column, to: newName)
```

**「並べ替え・追加・削除」と「改名」は別の操作として実装する。** → 8節「表示名ではなくIDで記録する」

### 4-12. 「便利機能」が確認ダイアログを迂回することがある

雀算は、メンバーのチェックを外すときに「点数が消えます」の確認を出していた。
ところが**人数プリセット（3人/4人/5人/6人）だけは同じ確認を通らず、無言で点数が消えた。**

**破壊的な変更は、経路をひとつに集約する。**
UIを足したら「その経路も確認を通るか」を必ず確かめる。
雀算はプリセット自体を廃止して解決した（**参加チェックの数＝人数**なので、そもそも不要だった）。

**機能を足す前に「それは既にある情報から導けないか」を疑う。**

### 4-13. SwiftUIの `Button` は中の文字色を上書きする

自前で色を決めているのにボタンの既定色（青）に染まる。`.buttonStyle(.plain)` を付ける。

### 4-14. シートの地色を指定しないとカードが見えない

シートの既定背景は白。`Color(.secondarySystemGroupedBackground)` のカードが同化して**未選択のボタンが消える**。
`.background(Color(.systemGroupedBackground))` をシートに付ける。

### 4-15. CSSでもSwiftでも「名前の衝突」は静かに壊す

- HTMLプロトタイプ：翻訳関数 `t()` がローカル変数 `const t=...` に隠されて呼べなくなった
- CSS：年表示コンテナの `.year{display:none}` が、タイトルに付けた `year` クラスにも当たって消えた

**症状が「無反応」や「消える」になるので、原因に辿り着きにくい。**

### 4-16. 個人登録だと本名が公開される

販売者名・著作権表示に本名が出る。屋号は不可。**登録前に納得しておくこと。**

### 4-17. EU配信にはトレーダーステータス（住所公開）が必要

デジタルサービス法により、氏名・住所・電話の公開が要る。
**配信地域を日本のみに限定すれば不要。** あとから広げるのは審査なしでできる。

### 4-18. 「今日」を起動時に一度だけ決めると、日をまたいで止まる

iPhoneのアプリは**終了しない**。ホームに戻しても裏で生きている。
`init` で `today` を決めて放置すると、翌日開いても昨日のままになる。
ゆるトレ日記は、日付が変わってもカレンダーの「今日」が動かず、歩数も古いままだった。

外部データの読み込み（HealthKit等）を `.task` にだけ書くのも同じ問題。
**`.task` はビューが最初に出たときにしか走らない。** 復帰では走らない。

```swift
@Environment(\.scenePhase) private var phase

.task { await refresh() }                                   // 起動時
.onChange(of: phase) { _, new in                            // 復帰時
    if new == .active { Task { await refresh() } }
}
.onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
    .receive(on: RunLoop.main)) { _ in Task { await refresh() } }   // 前面のまま日をまたいだとき
```

3つとも要る。前面にいると `scenePhase` は変わらないので、日跨ぎは通知でしか拾えない。

**順番に注意。** 日付を進めてからデータを読む。逆だと日付が変わった直後に
「昨日まで」を読んでしまい、今日が空のままになる。
`.task` と `.onChange` が同時に走ることがあるので、再入防止のフラグも要る。

**確認の仕方**（実機で日付を跨がせずに試せる）:
設定 → 一般 → 日付と時刻 → 自動をオフ → 翌日に進める → アプリに戻る。

### 4-19. `set -e` + `grep` の空振りで、スクリプトが無言で死ぬ

```bash
set -e
LINE=$(xcrun devicectl list devices | grep -m1 " connected ")
if [ -z "$LINE" ]; then echo "繋がっていません"; exit 1; fi   # ← ここに来ない
```

grep は一致が無いと終了コード1。`set -e` はその時点でスクリプトを終わらせるので、
**用意したエラーメッセージが表示されない。** 出力ゼロ・終了コード0に見えて、原因が分からない。

```bash
LINE=$(xcrun devicectl list devices 2>/dev/null | grep -m1 " connected " || true)
```

4-1（エラーを握り潰さない）と同じ話がシェルでも起きる、と覚えておく。

### 4-20. `devicectl` の `available (paired)` は「今は繋がっていない」

| 表示 | 意味 |
|---|---|
| `connected` | 今すぐ使える |
| `available (paired)` | 前にペアリングしただけ。**今は使えない** |
| `unavailable` | 電源オフ、または未接続 |

`available` の端末を `-destination` に渡すと
`The developer disk image could not be mounted` で**10分待たされる**。
選ぶのは `connected` だけにして、`-destination-timeout 30` も付けておく。

### 4-21. 保存している構造体のフィールドを変えると、記録が丸ごと消える

`try? JSONDecoder().decode(...)` は**1つでも欠けると nil を返す**。
設定を1項目足しただけのつもりで、同じ入れ物に入っていた記録まで失う。

```swift
// 見つからない項目は既定値で埋めて、必ず読めるようにする
public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    passSteps = try c.decodeIfPresent(Int.self, forKey: .passSteps) ?? 10000
    ...
}
```

**旧版のJSONを直書きしたテストを必ず1本置く。** これが無いと気づけない。

---

## 5. リリース手続き

**順番が重要。** 飛ばすと後で詰まる。

### ① Xcodeにアカウントを追加

Xcode → Settings → Accounts → ＋ → Apple ID。証明書はアーカイブ時に自動生成される。

### ② 【重要】Explicit な App ID を先に登録する

**Xcodeの自動署名はワイルドカード（`TEAMID.*`）のApp IDを作る。**
これだと **App Store Connect のバンドルID選択肢が空**になり、アプリを登録できない。

[developer.apple.com → Identifiers](https://developer.apple.com/account/resources/identifiers/list)
→ ＋ → App IDs → App → **Explicit** → `com.zzzjjj080.アプリ名`

確認は書き出したipaの中を見る。

```bash
security cms -D -i App.app/embedded.mobileprovision > p.plist
/usr/libexec/PlistBuddy -c "Print Entitlements:application-identifier" p.plist
# TEAMID.*                      → ワイルドカード（NG）
# TEAMID.com.zzzjjj080.App      → 正しい
```

### ③ 実機を1台チームに登録する

アーカイブには開発用プロファイルが要り、その作成に実機登録が1台以上必要。
（`Your team has no devices` で止まる）
**USBで繋いでXcodeから一度実行する**のが一番早い。
デベロッパモードは**Macに繋いでXcodeが認識したあとに初めて設定に出てくる。**

**機種変更したら、新しい端末も登録し直す。** プロファイルにUDIDが載っているか確認する。

### ④ App Store Connect でアプリを登録

**これをやる前にアップロードすると失敗する。**

```
Step failed: missingApp(bundleId: "com.zzzjjj080.App")
```

バンドルIDが候補に出なければ**ページをリロード**。

### ⑤ アーカイブとアップロード

```bash
xcodebuild -project App.xcodeproj -scheme App -configuration Release \
  -destination 'generic/platform=iOS' -archivePath /tmp/App.xcarchive \
  -allowProvisioningUpdates archive
```

アーカイブがワイルドカード署名でも問題ない。**配布用の署名は書き出し時に付け直される。**

```xml
<!-- ExportOptions.plist -->
<key>method</key><string>app-store-connect</string>
<key>teamID</key><string>A7WA598R44</string>
<key>signingStyle</key><string>automatic</string>
<key>uploadSymbols</key><true/>
<key>destination</key><string>upload</string>
```

```bash
xcodebuild -exportArchive -archivePath /tmp/App.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath /tmp/export \
  -allowProvisioningUpdates
```

`destination` を `upload` にすれば、**app-specific password も APIキーも不要**。
`Upload succeeded` が出れば成功。

アップロード前に必ず確認すること。

```bash
A=/tmp/App.xcarchive/Products/Applications/App.app
/usr/libexec/PlistBuddy -c "Print CFBundleVersion" $A/Info.plist        # ビルド番号
codesign -d --entitlements - $A | tr ',' '\n' | grep -i healthkit      # 権限
strings $A/App | grep -i "DEMO"                                        # デモデータ
find $A -name "*.storekit"                                             # テスト用ファイル
```

**同じビルド番号は再アップロードできない。** 上げ直すときは必ず `CFBundleVersion` を増やす。

### アップロードは App Store Connect の APIキーで通す

`destination = upload` は Xcode に保存されたアカウントを使うため、**セッションが切れると
コマンドラインから上げられなくなる。**サインインし直しても直らないことがある。

```
error: exportArchive Failed to Use Accounts
Failed to find an account with App Store Connect access for team A7WA598R44
```

**APIキーを作っておけば、この経路を完全に迂回できる。**

- App Store Connect → ユーザーとアクセス → 統合 → App Store Connect API
- アクセス権は **App Manager**。生成した `.p8` は**一度しかダウンロードできない**
- 置き場所は `~/.appstoreconnect/private_keys/AuthKey_<キーID>.p8`（`chmod 600`）
- **Issuer ID** はキー一覧の上に出ている

```bash
xcodebuild -exportArchive -archivePath /tmp/App.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath /tmp/export \
  -allowProvisioningUpdates \
  -authenticationKeyPath ~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8 \
  -authenticationKeyID XXXXXXXXXX \
  -authenticationKeyIssuerID xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

雀算のキー: `CH8R5RJGXQ` / Issuer `cfeb84ca-47e6-45b2-8c5f-192212240b6c`

**⚠️ Downloads フォルダはClaude Codeから読み書きできない**（macOSの保護。`ls` は通るが
`cp`/`mv` が `Operation not permitted` になる）。ダウンロードしたファイルを使うときは、
**本人にFinderでドラッグしてもらう。**

### ⑥ 掲載情報

**スクリーンショットは、欄に表示されている寸法しか受け付けない。**

| 欄 | 必要な寸法 |
|---|---|
| iPhone 6.9インチ | 1320×2868（iPhone 17 Pro Max シミュレータがこの解像度） |
| iPhone 6.5インチ | 1242×2688 |

**現在のApp Store Connectは6.5インチ枠しか出ないことがある。** 両方作っておくのが安全。
6.9インチだけ登録すれば他サイズはApple側で自動縮小される、という話は枠が出ている場合のみ。

**iPad / Apple Watch のタブは、ビルドを添付するまで要求されてくる。** iPhone専用なら添付後に消える。

⚠️ **説明文は plain text の単独ファイルで用意すること。**
Markdownの中にコードブロックで置くと、ファイル全体をコピペする事故が起きる（実際に起きた）。
`store/description.txt` のように、**そのまま貼れる形で置く。**

### ⑦ 「審査用に追加」を押すまでに必要なもの

**チェックリスト。1つでも欠けると押せない。**

- [ ] スクリーンショット（正しい寸法で）
- [ ] プロモーション用テキスト（170字）
- [ ] 概要（4000字）
- [ ] キーワード（100字・カンマ区切り・**スペース禁止**）
- [ ] **サポートURL**（GitHub Pages。**公開してから入れる**。404を審査で踏ませない）
- [ ] **バージョン**（`1.0`。空欄になりがち）
- [ ] **著作権**（`2026 Jin Nakamura` 形式。©は不要）
- [ ] ビルドを選択 → **ビルド行の「管理」→ 暗号化「いいえ」**（ビルドごとに聞かれる）
- [ ] **「サインインが必要です」のチェックを外す**（ログイン無しのアプリ。外さないとユーザ名/パスワードが必須になる）
- [ ] 連絡先情報（名・姓・電話・メール）
- [ ] App Reviewのメモ（6節）
- [ ] リリース方法（**手動**を推奨）
- [ ] **別ページ:** アプリのプライバシー → ポリシーURL＋「データを収集しません」
- [ ] **別ページ:** 価格および配信状況 → 無料 ＋ **日本のみ**

### ⑧ GitHub Pages

```bash
git remote add origin git@github.com:zzzjjj080/<repo>.git
git push -u origin main
```

Settings → Pages → Source: **Deploy from a branch** → Branch: **main** → フォルダ: **`/docs`**
（既定は `/ (root)` なので必ず変更する）。反映に1〜3分。

```bash
curl -s -o /dev/null -w "%{http_code}" https://zzzjjj080.github.io/<repo>/
```

---

## 6. 初回提出は Guideline 2.1 で却下されると思っておく

2本とも初回提出で **Guideline 2.1 - Information Needed** に当たった。
バグではなく「情報が足りない」。**新規アプリではよくある。**

Appleが求めてくる7項目。

1. **実機で撮った画面録画**（起動から主要機能まで。権限ダイアログも含める）
2. テストした端末とOSの一覧
3. アプリの機能と対象ユーザー、解決する問題
4. 主要機能への到達手順（ログイン情報があれば含む）
5. 使っている外部サービス・ツール・プラットフォーム
6. 地域による差異の有無
7. 規制産業か、第三者の保護された素材を使っているか

**対策：最初から「App Reviewに関する情報 → メモ」に全部書いておく。**
Apple自身が「今後の提出ではメモ欄に入れておくように」と書いてくる。

**書いておくべきこと（テンプレ）**

```
No account, login, or credentials are required. No in-app purchases,
no subscriptions, no user-generated content, and no network connections.

IMPORTANT FOR REVIEW: [審査環境で挙動が変わる点をここに書く]
例）the app reads step counts from HealthKit. On a review device there is
usually no step history, so every day shows 20 points. This is expected
and does not indicate a malfunction.

How to exercise the app:
1. ... （主要機能への手順を番号で）

External services: none. Only Apple frameworks (...). All data stays on the device.
Regional differences: none.
Not a medical app. No diagnosis, treatment, or health claims.
```

**審査環境で挙動が変わる点は必ず書く。** ゆるトレ日記は歩数が0になるので、
書かないと「機能していない」と誤解される。

### 返信は4000字制限

App Reviewへの返信欄は**4000字まで**。7項目を全部書くと超えるので削る必要がある。
英語で書く（App Reviewは英語で読む）。

### 却下されたら、まずビルドの中身を疑う

ゆるトレ日記は「情報不足」で却下されたが、**そのビルドには実際にHealthKitの不具合があった**。
雀算も、返信を準備している間に**メンバー削除のクラッシュが見つかった**。
情報だけ返信していたら、次はバグで落ちていた。

**却下は修正のチャンス。** 返信前に、指摘された箇所以外も実機で一通り触ること。
新しいビルドを上げてから返信し、**返信文に「新しいビルドを上げた」と明記する。**
順番は「ビルド差し替え → 返信 → 再提出」。返信だけでは審査は再開しない。

### 審査中に見つけた修正は、上げずに次バージョンへ回す

雀算はプリセット廃止と改名バグの修正をコミット済みだが、
**1.0(2) の審査が動いている間はアップロードしなかった。**
審査中にビルドを差し替えると、審査がやり直しになる。
**コミットはする。アップロードは審査の結果が出てから。**

---

## 7. 使い回せる道具

### アプリアイコン — `Tools-MakeIcon.swift`

Swift + CoreGraphics で1024×1024を生成。デザインツール不要。

```bash
swiftc -O Tools-MakeIcon.swift -o /tmp/makeicon && /tmp/makeicon AppIcon.png
sips -Z 180 AppIcon.png --out /tmp/small.png   # 縮小して判別できるか必ず確認
```

**コツ**
- ホーム画面では60px程度まで縮む。**細い線や模様は消える**のでシルエットで見せる
- 角丸マスクで端が欠ける。**全体を86%程度に縮めて余白を確保**
- 要素は粗く。ゆるトレ日記はカレンダーを7列でなく**4×4**にした
- **文字よりシルエット。** 雀算は「雀」の字をやめて雀（鳥）の形にした

Assetsへは `AppIcon.appiconset/Contents.json` の `platform: ios` かつ `appearances` の無い項目に `filename` を足すだけ。

### スクリーンショット — `store/MakeScreenshots.swift`

生スクショに見出しを載せて指定サイズに組む。**サイズは引数で渡せるようにしておく。**

```bash
/tmp/makeshots store/raw store/screenshots              # 6.9インチ(1320x2868)
/tmp/makeshots store/raw store/screenshots-65 1242 2688 # 6.5インチ
```

**素材の撮り方**：`#if DEBUG` かつ環境変数でデモデータを入れ、シミュレータで撮る。

```bash
SIMCTL_CHILD_APP_DEMO=1 xcrun simctl launch booted com.zzzjjj080.App
xcrun simctl io booted screenshot store/raw/01.png
```

### 実機インストール — `install-device.sh`

接続中の端末を自動で選ぶので、機種変更しても書き換え不要。（2節⑤参照）

---

## 8. 設計で効いたこと

### 型であり得ない状態を作れなくする

```swift
// 0を持たないので「選んでいない＝キーが無い」と一意に決まる
public enum Volume: Int { case one = 1, two = 2, three = 3 }
public var parts: [BodyPart: Volume]
```

```swift
// 「空」「お休み」「手入力」「自動計算」を1つの型で表す。
// Int? と Bool の組み合わせで持つと、あり得ない組み合わせが作れてしまう
public enum Entry: Equatable, Sendable, Codable {
    case empty
    case resting
    case entered(Int)
    case derived(Int)
}
```

Bool複数で持つと必ず破綻する。

### 日付は `Date` ではなく専用の値型

```swift
public struct YMD: Hashable, Comparable, Codable { let year, month, day: Int }
```

カレンダーアプリが扱うのは「何月何日」であって時刻ではない。
`Date` だとタイムゾーンや夏時間で日付が前後する。**UTC固定のグレゴリオ暦で計算する。**

### 表示名ではなくIDで記録する

設定で名前を変えられるものは、**必ずidで記録して名前は表示専用にする。**
名前で記録していると、改名した瞬間に過去の記録が迷子になる。（→ 4-11で実際に消えた）

**UIのループも、配列操作も、全部IDで指す。**（→ 4-10のクラッシュも同じ原因）

```swift
public func index(of id: Member.ID) -> Int?
public mutating func rename(id: Member.ID, to name: String)
public mutating func remove(id: Member.ID)
```

### 破壊的な操作の経路を数え上げる

「このデータが消える可能性がある操作」を全部書き出して、
**すべてが同じ確認ダイアログを通るかを確認する。**
雀算では、参加チェックは確認を通るのにプリセットは通っていなかった（4-12）。

確認文は**何が起きるかを具体的に書く。**
「削除しますか？」ではなく「この対局に入力済みの点数も一緒に消えます。」

### 過去のデータを後から書き換えない

ゆるトレ日記は「3日経つとその日の点数を確定」する。
確定後は設定を変えても動かない。**過去のカレンダーが丸ごと書き換わるのを防ぐため。**

ただし**確定日を編集したときだけ、その日を計算し直して確定し直す。**
これが無いと「忘れてた記録を足したのに点が変わらない」という別のバグになる。

同様に、保存済みの記録には**その時の表示設定も一緒に保存する。**
雀算は小数モードを保存し忘れて、記録が10倍で表示された。

### 集計の起点を持つ

ヘルスケアは何年ぶんでもデータを持っているので、起点が無いと過去が全部0%になる。
「本人が最初に入力した日」を起点にし、**ユーザーが手動で指定もできる**ようにした（機種変更対策）。

### 色は「文字が読める明度」から逆算する

カレンダーのマスの文字を黒で統一するなら、**塗りを黒文字が読める明度だけで組む。**
明度で区別できなくなるぶん、**色相の差**で分ける。
コントラスト比はコードで実測する（WCAG AA = 4.5:1）。

### 設定は種類ごとにタブを分ける

「表示」「点数」「データ」を混ぜると、**色を触るつもりで採点式を変えてしまう。**
リセットボタンもタブごとに分ける。タブ切り替えでシートの高さが変わらないよう固定する。

**破壊的な項目は同じセクションに固めない。** 誤タップの距離を稼ぐ。

### 「おかしい」を見えるようにする

雀算は、合計が0にならない局に「!」を赤で出す。
**間違いを防ぐより、間違いに気づける方が安上がり。**

### 触覚は「押した」と「変わった」で強さを分ける

```swift
// キーを押した = .rigid（軽く固い）／盤面が動いた = .medium（確定感）
```

`UIImpactFeedbackGenerator` は**使い回して `prepare()` しておく。**
毎回作ると1打目が鳴らない。WebのVibration APIはiOSで動かないので、ここは実機アプリの利点。

### 削るものを決めたら守る

ゆるトレ日記は「重さも回数も記録しない」が商品。
機能を足したくなったら、**それが核心を壊さないか**を毎回確認する。

**足す前に「既にある情報から導けないか」を疑う。**
雀算の人数プリセットは、参加チェックの数を見れば要らなかった。

---

## 9. Claude Codeへの依頼で効果的だった指示

- **「ビルドが通った」で終わらせず、シミュレータで実際にタップして確認させる**
- **修正したら実機にも入れさせる**（触覚は実機でしか分からない。デバッグの都度、最新にさせる）
- 変更のたびに**小さくコミット**させる（日本語で、**なぜそうしたか**を書かせる）
- 推測で答えさせない。**バイナリを検索する・実際に起動する・curlで確認する**
- 間違えたときは**その場で認めて訂正させる**
- 仕様が技術的に矛盾するときは、**言われた通りに作らせず矛盾を指摘させる**
- **数値の仕様は「条件を先に言って、式を導出させる」**
  （ゆるトレ日記の採点式は、5つの条件を与えて一次式を導出させた）
- **検算をコードで実行させる**（目視で確認しない）
- **「本当にそうなっているか、もう一度確認して」は効く。**
  雀算の確認ダイアログの穴（4-12）はこの一言で見つかった
- **直したバグは、再現するテストを書かせてから直させる**

---

## 10. 2本の最終状態

### 雀算（麻雀スコア記録）

- https://github.com/zzzjjj080/jansan / https://zzzjjj080.github.io/jansan/
- `com.zzzjjj080.Jansan` / App ID 6802013584
- Core 45本超 / **1.0 (2) 審査中**（初回はGuideline 2.1で却下 → クラッシュ修正して再提出）
- 次バージョン分として実装済み・未提出：人数プリセット廃止 / 改名で点数が消えない修正 / 削除確認の文言改善
- 未実装: カンパ（銀行・税務情報の登録待ち）

### ゆるトレ日記（健康カレンダー）

- https://github.com/zzzjjj080/yurutore / https://zzzjjj080.github.io/yurutore/
- `com.zzzjjj080.Yurutore`
- iOS 18.0以降 / iPhone / 縦向き / 日本のみ / 無料 / 日英2言語
- **Core 54本** + アプリ層
- **審査待ち**（1.0 build 2。初回はGuideline 2.1で却下 → 修正して再提出）
- 次のアップデート分として「記録の開始日の指定」を実装済み（未提出）
- 未実装: カンパ（プロトタイプには実装済み。Swift移植は銀行・税務の完了後）

---

## 11. カンパ（App内課金）を入れる場合

**無料アプリなら銀行口座も税務情報も不要。だが課金を1つ入れると全部必要になる。**

- 有料App契約への同意
- 銀行口座の登録（**口座名義は半角ローマ字**。通帳のカナと綴りを合わせる）
- 税務情報の提出（日本＋米国向け W-8BEN）
- **Small Business Program に申請**（30% → 15%）

**アプリ完成を待たずに始められる**ので、最初に着手するのが得策。承認に時間がかかる。

課金を後回しにして先に無料でリリースする判断もできる（2本ともこの方針）。
その場合、**プライバシーポリシーが単純になる**（通信するものが無い）という副次的な利点がある。

`.storekit` はプロジェクト配下に置かない（アプリに同梱される → 4-7）。
Xcodeの Edit Scheme → Run → Options から設定するのが確実。

---

## 12. 検証コマンド集

```bash
# ロジックのテスト（Xcode不要・速い）
cd Core && swift test

# シミュレータ
xcrun simctl list devices booted
xcrun simctl boot "iPhone 17 Pro Max"
xcrun simctl install booted /path/App.app
SIMCTL_CHILD_APP_DEMO=1 xcrun simctl launch booted com.zzzjjj080.App
xcrun simctl terminate booted com.zzzjjj080.App   # 永続化の確認に使う
xcrun simctl io booted screenshot out.png
xcrun simctl uninstall booted com.zzzjjj080.App   # 初回起動の再現
xcrun simctl pbpaste booted                       # コピー機能の確認

# 実機
xcrun devicectl list devices
./install-device.sh

# アーカイブの中身
codesign -d --entitlements - App.app | tr ',' '\n' | grep -i healthkit
/usr/libexec/PlistBuddy -c "Print CFBundleVersion" App.app/Info.plist
security cms -D -i App.app/embedded.mobileprovision > p.plist
/usr/libexec/PlistBuddy -c "Print Entitlements:application-identifier" p.plist
find App.app -name "*.storekit"
strings App.app/App | grep -i "DEMO"

# クラッシュログ（実機で落ちたとき）
ls -t ~/Library/Logs/CrashReporter/MobileDevice/*/*.ips | head

# 公開ページ
curl -s -o /dev/null -w "%{http_code}" https://zzzjjj080.github.io/<repo>/
```

**永続化の確認は必ず `terminate` → `launch`。** 画面遷移だけでは確認にならない。

---

## 13. このファイルの更新ルール

- **新しく踏んだ罠は、その日のうちにここへ書く。** 後で思い出せない。
- 書くのは「次のアプリでも使う話」だけ。アプリ固有の仕様は各リポジトリのREADMEへ。
- **どちらのチャットからも、このファイルを更新する。**
  更新したら、もう一方のチャットに「iOS-DEVLOG.md の〇〇を更新した」と伝える。

---

## 14. このファイルの所在

- **正本（編集するのはこちら）**: `~/.claude/iOS-DEVLOG.md`
  - `~/.claude/CLAUDE.md` から参照されているので、どのチャットでも自動で案内が出る
  - `~/Claude/iOS-DEVLOG.md` は正本へのシンボリックリンク
- **バックアップ**: このリポジトリの `iOS-DEVLOG.md`（正本を更新したらコピーしてpush）
