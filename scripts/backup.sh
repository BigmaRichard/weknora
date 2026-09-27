#!/usr/bin/env bash
# 备份 WeKnora：数据库、上传的文档、.env。
# 用法：scripts/backup.sh [WeKnora 安装目录，默认 ~/WeKnora]
# 输出：本仓库 backups/<时间戳>/ 下的 weknora.dump、files.tar.gz、env、meta.txt。
# backups/ 已被 .gitignore 排除。备份含密钥与业务资料，请保存在安全位置，不要上传到 GitHub。
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WK_DIR="${1:-$HOME/WeKnora}"
OUT="$REPO_DIR/backups/$(date +%Y%m%d-%H%M%S)"

[ -f "$WK_DIR/.env" ] || { echo "未找到 $WK_DIR/.env，请确认 WeKnora 安装目录"; exit 1; }
DB_USER="$(grep -E '^DB_USER=' "$WK_DIR/.env" | cut -d= -f2-)"
DB_NAME="$(grep -E '^DB_NAME=' "$WK_DIR/.env" | cut -d= -f2-)"

mkdir -p "$OUT"
chmod 700 "$OUT"

echo "1/3 导出数据库 ..."
docker exec WeKnora-postgres pg_dump -U "$DB_USER" -d "$DB_NAME" -Fc > "$OUT/weknora.dump"

echo "2/3 打包上传的文档 ..."
docker cp WeKnora-app:/data/files - | gzip > "$OUT/files.tar.gz"

echo "3/3 保存 .env 与版本信息 ..."
cp "$WK_DIR/.env" "$OUT/env"
chmod 600 "$OUT/env"
{
  echo "backup_time=$(date '+%Y-%m-%d %H:%M:%S %z')"
  echo "weknora_version=$(grep -E '^WEKNORA_VERSION=' "$WK_DIR/.env" | cut -d= -f2-)"
  echo "app_image=$(docker inspect WeKnora-app --format '{{.Config.Image}}')"
  echo "app_image_id=$(docker inspect WeKnora-app --format '{{.Image}}')"
} > "$OUT/meta.txt"

du -sh "$OUT"
echo "备份完成：$OUT"
