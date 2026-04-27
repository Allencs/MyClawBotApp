#!/usr/bin/env bash
# 前台启动 OpenClaw Gateway（用于本地调试 / PM2 内被调用）
# 生产部署请用：pm2 start pm2.ecosystem.cjs
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

if ! command -v openclaw >/dev/null 2>&1; then
  # 尝试加载 nvm
  if [[ -s "$HOME/.nvm/nvm.sh" ]]; then
    # shellcheck disable=SC1091
    source "$HOME/.nvm/nvm.sh"
  fi
fi

if ! command -v openclaw >/dev/null 2>&1; then
  echo "[fail] 找不到 openclaw 命令，请先执行 bash scripts/install.sh" >&2
  exit 1
fi

echo "[start] OpenClaw Gateway 启动中..."
echo "[start] 默认模型：$(node -p "require('${OPENCLAW_HOME:-$HOME/.openclaw}/openclaw.json').agent.defaultModel")"
exec openclaw gateway start --foreground
