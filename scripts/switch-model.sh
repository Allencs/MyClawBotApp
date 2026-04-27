#!/usr/bin/env bash
# ===========================================================================
# 切换 OpenClaw 默认模型
#
# 用法：
#   bash scripts/switch-model.sh                    # 列出当前可用 model key
#   bash scripts/switch-model.sh <model-key>        # 切换并热重启 gateway
#
# model-key 必须存在于 ~/.openclaw/openclaw.json 的
# providers.entries.openrouter.models 中。
# ===========================================================================
set -euo pipefail

OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"
CONFIG="$OPENCLAW_HOME/openclaw.json"

if [[ ! -f "$CONFIG" ]]; then
  echo "[fail] 找不到 ${CONFIG}，请先 bash scripts/install.sh" >&2
  exit 1
fi

list_models() {
  echo "可用模型 (key -> id):"
  node -e '
    const cfg = require(process.argv[1]);
    const models = cfg.providers.entries.openrouter.models;
    const cur = cfg.agent.defaultModel;
    for (const k of Object.keys(models)) {
      const mark = k === cur ? "  *" : "   ";
      console.log(`${mark} ${k.padEnd(22)} -> ${models[k].id}`);
    }
    console.log("\n当前默认: " + cur);
  ' "$CONFIG"
}

if [[ $# -eq 0 ]]; then
  list_models
  exit 0
fi

TARGET_KEY="$1"

# 校验 key 存在
if ! node -e '
  const cfg = require(process.argv[1]);
  if (!cfg.providers.entries.openrouter.models[process.argv[2]]) process.exit(2);
' "$CONFIG" "$TARGET_KEY"; then
  echo "[fail] 模型 key '$TARGET_KEY' 未在配置中登记" >&2
  echo
  list_models
  exit 1
fi

echo "[switch] 切换默认模型 -> $TARGET_KEY"

# 优先用 openclaw config set，失败则回退到直接改 JSON
if openclaw config set agent.defaultModel "$TARGET_KEY" 2>/dev/null; then
  echo "[switch] openclaw config 写入成功"
else
  echo "[switch] openclaw config 不可用，直接编辑 JSON"
  TMP="$(mktemp)"
  node -e '
    const fs = require("fs");
    const [, , src, key] = process.argv;
    const cfg = JSON.parse(fs.readFileSync(src, "utf8"));
    cfg.agent.defaultModel = key;
    process.stdout.write(JSON.stringify(cfg, null, 2) + "\n");
  ' "$CONFIG" "$TARGET_KEY" > "$TMP"
  mv "$TMP" "$CONFIG"
  chmod 600 "$CONFIG"
fi

# 热重启
if command -v pm2 >/dev/null 2>&1 && pm2 describe myclawbot >/dev/null 2>&1; then
  echo "[switch] pm2 restart myclawbot"
  pm2 restart myclawbot
else
  echo "[switch] openclaw gateway restart"
  openclaw gateway restart || true
fi

echo "[ ok ] 已切换到模型: $TARGET_KEY"
echo "[hint] 在微信里再发一条消息，对比回复风格验证生效"
