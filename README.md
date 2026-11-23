# muse2api-tg-bot
# MUSEBOT

基于 Muse2API 接口的 Telegram 机器人，支持多轮对话、自然语言意图路由、生图/图像编辑、异步生视频/图生视频以及终端管理菜单。

## 功能特性
- **对话与代码（`muse-spark`）**：保留最近 12 条上下文记忆，支持 `/clear` 清空。
- **自动意图路由**：无需记命令，直接发送自然语言即可识别聊天、生图或生视频，也支持 `/img`、`/vid` 显式调用与比例/时长自动识别。
- **发图修图与图生视频**：发送图片并附带说明即可进行图像编辑或图生视频。
- **后台异步生视频**：视频任务在后台线程异步轮询，不阻塞聊天与生图。
- **终端管理菜单（`musebot.sh`）**：提供配置修改、服务启停/重启、日志查看、依赖安装与使用说明。

## 配置说明
参考 `.env.example` 配置以下参数（可通过环境变量或 `/etc/muse_tg_bot.conf` 传入）：
- `TG_TOKEN`：Telegram Bot Token
- `ALLOWED_UID`：允许使用的 Telegram 用户 ID（留空则不限制）
- `MUSE_BASE`：Muse2API 接口地址（如 `https://your-domain/v1`）
- `MUSE_KEY`：Muse2API 访问密钥
- `TG_PROXY`：可选，Telegram 请求代理地址
