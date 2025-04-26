#!/bin/bash
# npmの最新バージョンを指定してインストール
echo "Installing npm@11.1.0..."
npm install -g npm@11.1.0

# 本日の日付を取得
today=$(date +"%Y-%m-%d")
echo "Today's date: $today"

# zenn-cliのインストール
echo "Installing zenn-cli..."
npm install -g zenn-cli

# 新規記事の作成
echo "Creating a new Zenn article..."
npx zenn new:article

# 作成日時が最新の記事ファイルを取得
echo "Finding the most recently created article..."
article_file=$(find articles -name "*.md" -type f -printf "%T@ %p\n" | sort -rn | head -n 1 | cut -d' ' -f2-)
if [[ -f "$article_file" ]]; then
  echo "Adding date to $article_file..."
  
  # title行を"dummy"に置換
  sed -i 's/^title: ""$/title: "dummy"/' "$article_file"

  # 直接エディタを使用して書き込む
  datestr="date: \"$today\""
  echo "Date string to add: $datestr"
  
  # sedで単純置換（シングルクォートで囲んでシェル変数展開を制御）
  sed -i 's/^published: false$/published: false\
date: "'"$today"'"/' "$article_file"
  
  echo "Date added successfully to $article_file"
  # 確認のために内容を表示
  echo "Updated frontmatter:"
  head -n 10 "$article_file"
else
  echo "No article file found."
fi
echo "Done!"