#!/usr/bin/env bash
CONF="/etc/muse_tg_bot.conf"
SERVICE="muse-tg"

ensure_conf() {
  [ -f "$CONF" ] || cat << 'EOC' > "$CONF"
TG_TOKEN=""
ALLOWED_UID=""
MUSE_BASE=""
MUSE_KEY=""
TG_PROXY=""
EOC
  source "$CONF"
}

save_kv() {
  local key="$1" val="$2"
  ensure_conf
  python3 - "$CONF" "$key" "$val" << 'EOP'
import sys
path, k, v = sys.argv[1], sys.argv[2], sys.argv[3]
lines = []
found = False
with open(path, "r", encoding="utf-8") as f:
    for line in f:
        if line.strip().startswith(k + "="):
            lines.append(f'{k}="{v}"\n')
            found = True
        else:
            lines.append(line)
if not found:
    lines.append(f'{k}="{v}"\n')
with open(path, "w", encoding="utf-8") as f:
    f.writelines(lines)
EOP
}

mask_token() {
  local t="$1"
  if [ -z "$t" ]; then
    echo "未设置"
  elif [ "${#t}" -le 10 ]; then
    echo "已设置"
  else
    echo "${t:0:6}****${t: -4}"
  fi
}

show_usage() {
  clear
  cat << 'EOU'
==========================================
            Muse 机器人使用说明
==========================================
1. 正常聊天 / 写代码
   直接发送文字消息，自动保留最近 12 条上下文；
   发送 /clear 可清空当前对话记忆。

2. 自然语言生图（无需记命令）
   直接发“画一张…… / 生成图片…… / 手机壁纸……”
   支持自动识别“竖屏/9:16”、“横屏/16:9”，默认 1:1。

3. 自然语言生视频（无需记命令）
   直接发“做个视频…… / 拍一段…… / 10秒竖屏视频……”
   异步提交并在完成后自动发送视频（默认 5 秒、16:9）。

4. 发图修图 / 图生视频
   发送图片并附带说明（如“改成赛博朋克”或“让它动起来”），
   自动识别调用图像编辑或图生视频。

5. 强制指定命令
   /img 提示词   强制生图
   /vid 提示词   强制生视频
   /clear        清空对话历史
   /help         在 TG 中查看使用说明

6. 终端快捷管理
   随时在终端输入 musebot 打开本菜单。
==========================================
EOU
  read -rp "按回车键返回主菜单..." _
}

while true; do
  ensure_conf
  STATUS=$(systemctl is-active "$SERVICE" 2>/dev/null || true)
  clear
  echo "=========================================="
  echo "     Muse2API Telegram 机器人管理菜单"
  echo "=========================================="
  echo " 运行状态 : $STATUS"
  echo " Bot Token: $(mask_token "$TG_TOKEN")"
  echo " 允许 UID : ${ALLOWED_UID:-未限制（所有人可用）}"
  echo " 接口地址 : ${MUSE_BASE:-未设置}"
  echo " API 密钥 : ${MUSE_KEY:-未设置}"
  echo "------------------------------------------"
  echo "  1. 修改 Telegram Bot Token"
  echo "  2. 修改允许的 Telegram 用户 ID（留空则不限制）"
  echo "  3. 修改 Muse2API 接口地址 (BASE_URL)"
  echo "  4. 修改 Muse2API 访问密钥 (API_KEY)"
  echo "  5. 保存并重启机器人服务"
  echo "  6. 启动 / 停止 机器人服务"
  echo "  7. 查看实时运行日志（Ctrl+C 退出日志）"
  echo "  8. 检查并安装 requests 依赖"
  echo "  9. 查看使用说明"
  echo "  0. 退出菜单"
  echo "=========================================="
  read -rp "请输入选项 [0-9]: " choice

  case "$choice" in
    1)
      read -rp "请输入新的 Telegram Bot Token: " val
      [ -n "$val" ] && save_kv "TG_TOKEN" "$val" && echo "已更新 TG_TOKEN" || echo "未修改"
      sleep 1
      ;;
    2)
      read -rp "请输入允许的 Telegram 数字 ID（直接回车清空限制）: " val
      save_kv "ALLOWED_UID" "$val"
      echo "已更新 ALLOWED_UID"
      sleep 1
      ;;
    3)
      read -rp "请输入新的 BASE_URL: " val
      [ -n "$val" ] && save_kv "MUSE_BASE" "$val" && echo "已更新 MUSE_BASE" || echo "未修改"
      sleep 1
      ;;
    4)
      read -rp "请输入新的 API_KEY: " val
      [ -n "$val" ] && save_kv "MUSE_KEY" "$val" && echo "已更新 MUSE_KEY" || echo "未修改"
      sleep 1
      ;;
    5)
      systemctl daemon-reload
      systemctl enable "$SERVICE" >/dev/null 2>&1
      systemctl restart "$SERVICE"
      echo "已重启 $SERVICE 服务"
      sleep 1
      ;;
    6)
      if [ "$STATUS" = "active" ]; then
        systemctl stop "$SERVICE"
        echo "已停止 $SERVICE"
      else
        systemctl start "$SERVICE"
        echo "已启动 $SERVICE"
      fi
      sleep 1
      ;;
    7)
      journalctl -u "$SERVICE" -n 50 -f
      ;;
    8)
      python3 -c "import requests" 2>/dev/null && echo "requests 已安装" || (pip install -q requests || apt-get update -qq && apt-get install -y -qq python3-requests)
      sleep 1
      ;;
    9)
      show_usage
      ;;
    0)
      exit 0
      ;;
    *)
      echo "无效选项"
      sleep 1
      ;;
  esac
done
