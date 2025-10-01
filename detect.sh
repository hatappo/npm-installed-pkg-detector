#!/bin/bash

# 使用方法を表示する関数
show_usage() {
    cat << EOF
使用方法: $0 <list-file-path> [lock-file-path]

引数:
  list-file-path  検出対象のパッケージとバージョンの一覧ファイル
  lock-file-path  package-lock.jsonのパス (デフォルト: ./package-lock.json)

リストファイルの形式:
  package-name ( version1 , version2 , ... )

例:
  jest ( 29.7.0 , 29.6.0 )
  typescript ( 5.3.3 )
  express

終了コード:
  0 - 正常終了（バージョン一致なし）
  1 - エラー
  2 - バージョン一致あり
EOF
}

# カウント用変数の初期化
total_packages=0
detected_packages=0
total_versions=0
detected_versions=0
version_match_found=0

# 引数チェック
if [ $# -lt 1 ]; then
    show_usage
    exit 1
fi

LIST_FILE="$1"
LOCKFILE="${2:-./package-lock.json}"

if ! command -v jq &> /dev/null; then
    echo "エラー: jqがインストールされていません" >&2
    exit 1
fi

if [ ! -f "$LIST_FILE" ]; then
    echo "エラー: リストファイルが見つかりません: $LIST_FILE" >&2
    exit 1
fi

if [ ! -f "$LOCKFILE" ]; then
    echo "エラー: package-lock.jsonが見つかりません: $LOCKFILE" >&2
    exit 1
fi

# lockfileVersionをチェック（3のみサポート）
LOCKFILE_VERSION=$(jq -r '.lockfileVersion // empty' "$LOCKFILE" 2>/dev/null)
if [ "$LOCKFILE_VERSION" != "3" ]; then
    echo "エラー: lockfileVersion 3 のみサポートされています (現在: ${LOCKFILE_VERSION:-なし})" >&2
    exit 1
fi

# パッケージを検索する関数
search_package() {
    local pkg_name="$1"
    local pkg_versions="$2"

    # パッケージ数をカウント
    ((total_packages++))

    # まずパッケージの存在を確認（バージョン関係なく）
    local found_packages=$(jq -r --arg name "$pkg_name" '
        [
            # トップレベルの dependencies と devDependencies を確認（lockfileVersion 2以前用）
            if .dependencies[$name] then
                {location: "dependencies", version: .dependencies[$name]}
            else empty end,
            if .devDependencies[$name] then
                {location: "devDependencies", version: .devDependencies[$name]}
            else empty end,
            # packages."" の dependencies と devDependencies を確認（lockfileVersion 3用）
            if .packages[""].dependencies[$name] then
                {location: "dependencies", version: .packages[""].dependencies[$name]}
            else empty end,
            if .packages[""].devDependencies[$name] then
                {location: "devDependencies", version: .packages[""].devDependencies[$name]}
            else empty end,
            # packages セクションを確認
            (
                .packages | to_entries[] |
                select(.key | test("(^|/)\\Q\($name)\\E$")) |
                {location: .key, version: .value.version}
            )
        ] | unique_by(.version)
    ' "$LOCKFILE" 2>/dev/null)

    if [ -z "$found_packages" ] || [ "$found_packages" = "[]" ]; then
        if [ "$VERBOSE" = "1" ]; then
            echo "✗ $pkg_name: 未検出"
        fi
        return
    fi

    # パッケージが見つかった場合
    ((detected_packages++))
    local found_versions=$(echo "$found_packages" | jq -r '.[].version' | sort -u | tr '\n' ' ')
    echo "✓ $pkg_name: 検出 (対象バージョン: $found_versions)"

    # 特定バージョンの確認
    if [ -n "$pkg_versions" ]; then
        # カンマで分割してバージョンをチェック
        IFS=',' read -ra VERSIONS <<< "$pkg_versions"
        for version in "${VERSIONS[@]}"; do
            # 前後の空白を削除
            version=$(echo "$version" | xargs)

            # バージョン総数をカウント
            ((total_versions++))

            # バージョンが存在するか確認
            local version_found=$(echo "$found_packages" | jq -r --arg v "$version" '
                .[] | select(.version == $v) | .version
            ' | head -1)

            if [ -n "$version_found" ]; then
                echo "  → バージョン $version: 検出"
                ((detected_versions++))
                version_match_found=1
            else
                if [ "$VERBOSE" = "1" ]; then
                    echo "  → バージョン $version: 未検出"
                fi
            fi
        done
    fi
}

# リストファイルを処理
echo "=== 設定 ==="
echo "リストファイル: $LIST_FILE"
echo "package-lock.json: $LOCKFILE"
echo ""
echo "=== 検出結果 ==="

while IFS= read -r line; do
    # 空行をスキップ
    if [ -z "$line" ] || [[ "$line" =~ ^[[:space:]]*$ ]]; then
        continue
    fi

    # パッケージ名とバージョンリストを抽出
    # まず括弧があるかチェック
    if echo "$line" | grep -q '(.*)'  ; then
        # バージョンリスト付き
        pkg_name=$(echo "$line" | sed 's/[[:space:]]*(.*//' | xargs)
        pkg_versions=$(echo "$line" | sed 's/.*(\(.*\)).*/\1/')
    else
        # パッケージ名のみ
        pkg_name=$(echo "$line" | xargs)
        pkg_versions=""
    fi

    # パッケージ名が空の場合はスキップ
    if [ -z "$pkg_name" ]; then
        echo "警告: 無効な行形式をスキップ: $line" >&2
        continue
    fi

    search_package "$pkg_name" "$pkg_versions"
done < "$LIST_FILE"

echo ""
echo "=== 検出結果サマリ ==="
echo "検出パッケージ数: $detected_packages/$total_packages"
echo "検出バージョン数: $detected_versions/$total_versions"

# 終了ステータスを決定
if [ "$version_match_found" -eq 1 ]; then
    exit 2
else
    exit 0
fi
