# Majestouch JIS Helper

FILCO Majestouch Convertible 3をWindows 11とmacOSでBluetooth共有するとき、Mac側の無変換を英数、変換をかなへリマップする小さな常駐ヘルパー。

IOKit / IOHIDManagerの接続通知で、Product名が`Majestouch Convertible3`と完全一致するデバイスだけに設定する。初期列挙にも対応し、ポーリングは使わない。macOS標準のC・CoreFoundation・IOKit・libdispatch・hidutilを使い、外部アプリ・ライブラリ・sudoは不要。

## インストール

Apple Command Line Toolsが利用できるMacで、ログイン中のユーザーとして実行する。DIP6=OFFを前提とする。

```sh
git clone https://github.com/Jardingris/majesticouch-jis.git
cd majesticouch-jis/majesticouch-jis
sh install.sh
```

同じProduct名とHIDコードの個体が対象。同名の個体を複数接続した場合はすべてに適用する。インストール時にそのMac用のバイナリをビルドする。

## 更新・削除・復元

クローン先の`majesticouch-jis/`ディレクトリで操作する。

```sh
# リポジトリを更新して再インストール
git pull --ff-only
sh install.sh

# ヘルパーを停止・退避し、Majestouch限定のマッピングを解除
sh uninstall.sh
```

インストーラーは既存の同名LaunchAgent・実行ファイルをバックアップする。旧構成への復元方法と実機確認手順は[詳細README](majesticouch-jis/README.md)を参照。

## 検証範囲

macOS 27.0.1 / arm64、Apple clang 21.0.0、Majestouch Convertible 3の1個体で検証した。

- 警告をエラー扱いにしたビルド、静的解析、callbackとplist生成のテストが通過。
- 初期列挙、Bluetooth切断・再接続後のマッピング再適用、他キーボードの設定不変を実測。
- アイドル時のCPU 0.0%、run loopのイベント待機、定期hidutil起動がないことを観測。
- 接続直後のキー動作と再起動後の自動起動・キー動作はユーザーの実機確認による。

他のmacOSバージョン・CPUアーキテクチャ・個体での動作は未検証。実機の生ログ、デバイスの識別値、バックアップはこのリポジトリには含めない。

## ビルド・テスト

```sh
cd majesticouch-jis
sh tests/run.sh
```

実装は[単一のCソース](majesticouch-jis/src/majesticouch-jis.c)。インストール先・アンインストール・ロールバック・使用APIの一次資料は[詳細README](majesticouch-jis/README.md)にまとめている。
