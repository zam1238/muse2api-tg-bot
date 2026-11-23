#!/usr/bin/env bash
CONF="/etc/muse_tg_bot.conf"
SERVICE="muse-tg"
REPO_RAW="https://raw.githubusercontent.com/zam1238/muse2api-tg-bot/main"
BOT_SCRIPT="/opt/muse_tg_bot.py"
MENU_BIN="/usr/local/bin/musebot"

ensure_conf() {
  [ -f "$CONF" ] || cat << 'EOC' > "$CONF"
TG_TOKEN=""
ALLOWED_UID=""
MUSE_BASE=""
MUSE_KEY=""
TG_PROXY=""
MAX_HISTORY="60"
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

install_singbox_action() {
  if command -v sing-box >/dev/null 2>&1; then
    echo "已检测到 sing-box（$(sing-box version | head -n 1)），可直接跳过安装，去菜单选 10 填入节点。"
    read -rp "按回车键返回主菜单..." _
    return
  fi
  echo "未检测到 sing-box，正在尝试安装..."
  if bash -c "$(curl -fsSL https://sing-box.app/deb-install.sh)" 2>/dev/null || bash -c "$(curl -fsSL https://sing-box.app/install.sh)" 2>/dev/null; then
    command -v sing-box >/dev/null 2>&1 && echo "sing-box 安装完成: $(sing-box version | head -n 1)" || echo "安装脚本已执行，请检查输出"
  else
    echo "自动安装失败（可能是当前机器网络或权限限制）。"
  fi
  read -rp "按回车键返回主菜单..." _
}

uninstall_singbox_action() {
  echo "正在停止 sing-box 并清理相关文件与代理配置..."
  systemctl stop sing-box >/dev/null 2>&1 || true
  systemctl disable sing-box >/dev/null 2>&1 || true
  pkill -f "sing-box" >/dev/null 2>&1 || true

  if command -v apt-get >/dev/null 2>&1; then
    apt-get remove -y -qq sing-box >/dev/null 2>&1 || true
    apt-get purge -y -qq sing-box >/dev/null 2>&1 || true
  fi

  rm -f /usr/local/bin/sing-box /usr/bin/sing-box /etc/systemd/system/sing-box.service
  rm -rf /etc/sing-box /tmp/muse_proxy_singbox.json /tmp/muse_hy2_singbox.json
  systemctl daemon-reload >/dev/null 2>&1 || true

  save_kv "TG_PROXY" ""
  ensure_conf
  if systemctl is-active "$SERVICE" >/dev/null 2>&1; then
    systemctl restart "$SERVICE"
    echo "已卸载 sing-box、删除残留配置、清空代理配置并重启 $SERVICE（已恢复直连）。"
  else
    echo "已卸载 sing-box、删除残留配置并清空代理配置（已恢复直连）。"
  fi
  read -rp "按回车键返回主菜单..." _
}

manage_singbox() {
  clear
  echo "=========================================="
  echo "       sing-box 管理（安装 / 卸载）"
  echo "=========================================="
  if command -v sing-box >/dev/null 2>&1; then
    echo "当前状态：已安装（$(sing-box version | head -n 1)）"
  else
    echo "当前状态：未安装"
  fi
  echo "------------------------------------------"
  echo "  1. 安装 / 检查 sing-box（已有则跳过）"
  echo "  2. 卸载 sing-box（并自动清理配置与代理）"
  echo "  0. 返回主菜单"
  echo "=========================================="
  read -rp "请选择 [0-2]: " sub_choice
  case "$sub_choice" in
    1) install_singbox_action ;;
    2) uninstall_singbox_action ;;
    0) return ;;
    *) echo "无效选项"; sleep 1 ;;
  esac
}

show_usage() {
  clear
  cat << 'EOU'
==========================================
        Muse 机器人使用说明 & 提示格式
==========================================
【一、常用提示词 / 发送格式】
1. 聊天 / 写代码
   直接发文字即可，自动保留最近若干条上下文；
   发 /clear 清空当前上下文记忆。

2. 生图格式（支持自动路由或 /img）
- 自然语言：画一张…… / 生成图片…… / 手机壁纸……
  - 显式命令：/img 画面主体，风格细节，比例要求
  - 比例关键词：含“竖屏/手机壁纸/短视频/9:16”走 9:16；
                含“横屏/电脑壁纸/宽屏/16:9”走 16:9；
                默认 1:1。
   示例：/img 橘猫在草地上晒太阳，水彩插画，竖屏

3. 生视频格式（支持自动路由或 /vid）
- 自然语言：做个视频…… / 拍一段…… / 10秒竖屏视频……
  - 显式命令：/vid 画面主体 + 动作 + 镜头/时长/比例
  - 时长与比例：支持“X秒”（限制 3~15 秒，默认 5 秒）；
                支持“竖屏/9:16”或“横屏/16:9”（默认 16:9）。
   示例：/vid 小猫在草地上奔跑，镜头跟随，6秒竖屏

4. 发图修图 / 图生视频格式
- 发送图片并在图片说明（Caption）里写要求：
  - 修图/改风格：发送图片 + 说明“改成赛博朋克风格”
    - 图生视频：发送图片 + 说明“让画面自然动起来，5秒”

5. 查看说明
   在 TG 中发送 /help 或 “使用说明” 即可查看。

【二、代理使用与卸载步骤】
- 需要走代理时：
  1. 选 11 -> 1 安装 sing-box；如果机器上已经有 sing-box，
     可直接跳过安装。
2. 选 10 填入现有节点（支持 hysteria2://、vless://、
     socks5h:// 或 http://）。
3. 选 5 重启服务使代理生效。
- 不需要/想取消代理时：
  - 只需恢复直连：选 10 直接回车留空，再选 5 重启。
  - 彻底卸载 sing-box：选 11 -> 2，会自动停掉进程、
    删除残留配置、清空代理配置并恢复直连。

【三、终端快捷管理】
随时在终端输入 musebot 打开管理菜单。
==========================================
EOU
  read -rp "按回车键返回主菜单..." _
}

while true; do
  ensure_conf
  STATUS=$(systemctl is-active "$SERVICE" 2>/dev/null || true)
  SB_STATE="未安装"
  command -v sing-box >/dev/null 2>&1 && SB_STATE="已安装"
  clear
  echo "=========================================="
  echo "     Muse2API Telegram 机器人管理菜单"
  echo "=========================================="
  echo " 运行状态 : $STATUS"
  echo " sing-box : $SB_STATE"
  echo " Bot Token: $(mask_token "$TG_TOKEN")"
  echo " 允许 UID : ${ALLOWED_UID:-未限制（所有人可用）}"
  echo " 接口地址 : ${MUSE_BASE:-未设置}"
  echo " API 密钥 : ${MUSE_KEY:-未设置}"
  echo " TG 代理  : ${TG_PROXY:-未设置（直连）}"
  echo " 上下文数 : ${MAX_HISTORY:-60} 条"
  echo "------------------------------------------"
  echo "  1. 修改 Telegram Bot Token"
  echo "  2. 修改允许的 Telegram 用户 ID（留空则不限制）"
  echo "  3. 修改 Muse2API 接口地址 (BASE_URL)"
  echo "  4. 修改 Muse2API 访问密钥 (API_KEY)"
  echo "  5. 保存并重启机器人服务"
  echo "  6. 启动 / 停止 机器人服务"
  echo "  7. 查看实时运行日志（Ctrl+C 退出日志）"
  echo "  8. 检查并安装 requests 与 SOCKS 依赖"
  echo "  9. 查看使用说明与提示格式"
  echo " 10. 设置代理"
  echo " 11. 代理内核管理（安装 / 卸载 sing-box）"
  echo " 12. 一键更新脚本（保留当前配置）"
  echo " 13. 修改上下文记忆条数（默认 60）"
  echo "  0. 退出菜单"
  echo "=========================================="
  read -rp "请输入选项 [0-13]: " choice

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
      if python3 -c "import requests, socks" 2>/dev/null; then
        echo "requests 与 SOCKS 支持 (PySocks) 均已安装"
      else
        echo "正在安装 requests[socks] / PySocks..."
        pip install -q -U "requests[socks]" PySocks 2>/dev/null || \
        pip install -q -U --break-system-packages "requests[socks]" PySocks 2>/dev/null || \
        (apt-get update -qq && apt-get install -y -qq python3-requests python3-socks)
        python3 -c "import requests, socks" 2>/dev/null && echo "安装成功：已支持 HTTP 与 SOCKS5 代理" || echo "安装未完成，请检查报错"
      fi
      sleep 1
      ;;
    9)
      show_usage
      ;;
    10)
      echo "提示：若需走代理，先用 11 装 sing-box（已有则跳过），再在此处填入现有节点（hysteria2:// / vless:// / socks5h:// / http://）；留空则直连。"
      read -rp "请输入代理节点或地址: " val
      save_kv "TG_PROXY" "$val"
      if [ -n "$val" ]; then
        echo "已更新代理配置（请选 5 重启服务生效）"
      else
        echo "已清空代理配置，恢复直连（请选 5 重启服务生效）"
      fi
      sleep 1
      ;;
    11)
      manage_singbox
      ;;
    12)
      echo "正在拉取最新 muse_tg_bot.py 与 musebot..."
      if curl -fsSL "$REPO_RAW/muse_tg_bot.py" -o "${BOT_SCRIPT}.tmp" && \
         curl -fsSL "$REPO_RAW/musebot.sh" -o "${MENU_BIN}.tmp"; then
        mv "${BOT_SCRIPT}.tmp" "$BOT_SCRIPT"
        chmod +x "${MENU_BIN}.tmp"
        mv "${MENU_BIN}.tmp" "$MENU_BIN"
        ensure_conf
        systemctl daemon-reload
        if systemctl is-active "$SERVICE" >/dev/null 2>&1; then
          systemctl restart "$SERVICE"
          echo "更新完成并已重启 $SERVICE 服务（配置已保留）！"
        else
          echo "更新完成（配置已保留），如需启动可按 5 或 6。"
        fi
        sleep 1
        exit 0
      else
        rm -f "${BOT_SCRIPT}.tmp" "${MENU_BIN}.tmp"
        echo "拉取更新失败，请检查网络或 GitHub 访问状态。"
        sleep 2
      fi
      ;;
    13)
      read -rp "请输入保留的上下文消息条数（建议 20~120，当前 ${MAX_HISTORY:-60}）: " val
      if [[ "$val" =~ ^[0-9]+$ ]] && [ "$val" -ge 4 ]; then
        save_kv "MAX_HISTORY" "$val"
        echo "已更新 MAX_HISTORY 为 $val（请选 5 重启服务生效）"
      else
        echo "输入无效，请输入大于等于 4 的整数"
      fi
      sleep 1
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
