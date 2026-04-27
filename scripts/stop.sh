#!/usr/bin/env bash
# 停止 OpenClaw Gateway
# - 若由 PM2 启动，请使用 pm2 stop myclawbot
# - 此脚本兼容前台 / 直接 fork 启动的场景
set -euo pipefail

if command -v pm2 >/dev/null 2>&1 && pm2 describe myclawbot >/dev/null 2>&1; then
  echo "[stop] 检测到 PM2 进程，使用 pm2 stop myclawbot"
  pm2 stop myclawbot
  exit 0
fi

if command -v openclaw >/dev/null 2>&1; then
  echo "[stop] 调用 openclaw gateway stop"
  openclaw gateway stop || true
fi

# 兜底：杀掉残留 openclaw 进程
if pgrep -f "openclaw gateway" >/dev/null 2>&1; then
  echo "[stop] 仍有残留进程，发送 SIGTERM"
  pkill -TERM -f "openclaw gateway" || true
  sleep 2
  pkill -KILL -f "openclaw gateway" 2>/dev/null || true
fi

echo "[stop] 完成"
