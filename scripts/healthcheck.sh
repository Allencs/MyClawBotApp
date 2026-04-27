#!/usr/bin/env bash
# ===========================================================================
# OpenClaw + ClawBot 微信渠道健康探针
#
# 检查项：
#   1. gateway HTTP 端点可达
#   2. openclaw-weixin 渠道状态为 connected
#   3. （可选）OpenRouter API Key 仍有效
#
# 退出码：
#   0 = 全部 OK
#   1 = 至少一项失败（可由外部 cron 触发 pm2 restart）
#
# 用法：
#   bash scripts/healthcheck.sh                  # 输出可读结果
#   bash scripts/healthcheck.sh --quiet          # 仅返回退出码
#   bash scripts/healthcheck.sh --auto-restart   # 失败 3 次后 pm2 restart
# ===========================================================================
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

QUIET=false
AUTO_RESTART=false
for arg in "$@"; do
  case "$arg" in
    --quiet) QUIET=true ;;
    --auto-restart) AUTO_RESTART=true ;;
  esac
done

[[ -f .env ]] && { set -a; source .env; set +a; }
HOST="${OPENCLAW_GATEWAY_HOST:-127.0.0.1}"
PORT="${OPENCLAW_GATEWAY_PORT:-8421}"

LOG_DIR="$REPO_ROOT/logs"
mkdir -p "$LOG_DIR"
FAIL_COUNTER="$LOG_DIR/healthcheck.fail"
LOG_FILE="$LOG_DIR/healthcheck.log"

say() { $QUIET || echo "$@"; echo "[$(date '+%F %T')] $*" >> "$LOG_FILE"; }

failures=0

# ---------- 1. gateway 端点 ----------
if curl -fsS --max-time 5 "http://${HOST}:${PORT}/healthz" >/dev/null 2>&1 \
  || curl -fsS --max-time 5 "http://${HOST}:${PORT}/" >/dev/null 2>&1; then
  say "[ ok ] gateway HTTP ${HOST}:${PORT} 可达"
else
  say "[fail] gateway HTTP ${HOST}:${PORT} 不可达"
  failures=$((failures + 1))
fi

# ---------- 2. 微信渠道 ----------
if command -v openclaw >/dev/null 2>&1; then
  channels_out="$(openclaw channels list 2>/dev/null || true)"
  if echo "$channels_out" | grep -E "openclaw-weixin.*(connected|online|ok)" -i >/dev/null; then
    say "[ ok ] openclaw-weixin 渠道在线"
  else
    say "[fail] openclaw-weixin 渠道离线或未登录"
    say "       openclaw channels list 输出："
    echo "$channels_out" | sed 's/^/         /' | tee -a "$LOG_FILE" >/dev/null
    failures=$((failures + 1))
  fi
else
  say "[warn] 未找到 openclaw 命令，跳过渠道检查"
fi

# ---------- 3. OpenRouter Key ----------
if [[ -n "${OPENROUTER_API_KEY:-}" ]]; then
  http_code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
    -H "Authorization: Bearer $OPENROUTER_API_KEY" \
    https://openrouter.ai/api/v1/auth/key || echo 000)"
  if [[ "$http_code" == "200" ]]; then
    say "[ ok ] OpenRouter API Key 有效"
  else
    say "[fail] OpenRouter API Key 校验失败（HTTP $http_code）"
    failures=$((failures + 1))
  fi
fi

# ---------- 自动恢复 ----------
if [[ $failures -eq 0 ]]; then
  echo 0 > "$FAIL_COUNTER"
  say "[ ok ] healthcheck PASS"
  exit 0
fi

cur="$(cat "$FAIL_COUNTER" 2>/dev/null || echo 0)"
cur=$((cur + 1))
echo "$cur" > "$FAIL_COUNTER"
say "[fail] healthcheck FAIL ($failures 项失败，连续失败 $cur 次)"

if $AUTO_RESTART && [[ $cur -ge 3 ]]; then
  if command -v pm2 >/dev/null 2>&1 && pm2 describe myclawbot >/dev/null 2>&1; then
    say "[recover] 连续失败 ${cur} 次，触发 pm2 restart myclawbot"
    pm2 restart myclawbot >/dev/null 2>&1 || true
    echo 0 > "$FAIL_COUNTER"
  fi
fi

exit 1
