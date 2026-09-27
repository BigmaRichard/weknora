#!/usr/bin/env bash
# 在新机器上恢复 backup.sh 生成的备份（用于迁移到服务器）。
# 用法：scripts/restore.sh <备份目录> [WeKnora 安装目录，默认 ~/WeKnora]
# 注意：会用备份覆盖目标机器上 WeKnora 的数据库和上传文档。
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OVERRIDES="$REPO_DIR/config/overrides.env.example"
BK="$(cd "${1:?用法：scripts/restore.sh <备份目录> [WeKnora 安装目录]}" && pwd)"
WK_DIR="${2:-$HOME/WeKnora}"
VERSION="$(grep -E '^WEKNORA_VERSION=' "$OVERRIDES" | cut -d= -f2-)"

for f in weknora.dump files.tar.gz env; do
  [ -f "$BK/$f" ] || { echo "备份不完整，缺少 $f"; exit 1; }
done
for cmd in docker git perl; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "未找到 $cmd，请先安装后再运行"; exit 1; }
done

read -r -p "将用 $BK 覆盖 $WK_DIR 中的 WeKnora 数据库和文档，输入 yes 继续：" ans
[ "$ans" = "yes" ] || { echo "已取消"; exit 1; }

# 写入或替换 .env 中的 KEY=VALUE
set_kv() {
  local key="$1" val="$2"
  if grep -qE "^${key}=" .env; then
    KEY="$key" VAL="$val" perl -pi -e 's/^\Q$ENV{KEY}\E=.*/$ENV{KEY}=$ENV{VAL}/' .env
  else
    printf '%s=%s\n' "$key" "$val" >> .env
  fi
}

if [ ! -d "$WK_DIR/.git" ]; then
  echo "克隆 Tencent/WeKnora $VERSION 到 $WK_DIR ..."
  git clone --branch "$VERSION" --depth 1 https://github.com/Tencent/WeKnora.git "$WK_DIR"
fi
cd "$WK_DIR"

# 1. 使用备份中的 .env：保留原 SYSTEM_AES_KEY 等密钥，否则已加密保存的模型密钥无法解密
if [ -f .env ]; then cp .env ".env.before-restore.$(date +%Y%m%d-%H%M%S)"; fi
cp "$BK/env" .env
chmod 600 .env
while IFS='=' read -r key val; do
  set_kv "$key" "$val"
done < <(grep -E '^[A-Z_]+=' "$OVERRIDES")
DB_USER="$(grep -E '^DB_USER=' .env | cut -d= -f2-)"
DB_NAME="$(grep -E '^DB_NAME=' .env | cut -d= -f2-)"
DB_PASSWORD="$(grep -E '^DB_PASSWORD=' .env | cut -d= -f2-)"

# 2. 停止应用，只启动数据库；重建空库后导入
docker compose stop app frontend docreader >/dev/null 2>&1 || true
docker compose up -d postgres
echo "等待数据库就绪 ..."
until docker exec WeKnora-postgres pg_isready -U "$DB_USER" >/dev/null 2>&1; do sleep 2; done
# 让数据库用户密码与 .env 一致（目标机器之前初始化过数据库时可能不同）
docker exec -i WeKnora-postgres psql -U "$DB_USER" -d postgres -v ON_ERROR_STOP=1 -v pw="$DB_PASSWORD" \
  <<< "ALTER USER CURRENT_USER PASSWORD :'pw';"
docker exec WeKnora-postgres psql -U "$DB_USER" -d postgres -v ON_ERROR_STOP=1 \
  -c "DROP DATABASE IF EXISTS \"$DB_NAME\" WITH (FORCE);" \
  -c "CREATE DATABASE \"$DB_NAME\" TEMPLATE template0;"
echo "导入数据库 ..."
docker exec -i WeKnora-postgres pg_restore -U "$DB_USER" -d "$DB_NAME" --no-owner < "$BK/weknora.dump"

# 3. 恢复上传的文档
docker compose up --no-start
gunzip -c "$BK/files.tar.gz" | docker cp -a - WeKnora-app:/data/

# 4. 启动全部服务
docker compose up -d
docker compose ps
echo "恢复完成。服务器上请确认 Ollama 地址与模型配置（见 README「迁移到云服务器」）。"
