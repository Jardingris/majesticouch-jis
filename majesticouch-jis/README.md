# Majestouch JIS Helper

Majestouch Convertible 3をWindows 11とMacでBluetooth共有するとき、Mac側で次の2件を設定する。DIP6=OFFを前提とする。

| キー | 入力HID値 | 出力HID値 | 動作 |
|---|---|---|---|
| 無変換 | `0x70000008B` | `0x700000091` | 英数 |
| 変換 | `0x70000008A` | `0x700000090` | かな |

## 動作

`IOHIDManager`のmatchingは、`kIOHIDProductKey`にCFStringの`Majestouch Convertible3`を指定する。完全一致したデバイスの初期列挙・接続通知でだけ、`/usr/bin/hidutil property --matching '{"Product":"Majestouch Convertible3"}' --set ...`を1回実行する。同じProduct名を持つMajestouchには同じ設定を適用する。AppleやLogitechなど別名のキーボードは対象外。

`IOHIDManagerCreate`にはSDKの`kIOHIDManagerOptionIndependentDevices`を渡す。デバイスをopen/seizeせず、入力レポート・キー入力を登録／取得しない。`IOHIDManagerRegisterDeviceMatchingCallback`と削除callbackを登録し、`IOHIDManagerScheduleWithRunLoop`後は`CFRunLoopRun`でイベントを待つ。タイマー、ポーリング、接続状態の定期確認はない。

hidutilはshellを介さず`posix_spawn`で固定引数を渡す。`waitpid`で対象の子を回収し、`EINTR`なら終了待ちだけを続ける。重複通知は同じマッピングの再設定となる。hidutil失敗はログへ記録して次の接続イベントを待つ。タイマーでの再試行はしない。SIGTERM/SIGINTは標準libdispatchのシグナル通知でrun loopを止め、終了する。hidutilの短い実行中に終了要求を受けた場合は、子の終了を待ってから処理する。

macOS標準のCoreFoundation・IOKit・libdispatchとコマンドだけを使う。sudo、外部ライブラリ、Homebrew、GUI、追加の署名操作、アクセシビリティ／入力監視の設定変更は使わない。arm64実行ファイルにリンカーが付ける標準のadhoc署名はそのまま使う。

## インストール・更新

ログイン中のMacユーザーで、クローン先の`majesticouch-jis/`ディレクトリから実行する。

```sh
sh install.sh
```

更新時も同じコマンドを使う。Apple Command Line Toolsがなければビルド段階で停止し、既存Agentを変更しない。依存関係は自動インストールしない。

1. `/usr/bin/clang -std=c11 -Wall -Wextra -Wpedantic -Werror -O2`で一時ビルドする。
2. plistを生成・検証する。
3. 旧plist、旧バイナリがある場合はそのコピー、launchd登録状態、Majestouchのマッピング出力をバックアップする。
4. 同じlabelのAgentをbootoutし、バイナリ・plistを置換する。
5. `launchctl bootstrap gui/$(id -u)`と`kickstart`で起動する。`KeepAlive`で既に起動していれば再起動しない。
6. 一度だけ1秒待ち、プロセスの常駐と接続中のマッピングを検証する。この待ちはインストール確認用で、常駐ヘルパーやAgentには含まれない。

インストール処理中の失敗は、表示したバックアップへの自動復元を試みる。復元が失敗した場合は明示的にエラーを出し、手動復元コマンドを表示する。

配置先：

- 実行ファイル：`~/Library/Application Support/MajestouchJIS/majesticouch-jis`
- LaunchAgent：`~/Library/LaunchAgents/local.majesticouch.jis-mac.plist`
- イベント／エラーログ：`~/Library/Logs/MajestouchJIS.log`
- バックアップ：`~/Library/Application Support/MajestouchJIS/backups/install.<日時>.<識別子>/`

Agentは`RunAtLoad=true`、`KeepAlive=true`。`StartInterval`、`StartCalendarInterval`、`WatchPaths`、接続監視用タイマーはない。ヘルパーが異常終了した場合のlaunchd再起動は通常のKeepAlive動作となる。

## 状態確認

```sh
launchctl print gui/$(id -u)/local.majesticouch.jis-mac
plutil -p "$HOME/Library/LaunchAgents/local.majesticouch.jis-mac.plist"
pgrep -x majesticouch-jis
ps -p "$(pgrep -x majesticouch-jis)" -o pid,ppid,state,%cpu,time,command
tail -20 "$HOME/Library/Logs/MajestouchJIS.log"
hidutil list --matching '{"Product":"Majestouch Convertible3"}'
hidutil property --matching '{"Product":"Majestouch Convertible3"}' --get UserKeyMapping
```

hidutilの表示は10進数：`30064771211 → 30064771217`と`30064771210 → 30064771216`が期待値。接続していない場合はそのサービスの値が表示されない。

他キーボードの比較：

```sh
hidutil property --matching '{"Product":"Apple Magic Keyboard"}' --get UserKeyMapping
hidutil property --matching '{"Product":"USB Receiver"}' --get UserKeyMapping
hidutil property --get UserKeyMapping
```

このヘルパーが設定する2件はMajestouchサービスだけに存在する。ほかのツールによる既存マッピングの有無は変更前後で比較する。

## Bluetooth切替・ログイン試験

1. Macで無変換→英数、変換→かなを実際に押して確認する。
2. `tail -f "$HOME/Library/Logs/MajestouchJIS.log"`で通知ログを開く。
3. キーボードをWindows側へ切り替え、MacのHID一覧からMajestouchが消え、`disconnected`が記録されることを確認する。
4. Mac側へ戻す。`connected: Majestouch Convertible3; hidutil exit=0`が新しく1件記録され、上記hidutilの2件が入ることを確認する。
5. Bluetooth接続が完了したら意図的な待ち時間を入れずに両キーを押す。これを複数回繰り返す。hidutilのexit=0だけではキー動作まで確認したことにはならない。
6. 数分放置して、同じPIDのCPU時間とログ件数が増えないことを確認する。USB ReceiverやMagic Keyboardの値も比較する。
7. 作業を保存してログアウト／ログインまたは再起動する。上記launchctl出力にrunningとPIDが出ることを確認し、接続済みでの起動とログイン後の接続の両方でキーを試す。

インストールすると、ログイン時の自動ロード対象になるplistをユーザーのLaunchAgentsへ配置する。ログアウト／再起動はスクリプトから実行しない。IOHIDManagerの再列挙通知はAPIで裏付けられるが、実Bluetooth切替での通知順序と最初のキーの操作結果はこの手順で実機確認する。

## アンインストール

```sh
sh uninstall.sh
```

Agentをbootoutし、plistと実行ファイルをバックアップへ退避する。Majestouch限定の`UserKeyMapping`を空配列にする。別のキーボードへは設定しない。ログ・バックアップ・ソースは保持する。未接続の場合、そのデバイスの設定は既にHIDサービスとともに消えている。

## 以前の状態へ戻す

インストール時に出た**その回の**バックアップディレクトリを指定する。

```sh
sh uninstall.sh --restore "$HOME/Library/Application Support/MajestouchJIS/backups/install.<日時>.<識別子>"
```

現在のヘルパーを停止・退避し、旧plistと旧バイナリを復元する。旧Agentが登録されていた場合だけ再登録する。1秒ポーリング版から移行した場合は、その回のバックアップから従来版へ戻せる。復元モードは現在のマッピングをclearせず、旧Agentが設定を適用する。同じ2件のマッピングを持つ旧構成からの移行では一致する。`mapping-before.txt`は確認用の記録で、任意の別マッピングを自動で読み戻す仕組みではない。

アンインストール操作の取り消しも、表示された`uninstall.<日時>.<識別子>`を同じ`--restore`へ指定できる。

## ビルド・テスト

```sh
sh tests/run.sh
clang -std=c11 -Wall -Wextra -Wpedantic -Werror -O2 \
  src/majesticouch-jis.c -framework IOKit -framework CoreFoundation \
  -o /tmp/majesticouch-jis
clang --analyze -std=c11 -Wall -Wextra -Wpedantic src/majesticouch-jis.c
```

テストは実際のcallbackに対し、HIDプロパティ取得とプロセス起動／終了だけをテスト内で置換する。別Product名・欠落・型違い・callbackエラーでは起動しないこと、固定のマッチングとHID値、重複通知、`EINTR`、起動失敗・子の異常終了・終了回収を検証する。Bluetoothやキー入力を模擬して合格扱いにはしない。

インストーラーの実際のplist生成部分も実行し、ProgramArgumentsが実行ファイル1件だけであること、空白や`&`を含むパス、StartIntervalがないことを確認する。

## 一次資料

- Apple SDK：`/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/IOKit.framework/Headers/hid/IOHIDManager.h`（列挙・接続callback・IndependentDevicesの説明）
- 同SDKの`IOHIDDeviceKeys.h`（`kIOHIDProductKey = "Product"`）
- ローカルの`man 5 launchd.plist`、`man 2 posix_spawn`、`man 2 waitpid`、`man 3 dispatch_source_create`
- `/usr/bin/hidutil property --help`（Product matching）
- [Apple IOHIDManager.h](https://developer.apple.com/documentation/iokit/iohidmanager_h)
- [Apple Technical Note TN2450](https://developer.apple.com/library/archive/technotes/tn2450/_index.html)（マッピングのライフサイクルとhidutil）
