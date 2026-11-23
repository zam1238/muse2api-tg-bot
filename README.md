# muse2api-tg-bot

基于 Muse2API 接口的 Telegram 机器人，支持多轮对话、自然语言意图路由、生图/图像编辑、异步生视频/图生视频以及终端管理菜单（`musebot`）。

## 功能特性

- **对话与代码（`muse-spark`）**：保留最近 12 条上下文记忆，发送 `/clear` 清空当前上下文。
- **自动意图路由**：直接发送自然语言即可识别聊天、生图或生视频，也支持 `/img`、`/vid` 显式调用与比例、时长自动识别。
- **发图修图与图生视频**：发送图片并附带说明即可进行图像编辑或图生视频。
- **后台异步生视频**：视频任务在后台线程轮询，不阻塞聊天与生图。
- **终端管理菜单（`musebot`）**：提供参数配置、服务启停/重启、实时日志查看、依赖安装、代理设置、`sing-box` 安装/卸载与使用说明。

## 一键安装

在 Linux 终端（建议 Debian/Ubuntu）中执行以下命令下载脚本并安装依赖：

```bash
curl -fsSL [https://raw.githubusercontent.com/zam1238/muse2api-tg-bot/main/muse_tg_bot.py](https://raw.githubusercontent.com/zam1238/muse2api-tg-bot/main/muse_tg_bot.py) -o /opt/muse_tg_bot.py
curl -fsSL [https://raw.githubusercontent.com/zam1238/muse2api-tg-bot/main/musebot.sh](https://raw.githubusercontent.com/zam1238/muse2api-tg-bot/main/musebot.sh) -o /usr/local/bin/musebot
chmod +x /usr/local/bin/musebot
pip install -q -U "requests[socks]" PySocks 2>/dev/null || pip install -q -U --break-system-packages "requests[socks]" PySocks 2>/dev/null || (apt-get update -qq && apt-get install -y -qq python3-requests python3-socks)

## 配置说明

参考 `.env.example` 配置以下参数（可通过环境变量或 `/etc/muse_tg_bot.conf` 传入）[cite: 5]：

- `TG_TOKEN`：Telegram Bot Token[cite: 5]
- `ALLOWED_UID`：允许使用的 Telegram 用户 ID（留空则不限制）[cite: 5]
- `MUSE_BASE`：Muse2API 接口地址（如 `https://your-domain/v1`）[cite: 5]
- `MUSE_KEY`：Muse2API 访问密钥[cite: 5]
- `TG_PROXY`：可选代理节点或地址（支持 `hysteria2://`、`vless://`、`socks5h://`、`http://`；留空则直连）[cite: 5]

## 使用方法

### 1. 终端菜单与代理配置
1. 在终端输入 `musebot` 打开管理菜单[cite: 5]。
2. 选 `1`~`4` 填入 `TG_TOKEN`、`ALLOWED_UID`、`MUSE_BASE`、`MUSE_KEY`[cite: 5]。
3. **如需走代理**：
   - 先选 `11` -> `1` 安装/检查 `sing-box`（若机器上已有 `sing-box`，可直接跳过安装）[cite: 5]。
   - 再选 `10` 填入现有节点（`hysteria2://`、`vless://`、`socks5h://` 或 `http://`）；留空则走直连[cite: 5]。
   - 如需取消代理或彻底清理，可选 `10` 留空恢复直连，或选 `11` -> `2` 卸载 `sing-box` 并自动清空代理配置[cite: 5]。
4. 选 `5` 保存并重启服务，选 `7` 查看实时日志（按 `Ctrl+C` 退出）[cite: 5]。

### 2. Telegram 交互与提示词格式
- **聊天 / 写代码**：直接发文字即可，发 `/clear` 清空记忆[cite: 5]。
- **生图**：直接说“画一张…… / 手机壁纸……”，或用 `/img 画面主体 + 风格 + 竖屏/横屏`（含“竖屏/手机壁纸/短视频/9:16”走 `9:16`，含“横屏/电脑壁纸/宽屏/16:9”走 `16:9`，默认 `1:1`）[cite: 5]。
- **生视频**：直接说“做个视频…… / 10秒竖屏视频……”，或用 `/vid 画面主体 + 动作 + X秒 + 竖屏/横屏`（时长支持 `3~15` 秒默认 `5` 秒，比例默认 `16:9`）[cite: 5]。
- **发图修图 / 图生视频**：发送图片并在说明里写“改成赛博朋克风格”或“让画面自然动起来，5秒”[cite: 5]。
- **查看说明**：在机器人中发送 `/help` 或“使用说明”[cite: 5]。
