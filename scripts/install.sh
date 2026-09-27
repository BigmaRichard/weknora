#!/usr/bin/env bash
# 新机器安装 WeKnora。
# 用法：scripts/install.sh [WeKnora 安装目录，默认 ~/WeKnora]
# 过程：按 config/overrides.env.example 中的版本克隆官方仓库 → 生成 .env（自动生成密钥）→ 拉取镜像并启动。
# 目标目录已有 .env 时保留原文件，不重新生成密钥。
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OVERRIDES="$REPO_DIR/config/overrides.env.example"
WK_DIR="${1:-$HOME/WeKnora}"
VERSION="$(grep -E '^WEKNORA_VERSION=' "$OVERRIDES" | cut -d= -f2-)"

for cmd in docker git openssl perl; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "未找到 $cmd，请先安装后再运行"; exit 1; }
done

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

if [ -f .env ]; then
  echo ".env 已存在，保留现有配置与密钥"
else
  cp .env.example .env
  set_kv JWT_SECRET "$(openssl rand -hex 32)"
  set_kv SYSTEM_AES_KEY "$(openssl rand -hex 16)"
  while IFS='=' read -r key val; do
    set_kv "$key" "$val"
  done < <(grep -E '^[A-Z_]+=' "$OVERRIDES")
  chmod 600 .env
  echo "已生成 .env。请把其中的 SYSTEM_AES_KEY 另存到密码管理器，丢失后已加密的模型密钥无法解密。"
fi

docker compose pull
docker compose up -d
docker compose ps
echo "安装完成：浏览器打开 http://localhost 注册账号，再按 README 配置模型。"
