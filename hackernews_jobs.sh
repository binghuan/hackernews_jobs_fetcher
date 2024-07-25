#!/bin/bash

# 定义数据库文件名和路径
DB_DIR="$HOME/Dropbox/bin"
DB_FILE="$DB_DIR/hackernews.db"
# Hacker News 帖子的基础 URL
HN_ITEM_URL="https://news.ycombinator.com/item?id="

# 创建数据库目录和网页内容目录
mkdir -p "$DB_DIR"

# 检查数据库文件是否存在，如果不存在则创建数据库和表
if [ ! -f "$DB_FILE" ]; then
    echo "Database file not found. Creating database and table..."
    sqlite3 "$DB_FILE" <<EOF
CREATE TABLE IF NOT EXISTS jobs (
    id INTEGER PRIMARY KEY,
    title TEXT,
    url TEXT,
    score INTEGER,
    by TEXT,
    time TEXT,
    text TEXT,
    webpage_content TEXT
);
EOF
else
    echo "Database file found. Skipping database creation."
fi

fetch_jobs() {
    # 获取 Job Board 的 ID 列表
    JOB_STORIES=$(curl -s "$BASE_URL/jobstories.json")
    TOTAL_JOBS=$(echo "$JOB_STORIES" | jq length)

    # 使用 jq 解析 JSON 并遍历 Job Board 的 ID 列表
    echo "Fetching Job Board IDs..."
    CURRENT_JOB=0
    echo "$JOB_STORIES" | jq -r '.[]' | while read JOB_ID; do
        CURRENT_JOB=$((CURRENT_JOB + 1))
        echo "Fetching details for Job ID: $JOB_ID ($CURRENT_JOB/$TOTAL_JOBS)"
        
        # 检查数据库中是否已有该 Job ID 且 URL 没有变化
        DB_URL=$(sqlite3 "$DB_FILE" "SELECT url FROM jobs WHERE id=$JOB_ID;")
        JOB_DETAILS=$(curl -s "$BASE_URL/item/$JOB_ID.json")
        NEW_URL=$(echo "$JOB_DETAILS" | jq -r '.url // ""' | sed "s/'/''/g")

        if [ "$DB_URL" == "$NEW_URL" ] && [ -n "$DB_URL" ]; then
            echo "Job ID $JOB_ID already exists with the same URL. Skipping..."
            continue
        fi

        # 解析 Job 的详细信息
        ID=$(echo "$JOB_DETAILS" | jq -r '.id')
        TITLE=$(echo "$JOB_DETAILS" | jq -r '.title' | sed "s/'/''/g")
        SCORE=$(echo "$JOB_DETAILS" | jq -r '.score')
        BY=$(echo "$JOB_DETAILS" | jq -r '.by' | sed "s/'/''/g")
        TIME=$(echo "$JOB_DETAILS" | jq -r '.time | strftime("%Y-%m-%d %H:%M:%S")')
        TEXT=$(echo "$JOB_DETAILS" | jq -r '.text // ""' | sed "s/'/''/g")

        # 获取 URL 的网页内容
        WEBPAGE_CONTENT=""
        if [ -n "$NEW_URL" ]; then
            WEBPAGE_CONTENT=$(curl -s "$NEW_URL" | sed "s/'/''/g")
        fi
        
        echo "Inserting Job ID $ID into database"
        # 将 Job details 和网页内容插入数据库
        sqlite3 "$DB_FILE" <<EOF
INSERT OR REPLACE INTO jobs (id, title, url, score, by, time, text, webpage_content)
VALUES ($ID, '$TITLE', '$NEW_URL', $SCORE, '$BY', '$TIME', '$TEXT', '$WEBPAGE_CONTENT');
EOF
        echo "Job ID $ID inserted successfully"
    done

    echo "All jobs have been fetched and inserted into the database."
}

highlight_keyword() {
    local text="$1"
    local keyword="$2"
    echo "$text" | grep --color=always -i -E "($keyword|$)"
}

search_jobs() {
    KEYWORD=$1

    if [ -z "$KEYWORD" ]; then
        echo "Usage: $0 search <keyword>"
        exit 1
    fi

    echo "Searching for jobs with keyword '$KEYWORD'..."
    sqlite3 -line "$DB_FILE" <<EOF | while read -r line; do
.headers on
.mode line
SELECT id, title, url, score, by, time, text, webpage_content 
FROM jobs 
WHERE LOWER(title) LIKE LOWER('%$KEYWORD%') 
   OR LOWER(text) LIKE LOWER('%$KEYWORD%') 
   OR LOWER(webpage_content) LIKE LOWER('%$KEYWORD%') 
ORDER BY time ASC;
EOF
        if [[ $line == id* ]]; then
            job_id=$(echo "$line" | cut -d= -f2 | xargs)
            echo -e "Link to HN Post: $HN_ITEM_URL$job_id"
        elif [[ $line == webpage_content* ]]; then
            content="${line#*= }"
            highlighted_content=$(highlight_keyword "$content" "$KEYWORD")
            echo "webpage_content: $(echo "$highlighted_content" | grep -o ".\{0,80\}$KEYWORD.\{0,80\}" -i --color=always)"
        else
            highlighted_line=$(highlight_keyword "$line" "$KEYWORD")
            echo "$highlighted_line"
        fi
    done
}

# 检查命令行参数
if [ "$#" -eq 0 ]; then
    echo "Usage: $0 {fetch|search <keyword>}"
    exit 1
fi

COMMAND=$1
BASE_URL="https://hacker-news.firebaseio.com/v0"

case $COMMAND in
    fetch)
        fetch_jobs
        ;;
    search)
        search_jobs "$2"
        ;;
    *)
        echo "Unknown command: $COMMAND"
        echo "Usage: $0 {fetch|search <keyword>}"
        exit 1
        ;;
esac
