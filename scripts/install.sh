#!/usr/bin/env bash
# ===========================================================================
# 私人 AI 管家 / WeChat ClawBot 一键安装脚本（Linux / macOS）
#
# 流程：
#   1. 加载 .env，校验 OPENROUTER_API_KEY
#   2. 安装/检测 Node.js 20（优先 nvm，已有 node>=20 则跳过）
#   3. 全局安装 openclaw（CLI 主程序）
#   4. 安装并启用 @tencent-weixin/openclaw-weixin（ClawBot 微信插件）
#   5. 渲染 config/openclaw.template.json -> ~/.openclaw/openclaw.json，
#      注入 API Key 与默认模型
# ===========================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# ---------- 颜色输出 ----------
if [[ -t 1 ]]; then
  C_RED='\033[0;31m'; C_GRN='\033[0;32m'; C_YLW='\033[0;33m'
  C_BLU='\033[0;34m'; C_RST='\033[0m'
else
  C_RED=''; C_GRN=''; C_YLW=''; C_BLU=''; C_RST=''
fi
log()  { printf "${C_BLU}[install]${C_RST} %s\n" "$*"; }
ok()   { printf "${C_GRN}[ ok ]${C_RST}    %s\n" "$*"; }
warn() { printf "${C_YLW}[warn]${C_RST}    %s\n" "$*"; }
err()  { printf "${C_RED}[fail]${C_RST}    %s\n" "$*" >&2; }

# ---------- 1. 加载 .env ----------
if [[ ! -f .env ]]; then
  err ".env 不存在，请先 cp .env.example .env 并填写 OPENROUTER_API_KEY"
  exit 1
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

if [[ -z "${OPENROUTER_API_KEY:-}" || "$OPENROUTER_API_KEY" == "sk-or-v1-replace-me" ]]; then
  err "OPENROUTER_API_KEY 未填，请编辑 .env"
  exit 1
fi

OPENCLAW_DEFAULT_MODEL="${OPENCLAW_DEFAULT_MODEL:-gemini-flash-lite}"
OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"
ok ".env 加载完成（默认模型：$OPENCLAW_DEFAULT_MODEL）"

# ---------- 2. Node.js 20 ----------
need_install_node=true
if command -v node >/dev/null 2>&1; then
  node_major="$(node -p 'process.versions.node.split(".")[0]')"
  if [[ "$node_major" -ge 20 ]]; then
    need_install_node=false
    ok "Node.js 已存在：$(node -v)"
  else
    warn "Node.js 版本过低（$(node -v)），将通过 nvm 升级到 20"
  fi
fi

if $need_install_node; then
  log "通过 nvm 安装 Node 20..."
  if ! command -v nvm >/dev/null 2>&1; then
    if [[ ! -s "$HOME/.nvm/nvm.sh" ]]; then
      log "下载安装 nvm..."
      curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
    fi
    # shellcheck disable=SC1091
    export NVM_DIR="$HOME/.nvm"
    [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
  fi
  nvm install 20
  nvm alias default 20
  nvm use 20
  ok "Node.js 安装完成：$(node -v)"
fi

# ---------- 3. 全局安装 openclaw CLI ----------
if command -v openclaw >/dev/null 2>&1; then
  ok "openclaw 已存在：$(openclaw --version 2>/dev/null || echo unknown)"
else
  log "全局安装 openclaw..."
  npm install -g openclaw@latest
  ok "openclaw 安装完成：$(openclaw --version)"
fi

# ---------- 4. 安装/启用 ClawBot 微信插件 ----------
log "安装/升级 @tencent-weixin/openclaw-weixin（ClawBot 微信插件）..."
# 首选官方 CLI 安装器（自动版本匹配）
if ! npx -y @tencent-weixin/openclaw-weixin-cli@latest install <<<""; then
  warn "CLI 安装器失败，回退到手动安装"
  openclaw plugins install "@tencent-weixin/openclaw-weixin@latest"
  openclaw config set plugins.entries.openclaw-weixin.enabled true
fi
ok "ClawBot 插件已安装并启用"

# ---------- 5. 渲染 openclaw.json ----------
mkdir -p "$OPENCLAW_HOME"
TARGET="$OPENCLAW_HOME/openclaw.json"
TEMPLATE="$REPO_ROOT/config/openclaw.template.json"

if [[ -f "$TARGET" ]]; then
  BACKUP="$TARGET.bak.$(date +%Y%m%d%H%M%S)"
  cp "$TARGET" "$BACKUP"
  warn "已存在 $TARGET，已备份到 $BACKUP"
fi

log "渲染配置到 $TARGET ..."
# 使用 node 做 JSON 替换，避免 sed 对特殊字符的转义问题
node - "$TEMPLATE" "$TARGET" "$OPENROUTER_API_KEY" "$OPENCLAW_DEFAULT_MODEL" <<'NODE'
const fs = require('fs');
const [, , src, dst, apiKey, defaultModel] = process.argv;
const cfg = JSON.parse(fs.readFileSync(src, 'utf8'));
cfg.providers.entries.openrouter.apiKey = apiKey;
if (defaultModel && cfg.providers.entries.openrouter.models[defaultModel]) {
  cfg.agent.defaultModel = defaultModel;
} else if (defaultModel) {
  console.warn(`[warn] 模型 ${defaultModel} 未在模板中登记，沿用 ${cfg.agent.defaultModel}`);
}
fs.writeFileSync(dst, JSON.stringify(cfg, null, 2) + '\n');
NODE
chmod 600 "$TARGET"
ok "配置已写入 $TARGET（权限 600）"

# ---------- 完成提示 ----------
cat <<EOF

${C_GRN}========================================${C_RST}
${C_GRN}  安装完成 ✔${C_RST}
${C_GRN}========================================${C_RST}

下一步：
  1. 扫码绑定微信：    bash scripts/login-wechat.sh
  2. PM2 守护启动：    pm2 start pm2.ecosystem.cjs && pm2 save
  3. 微信里发条消息验证回复
  4. 切换模型：        bash scripts/switch-model.sh claude-sonnet

可用模型 key：
  $(node -p "Object.keys(require('$TARGET').providers.entries.openrouter.models).join('  ')")

当前默认模型：${C_YLW}$(node -p "require('$TARGET').agent.defaultModel")${C_RST}
EOF
