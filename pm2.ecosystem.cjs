/**
 * PM2 守护配置：私人 AI 管家 / WeChat ClawBot
 *
 * 启动：pm2 start pm2.ecosystem.cjs && pm2 save
 * 自启：pm2 startup   （按 PM2 输出再用 sudo 跑一次）
 * 日志：pm2 logs myclawbot
 */

const path = require('path');
const repoRoot = __dirname;

module.exports = {
  apps: [
    {
      name: 'myclawbot',
      // 由 start.sh 负责加载 .env / nvm，再 exec openclaw gateway
      script: path.join(repoRoot, 'scripts/start.sh'),
      interpreter: 'bash',
      cwd: repoRoot,

      // 守护策略
      autorestart: true,
      restart_delay: 3000,           // 崩溃后 3s 再起
      max_restarts: 50,              // 1 分钟内最多 50 次（防雪崩）
      min_uptime: '30s',             // 起来撑过 30s 才算成功一次
      kill_timeout: 8000,            // SIGTERM -> SIGKILL 间隔
      exp_backoff_restart_delay: 1000, // 持续失败时指数退避

      // 日志
      out_file: path.join(repoRoot, 'logs/myclawbot.out.log'),
      error_file: path.join(repoRoot, 'logs/myclawbot.err.log'),
      merge_logs: true,
      time: true,                    // 日志带时间戳

      // 环境
      env: {
        NODE_ENV: 'production',
        // .env 由 start.sh 内部 source，PM2 这层只兜底默认值
        OPENCLAW_HOME: process.env.OPENCLAW_HOME || `${process.env.HOME}/.openclaw`,
      },
    },

    // 健康探针：每 60s 跑一次，连续失败 3 次自动 pm2 restart myclawbot
    {
      name: 'myclawbot-healthcheck',
      script: path.join(repoRoot, 'scripts/healthcheck.sh'),
      args: '--quiet --auto-restart',
      interpreter: 'bash',
      cwd: repoRoot,
      autorestart: false,            // cron_restart 触发，不要自动拉起
      cron_restart: '* * * * *',     // 每分钟一次
      out_file: path.join(repoRoot, 'logs/healthcheck.out.log'),
      error_file: path.join(repoRoot, 'logs/healthcheck.err.log'),
      merge_logs: true,
      time: true,
    },
  ],
};
