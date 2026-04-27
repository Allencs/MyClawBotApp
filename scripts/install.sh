#!/usr/bin/env bash
# ===========================================================================
# 私人 AI 管家 / WeChat ClawBot 一键安装脚本（Linux / macOS）
#
# 默认全自动流程：
#   1. 加载 .env，校验 OPENROUTER_API_KEY
#   2. 安装/检测 Node.js 20（优先 nvm，已有 node>=20 则跳过）
#   3. 全局安装 openclaw（CLI 主程序）
#   4. 安装并启用 @tencent-weixin/openclaw-weixin（ClawBot 微信插件）
#   5. 渲染 config/openclaw.template.json -> ~/.openclaw/openclaw.json
#   6. 全局安装 PM2（如未安装）
#   7. 自动弹出二维码，引导扫码绑定微信
#   8. PM2 拉起 myclawbot + myclawbot-healthcheck，并 pm2 save
#
# 选项：
#   --skip-login    跳过扫码登录步骤（重复执行 / CI 时用）
#   --skip-pm2      跳过 PM2 安装与启动
#   --reinstall     强制重新渲染配置（已存在的 openclaw.json 会先备份）
# ===========================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# ---------- 参数解析 ----------
SKIP_LOGIN=false
SKIP_PM2=false
REINSTALL=false
for arg in "$@"; do
  case "$arg" in
    --skip-login) SKIP_LOGIN=true ;;
    --skip-pm2)   SKIP_PM2=true ;;
    --reinstall)  REINSTALL=true ;;
    -h|--help)
      sed -n '2,19p' "$0"
      exit 0
      ;;
    *)
      echo "未知参数: $arg" >&2
      echo "用 -h 查看帮助" >&2
      exit 2
      ;;
  esac
done

# ---------- 颜色输出 ----------
if [[ -t 1 ]]; then
  C_RED=$'\033[0;31m'; C_GRN=$'\033[0;32m'; C_YLW=$'\033[0;33m'
  C_BLU=$'\033[0;34m'; C_RST=$'\033[0m'
else
  C_RED=''; C_GRN=''; C_YLW=''; C_BLU=''; C_RST=''
fi
log()  { printf "${C_BLU}[install]${C_RST} %s\n" "$*"; }
ok()   { printf "${C_GRN}[ ok ]${C_RST}    %s\n" "$*"; }
warn() { printf "${C_YLW}[warn]${C_RST}    %s\n" "$*"; }
err()  { printf "${C_RED}[fail]${C_RST}    %s\n" "$*" >&2; }
hr()   { printf "${C_BLU}%s${C_RST}\n" "============================================================"; }

# ---------- 1. 加载 .env ----------
if [[ ! -f .env ]]; then
  err ".env 不存在，请先 cp .env.example .env 并填写 OPENROUTER_API_KEY"
  exit 1
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

if [[ -z "${OPENROUTER_API_KEY:-}" || "${OPENROUTER_API_KEY}" == "sk-or-v1-replace-me" ]]; then
  err "OPENROUTER_API_KEY 未填，请编辑 .env"
  exit 1
fi

OPENCLAW_DEFAULT_MODEL="${OPENCLAW_DEFAULT_MODEL:-gemini-flash-lite}"
OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"
ok ".env 加载完成（默认模型：${OPENCLAW_DEFAULT_MODEL}）"

# 确保后续步骤里 openclaw / pm2 这类全局命令能被找到
ensure_node_in_path() {
  if [[ -s "$HOME/.nvm/nvm.sh" ]]; then
    # shellcheck disable=SC1091
    export NVM_DIR="$HOME/.nvm"
    # shellcheck disable=SC1091
    source "$NVM_DIR/nvm.sh"
  fi
  # npm 全局 bin 目录
  local npm_bin
  npm_bin="$(npm bin -g 2>/dev/null || true)"
  if [[ -n "$npm_bin" && ":$PATH:" != *":$npm_bin:"* ]]; then
    export PATH="$npm_bin:$PATH"
  fi
}

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

ensure_node_in_path

# ---------- 3. 全局安装 openclaw CLI ----------
if command -v openclaw >/dev/null 2>&1; then
  ok "openclaw 已存在：$(openclaw --version 2>/dev/null || echo unknown)"
else
  log "全局安装 openclaw..."
  npm install -g openclaw@latest
  ensure_node_in_path
  ok "openclaw 安装完成：$(openclaw --version)"
fi

# ---------- 4. 安装/启用 ClawBot 微信插件 ----------
log "安装/升级 @tencent-weixin/openclaw-weixin（ClawBot 微信插件）..."
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

if [[ -f "$TARGET" ]] && ! $REINSTALL; then
  current_key="$(node -e "console.log(require('$TARGET').providers.entries.openrouter.apiKey || '')" 2>/dev/null || true)"
  if [[ "$current_key" == "$OPENROUTER_API_KEY" ]]; then
    ok "openclaw.json 已是最新（API Key 一致），跳过渲染"
  else
    BACKUP="${TARGET}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$TARGET" "$BACKUP"
    warn "已存在 ${TARGET}，已备份到 ${BACKUP}"
    REINSTALL=true
  fi
fi

if [[ ! -f "$TARGET" ]] || $REINSTALL; then
  log "渲染配置到 ${TARGET} ..."
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
  ok "配置已写入 ${TARGET}（权限 600）"
fi

# ---------- 6. PM2 ----------
if ! $SKIP_PM2; then
  if command -v pm2 >/dev/null 2>&1; then
    ok "PM2 已存在：$(pm2 --version)"
  else
    log "全局安装 PM2..."
    npm install -g pm2
    ensure_node_in_path
    ok "PM2 安装完成：$(pm2 --version)"
  fi
else
  warn "--skip-pm2 已设置，跳过 PM2 安装"
fi

# ---------- 7. 扫码绑定微信 ----------
if ! $SKIP_LOGIN; then
  echo
  hr
  printf "%s  下一步：扫码绑定微信%s\n" "${C_YLW}" "${C_RST}"
  hr
  cat <<'TIPS'
  操作步骤：
    1) 打开 v8.0.70+ 个人微信
    2) 右上角「+」→「扫一扫」→ 对准终端二维码
    3) 在手机上点「同意授权」

  说明：
    - 二维码以 ASCII 形式直接打印在终端，请把窗口拉大一些
    - 已经登录过、不需要再扫的话，按 Ctrl+C 跳过本步骤
    - 之后想再加账号或重扫，运行：bash scripts/login-wechat.sh
TIPS
  echo
  read -r -p "准备好后按回车开始（Ctrl+C 跳过）..." _ || true

  if openclaw channels login --channel openclaw-weixin; then
    ok "微信账号绑定成功"
    openclaw channels list || true
  else
    rc=$?
    if [[ $rc -eq 130 ]]; then
      warn "已跳过扫码登录（Ctrl+C）。后续可运行 bash scripts/login-wechat.sh 单独登录"
    else
      warn "扫码登录退出码=${rc}，但安装流程继续。后续可运行 bash scripts/login-wechat.sh 重试"
    fi
  fi
else
  warn "--skip-login 已设置，跳过扫码登录"
fi

# ---------- 8. PM2 守护启动 ----------
if ! $SKIP_PM2; then
  echo
  hr
  printf "%s  启动 PM2 守护进程%s\n" "${C_YLW}" "${C_RST}"
  hr

  log "pm2 start pm2.ecosystem.cjs"
  pm2 start "$REPO_ROOT/pm2.ecosystem.cjs"

  log "pm2 save（落盘进程列表，下次重启自动恢复）"
  pm2 save

  ok "PM2 守护已启动"
  pm2 status || true

  cat <<EOF

${C_YLW}如要做到「服务器重启自动拉起」，请按下面提示执行${C_RST}：
  pm2 startup
执行后 PM2 会打印一条 ${C_BLU}sudo env PATH=...${C_RST} 命令，
将那条命令复制 + 用 sudo 跑一遍即可（需要 root 权限）。

EOF
else
  warn "--skip-pm2 已设置，跳过 PM2 启动；可手动执行：pm2 start pm2.ecosystem.cjs && pm2 save"
fi

# ---------- 完成提示 ----------
echo
hr
printf "%s  全部完成 ✔%s\n" "${C_GRN}" "${C_RST}"
hr

CUR_MODEL="$(node -p "require('$TARGET').agent.defaultModel")"
MODEL_KEYS="$(node -p "Object.keys(require('$TARGET').providers.entries.openrouter.models).join('  ')")"

cat <<EOF

当前默认模型：${C_YLW}${CUR_MODEL}${C_RST}
可用模型 key：${MODEL_KEYS}

常用命令：
  ${C_BLU}pm2 logs myclawbot${C_RST}                       查看实时日志
  ${C_BLU}pm2 status${C_RST}                                查看进程
  ${C_BLU}pm2 restart myclawbot${C_RST}                     重启
  ${C_BLU}bash scripts/switch-model.sh claude-sonnet${C_RST}  切换模型
  ${C_BLU}bash scripts/healthcheck.sh${C_RST}                一次性健康检查
  ${C_BLU}bash scripts/login-wechat.sh${C_RST}               重新扫码 / 加多账号

接下来：打开微信，向 ClawBot 发送一条消息（如「你好」），验证回复。
EOF
