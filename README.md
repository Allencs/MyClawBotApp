# 私人 AI 管家 · WeChat ClawBot 基础能力（MVP）

通过腾讯官方 ClawBot 插件把 OpenClaw 接入个人微信，配合 OpenRouter 调用大模型，实现「**微信收消息 → LLM 生成回复 → 微信回写**」最小闭环。本仓库只存「**安装 / 配置 / 守护 / 运维**」的脚本与文档，业务级 Skill（日程、晨报、复盘）后续迭代。

---

## 一、本期能做什么

- 用个人微信（v8.0.70+）和 ClawBot 自然语言对话，由 OpenRouter 上的 LLM 自动回复
- 默认模型：`google/gemini-3.1-flash-lite-preview`（便宜稳定，适合日常聊天）
- 一行命令在多个模型间切换（gemini-pro / claude-sonnet / deepseek-chat 等）
- PM2 守护，崩溃自动重启，开机自启
- 健康探针检测微信掉线 / Bot Token 失效

> 不在本期：5W1H 日程提取 / 晨报复盘 / 语音备忘录 / ASR / 数据库

---

## 二、架构（最小闭环）

```
个人微信 ──► @tencent-weixin/openclaw-weixin ──► OpenClaw Gateway ──► OpenRouter ──► Gemini / Claude / DeepSeek
   ▲                                                                                          │
   └──────────────────────────────────────── sendMessage ◄─────────────────────────────────────┘
```

按官方插件文档（`@tencent-weixin/openclaw-weixin` v2.1.10），消息进入 Gateway 后会自动路由到配置的 LLM 模型，并将回复回写到微信。MVP 阶段无需写一行业务代码。

---

## 三、远程 Linux 7 步部署

> 适用：Ubuntu 22.04 / Debian 12（x86_64），需要 sudo。

### 1. SSH 登录服务器，拉代码

```bash
sudo mkdir -p /opt/myclawbot && sudo chown -R "$USER" /opt/myclawbot
git clone <your-repo-url> /opt/myclawbot
cd /opt/myclawbot
```

### 2. 配置 API Key

```bash
cp .env.example .env
vim .env   # 把 OPENROUTER_API_KEY 改成你的真实 key
```

### 3. 一键安装（Node 20 + OpenClaw + ClawBot 插件）

```bash
bash scripts/install.sh
```

脚本会：
- 检测/安装 nvm + Node 20（已安装 Node>=20 则跳过）
- 全局安装 `openclaw@latest`
- 通过 `@tencent-weixin/openclaw-weixin-cli` 安装并启用 `@tencent-weixin/openclaw-weixin@latest`
- 把 `config/openclaw.template.json` 渲染成 `~/.openclaw/openclaw.json`，注入 `OPENROUTER_API_KEY`
- 文件权限设为 `600`

### 4. 扫码绑定微信

```bash
bash scripts/login-wechat.sh
```

终端会输出二维码，**用 v8.0.70+ 的个人微信扫码并在手机上点确认**。授权后凭证自动落盘，下次重启不用再扫。

> 多个微信号？再次执行同一脚本即可叠加登录。

### 5. PM2 守护

```bash
# 全局装 PM2（如果还没装）
npm install -g pm2

# 启动 + 落盘 + 开机自启
pm2 start pm2.ecosystem.cjs
pm2 save
pm2 startup    # 按 PM2 输出的命令再用 sudo 执行一次
```

启动后查看实时日志：

```bash
pm2 logs myclawbot
```

PM2 配置里同时挂了一个每分钟跑一次的 `myclawbot-healthcheck`，连续 3 次健康检查失败时会自动 `pm2 restart myclawbot`。

### 6. 微信里发一条消息验证

打开微信，找到刚授权的 ClawBot 会话（一般会出现在聊天列表顶部），发送：

```
你好，介绍一下你自己
```

正常情况下 1–3 秒内会收到 LLM 回复。

### 7. 切换模型（可选）

```bash
bash scripts/switch-model.sh                    # 列出当前可用 model key
bash scripts/switch-model.sh claude-sonnet      # 切到 Claude
bash scripts/switch-model.sh gemini-flash-lite  # 切回默认
```

可选模型在 `config/openclaw.template.json` 里登记，支持 OpenRouter 上任意模型，自行追加即可（key 自定义，id 必须与 OpenRouter model slug 一致）。

---

## 四、常用运维命令

| 操作 | 命令 |
| --- | --- |
| 查看进程 | `pm2 status` |
| 查看实时日志 | `pm2 logs myclawbot` |
| 查看健康探针日志 | `pm2 logs myclawbot-healthcheck` 或 `tail -f logs/healthcheck.log` |
| 重启 | `pm2 restart myclawbot` |
| 停止 | `pm2 stop myclawbot` 或 `bash scripts/stop.sh` |
| 启动（前台调试） | `bash scripts/start.sh` |
| 切换模型 | `bash scripts/switch-model.sh <model-key>` |
| 一次性健康检查 | `bash scripts/healthcheck.sh` |
| 重新扫码 | `bash scripts/login-wechat.sh` |
| 查看 OpenClaw 渠道 | `openclaw channels list` |
| 查看 Skills（后期） | `openclaw skills list` |

---

## 五、验收清单（基础能力跑通的判定标准）

部署完成后逐条勾选，全部通过即视为 MVP 完成：

- [ ] **进程在线**：`pm2 status` 中 `myclawbot` 状态为 `online`，无频繁 restart
- [ ] **微信渠道在线**：`openclaw channels list` 中 `openclaw-weixin` 状态为 `connected`
- [ ] **基础对话**：在微信向 ClawBot 发送「你好」，10 秒内收到自然语言回复
- [ ] **多轮上下文**：紧接着发「再用一句话总结你刚才的回答」，回复能引用上一轮内容
- [ ] **日志可追溯**：`pm2 logs myclawbot --lines 50` 能看到 `getUpdates` / `sendMessage` 与 OpenRouter 调用记录
- [ ] **模型切换生效**：执行 `bash scripts/switch-model.sh claude-sonnet` 后，微信里再发同样问题，回复风格/署名应有可观察差异
- [ ] **健康探针**：`bash scripts/healthcheck.sh` 输出全部 `[ ok ]`，退出码 0
- [ ] **自愈能力**：模拟断网后再恢复，`myclawbot-healthcheck` 在连续 3 次失败时自动 `pm2 restart`，恢复后无需重扫码即可继续对话
- [ ] **重启自愈**：`pm2 restart myclawbot` 后微信对话仍可用，无须重新扫码

---

## 六、故障排查

### 1. 扫码后微信没出现 ClawBot 会话
- 检查微信版本是否 ≥ 8.0.70（设置 → 关于微信）
- 重新执行 `bash scripts/login-wechat.sh`
- 查 `pm2 logs myclawbot`，看是否有 `bot_token expired` 或 `errcode -14`（会话超时）

### 2. 报 `requires OpenClaw >=2026.3.22`
说明插件版本与主程序不匹配。重跑 `bash scripts/install.sh` 会自动升级到 `latest`。如确需老版兼容：

```bash
openclaw plugins install @tencent-weixin/openclaw-weixin@legacy
```

### 3. 微信收到消息但没回复
逐项排查：

```bash
pm2 logs myclawbot --lines 100                                      # LLM 调用是否报错
openclaw channels list                                              # 微信渠道是否仍 connected
curl -sS https://openrouter.ai/api/v1/auth/key \
  -H "Authorization: Bearer $OPENROUTER_API_KEY"                    # 验证 key 没欠费/失效
```

最常见原因：
- OpenRouter 账户余额不足或被限流 → 换模型 / 充值 / 切到 `deepseek-chat`
- 配置里 `apiKey` 占位符 `__OPENROUTER_API_KEY__` 没被替换 → 重跑 `bash scripts/install.sh`
- `plugins.entries.openclaw-weixin.enabled` 没开 → `openclaw config set plugins.entries.openclaw-weixin.enabled true && openclaw gateway restart`

### 4. Channel 显示 OK 但消息收不到
按官方文档，确认配置已生效：

```bash
openclaw config set plugins.entries.openclaw-weixin.enabled true
openclaw gateway restart
```

### 5. 服务器重启后掉线
确认 `pm2 startup` 已执行并按提示用 sudo 跑过它输出的命令，否则开机不会拉起 PM2。

### 6. 怎么彻底重置
```bash
pm2 delete myclawbot myclawbot-healthcheck
openclaw plugins uninstall @tencent-weixin/openclaw-weixin
rm -rf ~/.openclaw
bash scripts/install.sh
bash scripts/login-wechat.sh
pm2 start pm2.ecosystem.cjs && pm2 save
```

---

## 七、仓库结构

```
.
├── README.md                       # 当前文件
├── .env.example                    # 环境变量模板（OPENROUTER_API_KEY 等）
├── .gitignore
├── config/
│   └── openclaw.template.json      # OpenClaw 配置模板（含占位符 __OPENROUTER_API_KEY__）
├── scripts/
│   ├── install.sh                  # 一键安装：Node 20 + openclaw + ClawBot 插件 + 渲染配置
│   ├── login-wechat.sh             # 扫码登录
│   ├── start.sh                    # 前台启动 gateway（PM2 内部使用 / 本地调试）
│   ├── stop.sh                     # 停止 gateway
│   ├── switch-model.sh             # 切换默认模型
│   └── healthcheck.sh              # 健康探针
└── pm2.ecosystem.cjs               # PM2 守护描述（含 cron 健康检查）
```

---

## 八、下期路标（暂不实现，仅备忘）

- 5W1H 日程抽取 Skill + MySQL/Postgres 存储
- 晨报 / 晚复盘 Cron
- iOS Shortcuts 上传语音备忘录 → ASR → 自动建日程
- 多用户 / 多账号上下文隔离
- 监控告警接入（Server 酱 / 飞书机器人）
