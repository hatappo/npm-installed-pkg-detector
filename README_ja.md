
<div align="center"> <a href="README.md">en</a> | ja </div>

--------------------------------------------------------------------------------

`package-lock.json` ファイル内の npm パッケージとそのバージョンを検出するためのツールのコレクション


# 1. detect.sh

package-lock.jsonから複数のnpmパッケージとバージョンを一括検出するツール

## 必要要件

- bash / zsh
- jq

### サポート対象

このツールは **lockfileVersion 3** （npm 7以降で生成されるpackage-lock.json形式）のみをサポートしています

## 使用方法

```bash
./detect.sh <list-file-path> [lock-file-path]
```

- `list-file-path`: 検出対象のパッケージリストファイル（必須）
- `lock-file-path`: package-lock.jsonのパス（省略時: ./package-lock.json）

## 終了ステータス

- `0`: 正常終了（バージョン一致なし）
- `1`: エラー
- `2`: バージョン一致あり

## リストファイルの形式

```
jest ( 29.7.0 , 29.6.0 )
typescript ( 5.3.3 )
express
```

## 実行例

```bash
# 通常実行（検出されたもののみ表示）
$ ./detect.sh package-list.txt
✓ jest: 検出 (対象バージョン: 29.7.0 )
  → バージョン 29.7.0: 検出
✓ typescript: 検出 (対象バージョン: 5.3.3 )
  → バージョン 5.3.3: 検出

=== 検出結果サマリ ===
検出パッケージ数: 2/3, 検出バージョン数: 2/3

# 詳細モード（未検出も表示）
$ VERBOSE=1 ./detect.sh package-list.txt
✓ jest: 検出 (対象バージョン: 29.7.0 )
  → バージョン 29.7.0: 検出
  → バージョン 29.6.0: 未検出
✗ express: 未検出

=== 検出結果サマリ ===
検出パッケージ数: 1/2, 検出バージョン数: 1/2
```

## 環境変数

- `VERBOSE=1`: 検出した場合だけでなく未検出のすべて出力する。

--------------------------------------------------------------------------------

# 2. detect-remote.sh

GitHubリポジトリの package-lock.json を直接チェックできるツール

## 必要要件

- gh (GitHub CLI) - 事前に認証が必要 (`gh auth login`)
- jq
- base64

## 使用方法

```bash
./detect-remote.sh <org/repo> <list-file-path>
```

- `org/repo`: GitHubリポジトリ（例: facebook/react）
- `list-file-path`: 検出対象のパッケージリストファイル

## 実行例

```bash
# リモートリポジトリのパッケージをチェック
$ ./detect-remote.sh facebook/react package-list.txt

# 詳細モード
$ VERBOSE=1 ./detect-remote.sh microsoft/vscode package-list.txt
```

## 注意事項

- GitHub API の制限により、1MB を超える package-lock.json は取得できません
- GitHub CLI での認証が必要です（`gh auth status` で確認）
- 取得したファイルは work/ ディレクトリに一時保存されます（自動削除）

--------------------------------------------------------------------------------

# 3. detect-org.sh

GitHub Organization 内のすべてのリポジトリを一括チェックするツール

## 必要要件

- gh (GitHub CLI) - 事前に認証が必要 (`gh auth login`)
- jq
- detect-remote.sh が同じディレクトリに存在すること

## 使用方法

```bash
./detect-org.sh <org-name> <list-file-path>
```

- `org-name`: GitHub Organization名（例: facebook, microsoft）
- `list-file-path`: 検出対象のパッケージリストファイル

## 実行例

```bash
# Organization 全体をスキャン
$ ./detect-org.sh facebook package-list.txt

# 詳細モード
$ VERBOSE=1 ./detect-org.sh microsoft vulnerable-packages.txt
```

## 終了ステータス

- `0`: すべてのリポジトリで検出なし
- `1`: エラー
- `2`: 1つ以上のリポジトリで検出あり

## 処理内容

1. `gh repo list` で Organization のリポジトリ一覧を取得（最大1000件）
2. 各リポジトリに対して `detect-remote.sh` を順次実行
3. 結果を集計してサマリーを表示

## 注意事項

- 1000 を超えるリポジトリ数には対応していません。（`gh repo list "$ORG_NAME" --limit 1000` ）
