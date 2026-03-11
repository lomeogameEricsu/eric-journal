#!/bin/bash
# 从 GitHub Gist 拉取日记数据，写入本地 Markdown 文件
# 用法：bash ~/journal/sync-local.sh
# 首次使用需设置 Token：bash ~/journal/sync-local.sh --setup

ENTRIES_DIR="$HOME/journal/entries"
CONFIG_FILE="$HOME/journal/.sync-config"

mkdir -p "$ENTRIES_DIR"

# Setup
if [ "$1" = "--setup" ]; then
  echo "请输入 GitHub Token（需要 gist 权限）："
  read -s TOKEN
  echo ""
  echo "请输入 Gist ID（在日记网页设置页可以看到，或留空自动查找）："
  read GIST_ID

  if [ -z "$GIST_ID" ]; then
    echo "正在查找日记 Gist..."
    GIST_ID=$(curl -s -H "Authorization: token $TOKEN" \
      "https://api.github.com/gists" | \
      grep -B2 '"journal-data.json"' | grep '"id"' | head -1 | \
      sed 's/.*"id": "\(.*\)".*/\1/')
  fi

  if [ -z "$GIST_ID" ]; then
    echo "未找到日记 Gist，请先在网页端保存一条记录并开启云端同步"
    exit 1
  fi

  echo "TOKEN=$TOKEN" > "$CONFIG_FILE"
  echo "GIST_ID=$GIST_ID" >> "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
  echo "配置已保存到 $CONFIG_FILE"
fi

# Load config
if [ ! -f "$CONFIG_FILE" ]; then
  echo "请先运行: bash ~/journal/sync-local.sh --setup"
  exit 1
fi
source "$CONFIG_FILE"

# Fetch from Gist
echo "正在从云端拉取日记..."
DATA=$(curl -s -H "Authorization: token $TOKEN" \
  "https://api.github.com/gists/$GIST_ID" | \
  python3 -c "
import sys, json
data = json.load(sys.stdin)
content = data.get('files', {}).get('journal-data.json', {}).get('content', '{}')
print(content)
")

if [ -z "$DATA" ] || [ "$DATA" = "{}" ]; then
  echo "没有找到日记数据"
  exit 1
fi

# Write markdown files
COUNT=$(python3 -c "
import json, sys

data = json.loads('''$DATA''') if len('''$DATA''') < 100000 else json.loads(sys.stdin.read())

mood_labels = {'1':'很低落','2':'有点丧','3':'平稳','4':'不错','5':'很好'}
energy_labels = {'1':'疲惫','2':'一般','3':'充沛'}
count = 0

for date_key, entry in sorted(data.items()):
    md = f'# {date_key} 日记\n\n'
    mood = mood_labels.get(str(entry.get('mood','')), '未记录')
    energy = energy_labels.get(str(entry.get('energy','')), '未记录')
    exercise = '是' if entry.get('exercise') == 'yes' else '否'
    md += f'情绪：{mood} | 精力：{energy} | 运动：{exercise}\n\n'

    fields = [
        ('业务进展', 'business'),
        ('AI学习', 'aiLearning'),
        ('人际关系', 'people'),
        ('内心感受', 'feelings'),
        ('今日反思', 'reflection'),
        ('明日重点', 'tomorrow'),
    ]
    for label, key in fields:
        val = entry.get(key, '').strip()
        if val:
            md += f'## {label}\n{val}\n\n'

    filepath = f'$ENTRIES_DIR/{date_key}.md'
    with open(filepath, 'w') as f:
        f.write(md)
    count += 1

print(count)
" <<< "$DATA")

echo "已同步 ${COUNT} 条日记到 $ENTRIES_DIR/"
ls -la "$ENTRIES_DIR/"
