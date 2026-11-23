import base64
import os
import re
import threading
import time
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

CONF_FILE = os.environ.get("MUSEBOT_CONF", "/etc/muse_tg_bot.conf")

HELP_TEXT = (
    "📖 *Muse 机器人使用说明*\n\n"
    "1️⃣ *直接聊天 / 写代码*：直接发送文字即可对话，支持连续上下文；发送 `/clear` 清空当前记忆。\n"
    "2️⃣ *自然语言生图*：直接说“画一张…… / 生成图片…… / 手机壁纸……”，自动识别比例（支持竖屏/横屏/默认 1:1）。\n"
    "3️⃣ *自然语言生视频*：直接说“做个视频…… / 拍一段…… / 10秒竖屏视频……”，后台异步提交并在完成后自动发回。\n"
    "4️⃣ *发图修图 / 图生视频*：发送图片并附带说明（如“改成赛博朋克风格”或“让画面动起来”），自动走图像编辑或图生视频。\n"
    "5️⃣ *强制指定命令*：可用 `/img 提示词`、`/vid 提示词`、`/clear`、`/help`。\n\n"
    "💡 *服务器快捷管理*：在终端输入 `musebot` 可打开中文菜单修改配置、看日志或重启服务。"
)


def load_conf():
    cfg = {
        "TG_TOKEN": os.environ.get("TG_TOKEN", ""),
        "ALLOWED_UID": os.environ.get("ALLOWED_UID", ""),
        "MUSE_BASE": os.environ.get("MUSE_BASE", ""),
        "MUSE_KEY": os.environ.get("MUSE_KEY", ""),
        "TG_PROXY": os.environ.get("TG_PROXY", ""),
    }
    if os.path.exists(CONF_FILE):
        with open(CONF_FILE, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                cfg[k.strip()] = v.strip().strip('"').strip("'")
    return cfg


CFG = load_conf()
TG_TOKEN = CFG["TG_TOKEN"]
ALLOWED_UID = CFG["ALLOWED_UID"]
MUSE_BASE = CFG["MUSE_BASE"].rstrip("/")
MUSE_KEY = CFG["MUSE_KEY"]
TG_PROXY = CFG["TG_PROXY"].strip()

TG_API = f"https://api.telegram.org/bot{TG_TOKEN}"
TG_FILE_API = f"https://api.telegram.org/file/bot{TG_TOKEN}"
HEADERS = {"Authorization": f"Bearer {MUSE_KEY}", "Content-Type": "application/json"}
HISTORY = {}


def build_session(proxies=None):
    s = requests.Session()
    retry = Retry(
        total=3,
        backoff_factor=1.5,
        status_forcelist=[429, 500, 502, 503, 504],
        allowed_methods=["GET", "POST"],
        raise_on_status=False,
    )
    adapter = HTTPAdapter(max_retries=retry, pool_connections=10, pool_maxsize=10)
    s.mount("https://", adapter)
    s.mount("http://", adapter)
    if proxies:
        s.proxies.update(proxies)
    return s


TG_PROXIES = {"http": TG_PROXY, "https": TG_PROXY} if TG_PROXY else None
TG_SESSION = build_session(TG_PROXIES)
MUSE_SESSION = build_session(None)


def tg_request(method, data=None, files=None, params=None, timeout=180):
    for attempt in range(3):
        try:
            if method in ("getUpdates", "getFile"):
                r = TG_SESSION.get(f"{TG_API}/{method}", params=params, timeout=timeout)
            else:
                r = TG_SESSION.post(f"{TG_API}/{method}", data=data, files=files, timeout=timeout)
            return r.json()
        except Exception as e:
            print(f"TG {method} attempt {attempt + 1} error:", e)
            time.sleep(1.5 * (attempt + 1))
    return {}


def tg_post(method, data=None, files=None, timeout=180):
    return tg_request(method, data=data, files=files, timeout=timeout)


def root_origin():
    return MUSE_BASE[:-3] if MUSE_BASE.endswith("/v1") else MUSE_BASE


def normalize_url(u):
    if not u:
        return ""
    if u.startswith("/"):
        return f"{root_origin()}{u}"
    return u


def extract_video_url(st):
    if not isinstance(st, dict):
        return ""
    for cand in [
        (st.get("result") or {}).get("url") if isinstance(st.get("result"), dict) else None,
        st.get("url"),
        st.get("video_url"),
        (st.get("data") or {}).get("url") if isinstance(st.get("data"), dict) else None,
    ]:
        if isinstance(cand, str) and cand.strip():
            return normalize_url(cand.strip())
    return ""


def send_help(chat_id):
    res = tg_post("sendMessage", {"chat_id": chat_id, "text": HELP_TEXT, "parse_mode": "Markdown"})
    if not res.get("ok"):
        plain = HELP_TEXT.replace("*", "")
        tg_post("sendMessage", {"chat_id": chat_id, "text": plain})


def download_tg_photo(msg):
    photos = msg.get("photo") or []
    if not photos:
        return None, None
    file_id = photos[-1]["file_id"]
    info = tg_request("getFile", params={"file_id": file_id}, timeout=30)
    file_path = (info.get("result") or {}).get("file_path")
    if not file_path:
        return None, None
    raw = TG_SESSION.get(f"{TG_FILE_API}/{file_path}", timeout=60).content
    b64 = base64.b64encode(raw).decode("utf-8")
    return raw, f"data:image/jpeg;base64,{b64}"


def parse_media_hints(text):
    img_size = "1:1"
    vid_size = "16:9"
    if any(k in text for k in ["竖屏", "手机壁纸", "短视频", "9:16"]):
        img_size = "9:16"
        vid_size = "9:16"
    elif any(k in text for k in ["横屏", "电脑壁纸", "宽屏", "16:9"]):
        img_size = "16:9"
        vid_size = "16:9"

    duration = 5
    m = re.search(r"(\d+)\s*秒", text)
    if m:
        duration = max(3, min(15, int(m.group(1))))
    return img_size, vid_size, duration


def detect_intent(text, has_image=False):
    if has_image:
        if any(k in text for k in ["视频", "动起来", "动画", "拍成", "做成视频", "图生视频"]):
            return "VIDEO", text or "让这张图片自然动起来"
        return "IMAGE", text or "优化并重绘这张图片"

    sys_prompt = (
        "你是意图路由器。判断用户消息属于哪一种：\n"
        "- VIDEO：明确要求生成/制作/拍/剪视频、动画短片、动起来的视频\n"
        "- IMAGE：明确要求生成/画/绘制/做图片、插画、壁纸、海报、头像\n"
        "- CHAT：普通聊天、问答、写代码、解释、总结等\n"
        "只回复一行：VIDEO | 画面描述 或 IMAGE | 画面描述 或 CHAT | 原文\n"
        "不要多余解释。"
    )
    try:
        r = MUSE_SESSION.post(
            f"{MUSE_BASE}/chat/completions",
            headers=HEADERS,
            json={
                "model": "muse-spark",
                "messages": [
                    {"role": "system", "content": sys_prompt},
                    {"role": "user", "content": text},
                ],
                "temperature": 0,
            },
            timeout=25,
        )
        out = (r.json()["choices"][0]["message"]["content"] or "").strip()
        m = re.match(r"^(VIDEO|IMAGE|CHAT)\s*\|\s*(.*)$", out, re.S | re.I)
        if m:
            return m.group(1).upper(), (m.group(2).strip() or text)
    except Exception as e:
        print("Intent detect fallback to CHAT:", e)

    if any(k in text for k in ["生成视频", "做个视频", "拍个视频", "视频画面", "生成一段视频"]):
        return "VIDEO", text
    if any(k in text for k in ["生成一张", "生成图片", "画一张", "画个", "帮我画", "插画", "壁纸", "海报"]):
        return "IMAGE", text
    return "CHAT", text


def handle_chat(chat_id, text, image_data_uri=None):
    if text.strip() == "/clear":
        HISTORY[chat_id] = []
        tg_post("sendMessage", {"chat_id": chat_id, "text": "对话上下文已清空。"})
        return

    msgs = HISTORY.setdefault(chat_id, [])
    if image_data_uri:
        user_content = [
            {"type": "text", "text": text or "请描述并分析这张图片"},
            {"type": "image_url", "image_url": {"url": image_data_uri}},
        ]
    else:
        user_content = text

    msgs.append({"role": "user", "content": user_content})
    if len(msgs) > 12:
        msgs[:] = msgs[-12:]

    tg_post("sendChatAction", {"chat_id": chat_id, "action": "typing"})
    try:
        r = MUSE_SESSION.post(
            f"{MUSE_BASE}/chat/completions",
            headers=HEADERS,
            json={"model": "muse-spark", "messages": msgs},
            timeout=120,
        )
        reply = r.json()["choices"][0]["message"]["content"]
        msgs.append({"role": "assistant", "content": reply})
    except Exception as e:
        reply = f"对话请求失败: {e}"

    tg_post("sendMessage", {"chat_id": chat_id, "text": reply})


def handle_image(chat_id, prompt, size="1:1", image_data_uri=None):
    if not prompt and not image_data_uri:
        tg_post("sendMessage", {"chat_id": chat_id, "text": "请描述你想生成的图片内容。"})
        return
    tg_post("sendMessage", {"chat_id": chat_id, "text": f"正在处理图片（{size}），请稍候..."})
    tg_post("sendChatAction", {"chat_id": chat_id, "action": "upload_photo"})
    r = None
    try:
        payload = {
            "model": "muse-image",
            "prompt": prompt or "基于参考图进行高质量重绘",
            "size": size,
            "response_format": "url",
        }
        if image_data_uri:
            payload["image"] = image_data_uri
        r = MUSE_SESSION.post(
            f"{MUSE_BASE}/images/generations",
            headers=HEADERS,
            json=payload,
            timeout=260,
        )
        data = r.json()
        img_url = normalize_url(data["data"][0]["url"])
        img_bytes = MUSE_SESSION.get(img_url, timeout=60).content
        tg_post("sendPhoto", {"chat_id": chat_id, "caption": (prompt or "完成")[:200]}, files={"photo": ("image.webp", img_bytes)})
    except Exception as e:
        raw = r.text[:300] if r is not None else ""
        tg_post("sendMessage", {"chat_id": chat_id, "text": f"生图/修图失败: {e}\n原始响应: {raw}"})


def _video_worker(chat_id, prompt, duration=5, size="16:9", image_data_uri=None):
    tg_post("sendMessage", {"chat_id": chat_id, "text": f"已提交生视频任务（{duration}秒 / {size}），预计需要 1~5 分钟，完成后自动发送..."})
    tg_post("sendChatAction", {"chat_id": chat_id, "action": "upload_video"})
    try:
        payload = {
            "model": "muse-video",
            "prompt": prompt or "让参考图中的画面自然流畅地动起来",
            "duration": duration,
            "size": size,
        }
        if image_data_uri:
            payload["image"] = image_data_uri
        r = MUSE_SESSION.post(
            f"{MUSE_BASE}/videos",
            headers=HEADERS,
            json=payload,
            timeout=60,
        )
        task = r.json()
        task_id = task.get("id")
        print(f"Video task created: {task_id}, raw={str(task)[:200]}")
        if not task_id:
            tg_post("sendMessage", {"chat_id": chat_id, "text": f"创建视频任务失败: {task}"})
            return

        for _ in range(140):
            time.sleep(5)
            try:
                st = MUSE_SESSION.get(f"{MUSE_BASE}/videos/{task_id}", headers=HEADERS, timeout=30).json()
            except Exception as pe:
                print(f"Poll video {task_id} error:", pe)
                continue
            status = str(st.get("status") or "").lower()
            if status in ("succeeded", "completed"):
                vid_url = extract_video_url(st)
                print(f"Video {task_id} {status}, url={vid_url}")
                if not vid_url:
                    tg_post("sendMessage", {"chat_id": chat_id, "text": f"视频已完成但未找到链接: {str(st)[:300]}"})
                    return
                vid_bytes = MUSE_SESSION.get(vid_url, timeout=180).content
                print(f"Video {task_id} downloaded {len(vid_bytes)} bytes, uploading to TG...")
                res = tg_post("sendVideo", {"chat_id": chat_id, "caption": (prompt or "完成")[:200]}, files={"video": ("video.mp4", vid_bytes)}, timeout=240)
                print(f"TG sendVideo result: ok={res.get('ok')} desc={res.get('description', '')}")
                if not res.get("ok"):
                    tg_post("sendMessage", {"chat_id": chat_id, "text": f"视频发送失败: {res.get('description', res)}"})
                return
            elif status in ("failed", "error"):
                tg_post("sendMessage", {"chat_id": chat_id, "text": f"视频生成失败: {str(st)[:300]}"})
                return
        tg_post("sendMessage", {"chat_id": chat_id, "text": "视频生成超时（超过 700 秒）。"})
    except Exception as e:
        print(f"Video worker error: {e}")
        tg_post("sendMessage", {"chat_id": chat_id, "text": f"生视频异常: {e}"})


def handle_video(chat_id, prompt, duration=5, size="16:9", image_data_uri=None):
    if not prompt and not image_data_uri:
        tg_post("sendMessage", {"chat_id": chat_id, "text": "请描述你想生成的视频内容。"})
        return
    threading.Thread(
        target=_video_worker,
        args=(chat_id, prompt, duration, size, image_data_uri),
        daemon=True,
    ).start()


def main():
    if not TG_TOKEN or not MUSE_BASE or not MUSE_KEY:
        print("错误: 请先配置 TG_TOKEN、MUSE_BASE 和 MUSE_KEY。")
        while True:
            time.sleep(60)
    offset = 0
    print("Muse Telegram Bot started...")
    while True:
        try:
            res = tg_request("getUpdates", params={"timeout": 30, "offset": offset}, timeout=45)
            if not res.get("ok") and "result" not in res:
                time.sleep(2)
                continue
            for upd in res.get("result", []):
                offset = upd["update_id"] + 1
                msg = upd.get("message") or {}
                chat_id = msg.get("chat", {}).get("id")
                uid = str(msg.get("from", {}).get("id", ""))
                if not chat_id:
                    continue
                if ALLOWED_UID and uid != str(ALLOWED_UID):
                    continue

                _, img_data_uri = download_tg_photo(msg)
                has_image = bool(img_data_uri)
                text = ((msg.get("text") or msg.get("caption")) or "").strip()
                if not text and not has_image:
                    continue

                low = text.lower()
                if not has_image and (low in ("/help", "/start", "使用说明", "帮助", "菜单")):
                    send_help(chat_id)
                    continue

                img_size, vid_size, duration = parse_media_hints(text)
                if text.startswith("/img"):
                    handle_image(chat_id, text[4:].strip(), size=img_size, image_data_uri=img_data_uri)
                elif text.startswith("/vid"):
                    handle_video(chat_id, text[4:].strip(), duration=duration, size=vid_size, image_data_uri=img_data_uri)
                elif text.strip() == "/clear":
                    handle_chat(chat_id, text)
                else:
                    intent, prompt = detect_intent(text, has_image=has_image)
                    if intent == "IMAGE":
                        handle_image(chat_id, prompt, size=img_size, image_data_uri=img_data_uri)
                    elif intent == "VIDEO":
                        handle_video(chat_id, prompt, duration=duration, size=vid_size, image_data_uri=img_data_uri)
                    else:
                        handle_chat(chat_id, text, image_data_uri=img_data_uri)
        except Exception as e:
            print("Polling error:", e)
            time.sleep(3)


if __name__ == "__main__":
    main()
