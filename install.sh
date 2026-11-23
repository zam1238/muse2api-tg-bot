#!/usr/bin/env bash
set -e

REPO_RAW="https://raw.githubusercontent.com/zam1238/muse2api-tg-bot/main"
BOT_SCRIPT="/opt/muse_tg_bot.py"
MENU_BIN="/usr/local/bin/musebot"
CONF_FILE="/etc/muse_tg_bot.conf"
SERVICE_FILE="/etc/systemd/system/muse-tg.service"

echo "1/4 下载机器人主程序与 musebot 菜单..."
mkdir -p /opt /etc
curl -fsSL "$REPO_RAW/muse_tg_bot.py" -o "$BOT_SCRIPT"
curl -fsSL "$REPO_RAW/musebot.sh" -o "$MENU_BIN"
chmod +x "$MENU_BIN"

echo "2/4 安装 requests 与 SOCKS 依赖..."
pip install -q -U "requests[socks]" PySocks 2>/dev/null || \
pip install -q -U --break-system-packages "requests[socks]" PySocks 2>/dev/null || \
(apt-get update -qq && apt-get install -y -qq python3-requests python3-socks)

echo "3/4 初始化配置文件..."
if [ ! -f "$CONF_FILE" ]; then
  cat << 'EOF' > "$CONF_FILE"
TG_TOKEN=""
ALLOWED_UID=""
MUSE_BASE=""
MUSE_KEY=""
TG_PROXY=""
EOF
fi

echo "4/4 配置并启用 systemd 服务 (muse-tg)..."
cat << EOF > "$SERVICE_FILE"
[Unit]
Description=Muse2API Telegram Media & Chat Bot
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=$CONF_FILE
ExecStart=/usr/bin/python3 $BOT_SCRIPT
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable muse-tg.service >/dev/null 2>&1 || true

echo "安装完成！现在输入 musebot 即可打开管理菜单。"
