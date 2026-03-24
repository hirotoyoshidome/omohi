# omohi

結果だけでなく、過程から知識を積み上げる。

[English](./README.md)

## なぜ長期のプロセス保存が必要か

その時は妥当だった意思決定でも、数カ月後・数年後には再現が難しくなります。
コードや最終成果物は残っても、判断に至った過程は失われがちです。

omohi は、その過程をローカルの永続データとして残すために作られています。
何を追跡し、いつ記録し、どう再参照するかを明示的に扱います。

## omohi とは

omohi は process logging のための local-first CLI です。
次の 3 つを明確に分離します。

- Tracking: 何を記憶対象にするかを定義する。
- Recording: 必要な時点を意図的に記録する。
- Referencing: 破壊せずに履歴を再参照する。

## 時間軸でみるツールの棲み分け

これらのツールは競合ではなく補完関係です。

- Git はプロジェクト単位のソース管理（ブランチ、差分、協業フロー）に強い。
- Notion / Obsidian は可読性の高い整理や短中期のノート運用に強い。
- omohi は長期スパンでの意思決定プロセスと文脈の継続性に最適化している。

omohi は他ツールの代替ではなく、別の境界を担当します。

## 価値観と哲学

- デフォルトで local-first。
- 結果だけでなく過程を保存する。
- 便利さより耐久性と境界の明確さを優先する。
- 履歴を非破壊で扱うことを原則にする。
- データの主導権を個人に残す。

## やらないこと

- Web アプリ化しない。
- アカウント、認証、ホスティングを提供しない。
- コア機能としてのリモート永続化や共有を提供しない。
- Git 連携をコアモデルにしない。
- 初期スコープでブランチ / 差分モデルを持たない。

## なぜ CLI を先に作るのか

omohi は長い時間軸で使い続けることを前提にしています。
CLI を先に設計することで、日常の workflow や自動化へ組み込みやすくしています。

## インストール

### 最新の GitHub Release からセットアップする

1. 最新リリースページを開きます:
   [github.com/hirotoyoshidome/omohi/releases/latest](https://github.com/hirotoyoshidome/omohi/releases/latest)
2. 利用する OS / architecture に合うアーカイブを選んでダウンロードします:
   - Linux x86_64: `omohi-<tag>-linux-x86_64.tar.gz`
   - Linux arm64: `omohi-<tag>-linux-arm64.tar.gz`
   - macOS x86_64: `omohi-<tag>-macos-x86_64.tar.gz`
   - macOS arm64: `omohi-<tag>-macos-arm64.tar.gz`
3. アーカイブを展開し、`omohi` バイナリを `PATH` の通ったディレクトリに配置します。例: `~/.local/bin`

```sh
tar -xzf omohi-<tag>-<os>-<arch>.tar.gz
mkdir -p ~/.local/bin
mv omohi ~/.local/bin/omohi
chmod 755 ~/.local/bin/omohi
```

4. 必要であれば、シェルの設定ファイルにインストール先を追加します:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

各リリースには対応する `.sha256` ファイルも含まれているため、必要ならダウンロードしたアーカイブを検証できます。

### ソースコードからビルドする

```sh
./install.sh
```

```sh
./install.sh --prefix /custom/path --optimize ReleaseFast
```

```sh
./install.sh --skip-tests
```

未リリースの `main` を試したい場合や、手元の checkout からそのままビルドしたい場合はこの方法を使ってください。

## ビルドとテスト

```sh
make build
make test
```

## 基本コマンド

コマンドの詳細仕様は `docs/cli.md` を参照してください。
ここでは最小の運用フローのみ示します。
相対パス・絶対パスのどちらでも指定できます。相対パスは実行時のカレントディレクトリを基準に解決されます。

```sh
# 1) ファイルを追跡対象として登録
omohi track ./note.md

# 2) 現在内容をステージ
omohi add ./note.md

# 3) メッセージ付きで記録
omohi commit -m "capture decision background"

# 4) 状態確認
omohi status

# 5) 履歴の検索と参照
omohi find --tag architecture --date 2026-03-18
omohi show <commitId>
```

タグ操作は `omohi tag add`, `omohi tag ls`, `omohi tag rm` を利用できます。

## データと安全性の要点

- 保存先: `~/.omohi`
- 永続化はローカルファイルベース。
- 破壊的操作はロックで保護される。
- 書き込みは耐久性を意識した atomic write を前提とする。

## 現在できることと、これからの方向性

現時点の omohi は、信頼できる「記録の基盤」にフォーカスしています。
そのため、機能が少なく見えるのは設計上の意図です。

今後は、蓄積されたプロセスログの活用価値を高め、
長期スパンでも意思決定の文脈が失われない状態を目指します。

## ドキュメント

- CLI リファレンス: [docs/cli.md](./docs/cli.md)
- English README: [README.md](./README.md)

## コントリビューション

バグ報告、機能提案、ドキュメント改善を歓迎します。
提案や報告は GitHub Issues から投稿してください。まずはコントリビューションガイドを確認してください。

- ガイド: [CONTRIBUTING.md](./CONTRIBUTING.md)
- Issue テンプレート: [`.github/ISSUE_TEMPLATE`](./.github/ISSUE_TEMPLATE)

## ライセンス

このプロジェクトは MIT License の下で公開されています。詳細は [LICENSE](./LICENSE) を参照してください。
