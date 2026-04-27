#!/usr/bin/env bash
# ===========================================================================
# 触发 ClawBot 微信扫码登录
#
# - 终端会打印一张 ASCII 二维码，请用 v8.0.70+ 的个人微信扫码并在手机点确认
# - 多次执行此脚本可叠加登录多个微信号（自动按账号隔离会话）
# ===========================================================================
set -euo pipefail

if ! command -v openclaw >/dev/null 2>&1; then
  echo "[fail] 未检测到 openclaw 命令，请先执行 bash scripts/install.sh" >&2
  exit 1
fi

cat <<'TIPS'
============================================================
  即将弹出二维码，请按以下步骤操作：
    1) 打开 v8.0.70+ 的个人微信
    2) 右上角「+」→「扫一扫」→ 对准终端二维码
    3) 在手机上点「同意授权」
  授权完成后凭证会自动落盘到 ~/.openclaw/，
  之后无需重复扫码（除非主动登出 / Bot Token 过期）。
============================================================
TIPS

openclaw channels login --channel openclaw-weixin

echo
echo "[ ok ] 登录流程结束。当前已登录的渠道："
openclaw channels list || true

cat <<'NEXT'

下一步：
  - 启动 / 守护：  pm2 start pm2.ecosystem.cjs && pm2 save
  - 前台调试：     bash scripts/start.sh
  - 日志：         pm2 logs myclawbot
NEXT
