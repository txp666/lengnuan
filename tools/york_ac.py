#!/usr/bin/env python3
"""约克智慧家 Wi-Fi 线控器 —— 命令行控制小工具（协议验证用）

只用 Python 标准库，macOS 自带的 python3 就能跑，不用装任何依赖。

用法（在“终端”里）：
    python3 tools/york_ac.py login          # 手机号 + 密码登录（加 --sms 用短信验证码）
    python3 tools/york_ac.py devices        # 列出账号下的线控器
    python3 tools/york_ac.py status         # 查看当前状态
    python3 tools/york_ac.py on / off       # 开机 / 关机
    python3 tools/york_ac.py temp 26        # 设温度（支持 0.5 步进，如 25.5）
    python3 tools/york_ac.py mode cool      # 模式：cool 制冷 / heat 制热 / fan 送风 / dry 除湿 / auto 自动
    python3 tools/york_ac.py fan auto       # 风速：low 低 / medium 中 / high 高 / auto 自动 ...
    python3 tools/york_ac.py set --on --mode cool --temp 26 --fan auto   # 一条指令改多项
    python3 tools/york_ac.py watch          # 持续显示面板上报的状态（Ctrl+C 退出）

加 -v 会打印发送的指令内容，方便排查。

协议来自开源项目 ha-york-smart-home（MIT 许可，对「约克智慧家」App 抓包分析）：
https://github.com/mufeng05/ha-york-smart-home
接口是海信日立 hicloud 云（1app.hicloud.hisensehitachi.com），全程走云端。

注意：约克智慧家同一个账号只能在一处登录。用这个脚本登录后，手机 App 会被挤下线，
反之亦然。最好另注册一个账号，在 App 里把它邀请进同一个家庭，给脚本专用。
"""

from __future__ import annotations

import argparse
import getpass
import json
import os
import secrets
import socket
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

# ---------------------------------------------------------------- 协议常量

API_BASE = os.environ.get("YORK_API_BASE", "https://1app.hicloud.hisensehitachi.com")
API_KEY = "61PdDpLyYzpctYwwVpbHRb2"
APP_ID = "com.hisensehitachi.iyes2"
APP_VERSION = "1.8.2.260807104325_release"
APP_TAG = "V1"
CTRL_TYPE_SINGLE = "YO420"

CONFIG_PATH = os.environ.get("YORK_CONFIG", os.path.expanduser("~/.york-ac.json"))

# 模式（App 里的顺序）：id, 中文, 控制键, 能力键。当前模式 = 第一个控制键为 "1" 的。
MODES = [
    ("fresh_air_eco", "节能新风", "wire_controller_saveene_freshair", "saveene_freshair"),
    ("cool", "制冷", "wire_controller_makecold", "wire_controller_makecold_fix"),
    ("heat", "制热", "wire_controller_heating", "wire_controller_heating_fix"),
    ("fan", "送风", "wire_controller_makewind", "wire_controller_makewind_fix"),
    ("dry", "除湿", "wire_controller_rmwet", "wire_controller_rmwet_fix"),
    ("auto", "自动", "wire_controller_auto", "wire_controller_auto_fix"),
    ("dry_comfort", "干爽除湿", "wire_controller_dry_comfortable_rmwet", "is_dehumidification2_avalable"),
    ("dry_strong", "强力除湿", "wire_controller_strong_rmwet", "is_dehumidification3_avalable"),
    ("dry_auto", "自动除湿", "wire_controller_auto_rmwet", "wire_controller_auto_rmwet_fix"),
    ("floor_heat", "地暖", "wire_controller_floor_heat", "is_floor_heating_avalable"),
    ("dry_floor_heat", "除湿+地暖", "wire_controller_rmwet_floor_heating", "controllerFloorRmwetFix"),
    ("fan_floor_heat", "送风+地暖", "wire_controller_air_supply_floor_heating", "air_supply_floor_heating"),
    ("heat_floor_heat", "制热+地暖", "wire_controller_heat_floor_heating", "controllerFloorHeatFix"),
    ("purify", "净化", "wire_controller_purification", "is_purification_available"),
    ("heat_supply", "供热", "wire_controller_heating_mode", "is_heating_mode_available"),
]
# 普通线控器（xkqType 8）没有这两种模式
STANDARD_EXCLUDED_MODES = {"fresh_air_eco", "heat_supply"}

# 风速，从低到高：id, 中文, 控制键, 能力键
FANS = [
    ("silent", "微风", "wire_controller_wind_light", "wire_controller_wind_silent"),
    ("super_low", "超低", "wire_controller_wind_superlow", "wire_controller_wind_superlow_fix"),
    ("low", "低", "wire_controller_wind_low", "wire_controller_wind_low_fix"),
    ("medium", "中", "wire_controller_wind_mid", "wire_controller_wind_mid_fix"),
    ("high", "高", "wire_controller_wind_high", "wire_controller_wind_high_fix"),
    ("super_high", "超高", "wire_controller_wind_superhigh", "wire_controller_wind_superhign_fix"),
    ("auto", "自动", "wire_controller_wind_auto", "wire_controller_wind_auto_fix"),
]

MODE_ALIASES = {"fan_only": "fan", "dehumidify": "dry"}
FAN_ALIASES = {"mid": "medium", "med": "medium", "breeze": "silent"}

COOL_RANGE_MODES = {"cool", "fan", "dry", "dry_comfort", "dry_strong", "dry_auto"}
HEAT_RANGE_MODES = {"heat", "floor_heat", "dry_floor_heat", "fan_floor_heat",
                    "heat_floor_heat", "heat_supply", "purify"}
MODES_WITHOUT_TEMP = {"fresh_air_eco", "dry_auto", "dry_floor_heat"}
MODES_WITHOUT_FAN = {"floor_heat"}

KEY_POWER = "if_run"
KEY_SET_TEMP = "set_temp"
KEY_SET_TEMP_HALF = "set_temperature_add05"

VERBOSE = False


class Fail(Exception):
    """给用户看的错误。"""


class SessionTaken(Fail):
    """HTTP 401：账号在别处登录了。"""


# ---------------------------------------------------------------- 小工具

def is_on(v) -> bool:
    return v is True or v == 1 or v == "1"


def num(v):
    if v is None or isinstance(v, bool):
        return None
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def parse_constants(v) -> dict:
    if isinstance(v, str):
        try:
            v = json.loads(v)
        except ValueError:
            return {}
    return dict(v) if isinstance(v, dict) else {}


def log(*a):
    if VERBOSE:
        print("[debug]", *a, file=sys.stderr)


def load_config() -> dict:
    try:
        with open(CONFIG_PATH, encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return {}
    except ValueError:
        raise Fail(f"配置文件 {CONFIG_PATH} 损坏，删掉它后重新 login 即可。")


def save_config(cfg: dict) -> None:
    tmp = CONFIG_PATH + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)
    os.replace(tmp, CONFIG_PATH)
    os.chmod(CONFIG_PATH, 0o600)


# ---------------------------------------------------------------- HTTP

def headers(token: str | None) -> dict:
    return {
        "Content-Type": "application/json",
        "Accept": "application/json, text/plain, */*",
        "X-His-AppId": APP_ID,
        "X-His-AppTag": APP_TAG,
        "X-His-APIKey": API_KEY,
        "X-His-Version": APP_VERSION,
        "X-His-OS": "Android",
        "X-His-Locale": "zh_CN",
        "X-His-Timestamp": str(int(time.time() * 1000)),
        "Authorization": f"Bearer {token}" if token else "Bearer",
    }


def envelope(method: str, path: str, *, params=None, body=None, token=None) -> dict:
    """发一个请求，返回 {"code", "message", "data"}。错误信息里不带 URL（登录 URL 里有密码）。"""
    url = API_BASE + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    data = json.dumps(body, ensure_ascii=False).encode("utf-8") if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers=headers(token))
    log(method, path, json.dumps(body, ensure_ascii=False) if body is not None else "")
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            raw = resp.read()
    except urllib.error.HTTPError as e:
        if e.code == 401:
            raise SessionTaken("HTTP 401") from None
        if e.code == 429:
            raise Fail("请求太频繁，云端要求稍后再试。") from None
        raise Fail(f"{path} 返回 HTTP {e.code}") from None
    except urllib.error.URLError as e:
        reason = e.reason
        if isinstance(reason, ssl.SSLCertVerificationError) or "CERTIFICATE_VERIFY_FAILED" in str(reason):
            raise Fail(
                "HTTPS 证书校验失败。如果你的 python3 是从 python.org 装的，"
                "请在“应用程序/Python 3.x”文件夹里双击运行 “Install Certificates.command” 后再试。"
            ) from None
        raise Fail(f"连不上约克云端（{type(reason).__name__}: {reason}）。检查一下网络。") from None
    except (socket.timeout, TimeoutError):
        raise Fail("请求约克云端超时，稍后再试。") from None
    except OSError as e:
        raise Fail(f"网络错误：{type(e).__name__}") from None
    try:
        env = json.loads(raw.decode("utf-8"))
    except ValueError:
        raise Fail(f"{path} 返回的不是 JSON") from None
    if not isinstance(env, dict) or "code" not in env:
        raise Fail(f"{path} 返回格式不认识")
    env["code"] = str(env["code"])
    log("  ->", env["code"], env.get("message"))
    if env["code"] == "401":
        raise SessionTaken("code 401")
    if env["code"] == "300":
        raise Fail("云端要求升级 App 版本（协议里的版本号过旧），需要更新脚本里的 APP_VERSION。")
    return env


# ---------------------------------------------------------------- 账号

class Client:
    def __init__(self, cfg: dict):
        self.cfg = cfg
        if not cfg.get("client_id"):
            # 登录时要带一个推送 id（不能为空），用自己的随机 id，免得抢走手机的推送
            cfg["client_id"] = secrets.token_hex(10)[:19]

    # -- 登录
    def _accept(self, env: dict, path: str) -> None:
        if env["code"] != "200":
            raise Fail(f"登录失败：{env.get('message') or 'code ' + env['code']}")
        user = (env.get("data") or {}).get("user") if isinstance(env.get("data"), dict) else None
        if not isinstance(user, dict) or not user.get("token"):
            raise Fail("登录返回里没有 token，协议可能变了。")
        self.cfg["token"] = user["token"]
        self.cfg["user_id"] = user.get("userId")
        self.cfg["login_version"] = int(user.get("version") or 0)
        if user.get("refreshToken"):
            self.cfg["refresh_token"] = user["refreshToken"]
        save_config(self.cfg)

    def login_password(self, phone: str, password: str) -> None:
        self.cfg["phone"] = phone
        env = envelope("GET", "/login", params={
            "phoneNo": phone,
            "password": password,
            "jgRegId": self.cfg["client_id"],
            "version": self.cfg.get("login_version", 0),
        })
        self._accept(env, "/login")

    def request_sms(self, phone: str) -> None:
        env = envelope("POST", "/smsLogin/getVerifyCode", body={"phoneNo": phone})
        if env["code"] != "200":
            raise Fail(f"发送验证码失败：{env.get('message') or env['code']}")

    def login_sms(self, phone: str, code: str) -> None:
        self.cfg["phone"] = phone
        env = envelope("GET", "/smsLogin", params={
            "phoneNo": phone, "version": 0, "verifyCode": code,
            "refreshToken": "", "jgRegId": self.cfg["client_id"],
        })
        self._accept(env, "/smsLogin")

    def relogin(self) -> bool:
        """会话失效时自动重新登录（保存了密码，或有短信登录的 refreshToken）。"""
        phone = self.cfg.get("phone")
        if not phone:
            return False
        if self.cfg.get("password"):
            self.login_password(phone, self.cfg["password"])
            return True
        if self.cfg.get("refresh_token"):
            env = envelope("GET", "/smsLogin", params={
                "phoneNo": phone, "version": self.cfg.get("login_version", 0),
                "refreshToken": self.cfg["refresh_token"], "jgRegId": self.cfg["client_id"],
            })
            self._accept(env, "/smsLogin")
            return True
        return False

    # -- 带登录态的请求
    def call(self, method: str, path: str, body=None, *, want_envelope=False):
        if not self.cfg.get("token"):
            raise Fail("还没登录，先运行：python3 tools/york_ac.py login")
        for attempt in (1, 2):
            try:
                env = envelope(method, path, body=body, token=self.cfg["token"])
                if env["code"] == "403" and attempt == 1 and self.relogin():
                    continue
                break
            except SessionTaken:
                if attempt == 1 and self.relogin():
                    print("（登录已失效，已自动重新登录）", file=sys.stderr)
                    continue
                raise Fail(
                    "登录已失效：这个账号大概在手机 App 上又登录了（同一账号只能在一处登录）。\n"
                    "重新运行 python3 tools/york_ac.py login；建议给脚本单独用一个账号。"
                ) from None
        if want_envelope:
            return env
        if env["code"] != "200":
            raise Fail(f"{path} 失败：{env.get('message') or 'code ' + env['code']}")
        return env.get("data")

    # -- 设备
    def controllers(self) -> list[dict]:
        data = self.call("GET", "/api/apphome/homes/homeList/deviceList")
        homes = (data or {}).get("allHomeDeviceList")
        if not isinstance(homes, list):
            raise Fail("设备列表格式不认识，协议可能变了。")
        result = []
        for home in homes:
            if not isinstance(home, dict):
                continue
            for x in home.get("xkqList") or []:
                if isinstance(x, dict) and x.get("xkqCode"):
                    result.append({**x, "homeId": home.get("homeId"), "homeName": home.get("homeName"),
                                   "_other": len(home.get("deviceList") or []) + len(home.get("boxList") or [])})
            if not home.get("xkqList"):
                others = len(home.get("deviceList") or []) + len(home.get("boxList") or [])
                if others:
                    result.append({"homeId": home.get("homeId"), "homeName": home.get("homeName"),
                                   "_only_other": others})
        return result

    def detail_constants(self, dev: dict) -> dict:
        try:
            data = self.call("GET", f"/api/appdevice/homes/{dev['homeId']}/xkqs/{dev['xkqCode']}")
        except Fail as e:
            log("detail failed:", e)
            return {}
        return parse_constants((data or {}).get("constantJson")) if isinstance(data, dict) else {}

    def status(self, dev: dict, cursor: int = 0) -> dict | None:
        data = self.call("POST", f"/api/appstatus/homes/{dev['homeId']}/status", {
            "homeId": dev["homeId"],
            "boxList": [], "iuIdList": [], "iuIdListGjy": [],
            "xkqListGjy": [{"xkqCode": dev["xkqCode"], "timestamp": cursor}],
        })
        for s in (data or {}).get("xkqStatusListGjy") or []:
            if isinstance(s, dict) and s.get("xkqCode") == dev["xkqCode"]:
                return s
        return None

    def online(self, dev: dict) -> bool | None:
        try:
            data = self.call("POST", "/api/appcontrol/cmds/xkqOnlineStatus", {
                "xkqCtrlList": [{"xkqCode": dev["xkqCode"], "deviceType": dev.get("type") or "C"}]})
        except Fail as e:
            log("online failed:", e)
            return None
        for d in data or []:
            if isinstance(d, dict) and d.get("xkqCode") == dev["xkqCode"]:
                return is_on(d.get("online"))
        return None

    def control(self, dev: dict, ctrl_json: dict) -> None:
        env = self.call("POST", "/api/appcontrol/cmds/multiIuOuCtrl", {
            "homeId": dev["homeId"],
            "ctrlType": CTRL_TYPE_SINGLE,
            "ctrlList": [],
            "xkqCtrlList": [{
                "xkqCode": dev["xkqCode"],
                "deviceType": str(dev.get("type") or "C"),
                "xkqType": str(dev.get("xkqType") or "9"),
                "ctrlJson": ctrl_json,
            }],
        }, want_envelope=True)
        if env["code"] != "200":
            raise Fail(f"云端拒绝了指令：{env.get('message') or 'code ' + env['code']}")


# ---------------------------------------------------------------- 状态解读

def cursor_of(report: dict) -> int:
    for key in ("roundTime", "timestamp"):
        v = num(report.get(key))
        if v and v > 0:
            return int(v)
    return 0


def mode_list(dev: dict):
    if str(dev.get("xkqType")) == "8":
        return [m for m in MODES if m[0] not in STANDARD_EXCLUDED_MODES]
    return MODES


def current_mode(view: dict, dev: dict):
    return next((m for m in mode_list(dev) if is_on(view.get(m[2]))), None)


def supported_modes(view: dict, dev: dict):
    return [m for m in mode_list(dev) if is_on(view.get(m[3]))]


def current_fan(view: dict):
    return next((f for f in FANS if is_on(view.get(f[2]))), None)


def supported_fans(view: dict):
    return [f for f in FANS if is_on(view.get(f[3]))]


def setpoint(view: dict):
    t = num(view.get(KEY_SET_TEMP))
    if t is None or not 5 <= t <= 40:
        return None
    return t + (0.5 if is_on(view.get(KEY_SET_TEMP_HALF)) else 0)


def room_temp(view: dict):
    t = num(view.get("indoor_temperature"))
    if t is None:
        return None
    t = int(t)
    if t > 128:
        t -= 256
    return t if -40 <= t <= 60 else None


def temp_limits(view: dict, mode_id: str | None):
    if mode_id == "auto":
        return 16.0, 32.0
    heat = mode_id in HEAT_RANGE_MODES
    if mode_id is not None and not heat and mode_id not in COOL_RANGE_MODES:
        return 1.0, 99.0
    lo_k, hi_k = ("heat_down_value", "heat_up_value") if heat else ("cold_down_value", "cold_up_value")
    lo, hi = num(view.get(lo_k)), num(view.get(hi_k))
    if lo is None or hi is None or not 5 <= lo < hi <= 40:
        return (16.0, 32.0) if heat else (19.0, 30.0)
    return lo, hi


def alarms(view: dict) -> list[str]:
    out = []
    for n in range(1, 17):
        code = num(view.get(f"iu{n}_alarm_code"))
        if not code:
            continue
        if 255 in (num(view.get(f"iu{n}_system_no")), num(view.get(f"iu{n}_addr_no"))):
            continue
        out.append(f"{int(code):02X}")
    return out


def fmt_t(t) -> str:
    return "—" if t is None else (f"{t:.1f}".rstrip("0").rstrip(".") + "°C")


def describe(view: dict, dev: dict, online=None) -> str:
    name = dev.get("xkqName") or dev.get("xkqCode")
    mode = current_mode(view, dev)
    fan = current_fan(view)
    lines = [f"【{name}】" + ("" if online is None else ("  在线" if online else "  ⚠ 离线"))]
    lines.append(f"  电源：{'开' if is_on(view.get(KEY_POWER)) else '关'}")
    lines.append(f"  模式：{mode[1] if mode else '—'}")
    if mode and mode[0] in MODES_WITHOUT_TEMP:
        lines.append("  设定温度：（此模式不设温度）")
    else:
        lo, hi = temp_limits(view, mode[0] if mode else None)
        lines.append(f"  设定温度：{fmt_t(setpoint(view))}   （可调 {fmt_t(lo)}~{fmt_t(hi)}）")
    lines.append(f"  室内温度：{fmt_t(room_temp(view))}")
    lines.append(f"  风速：{fan[1] if fan else '—'}")
    sm, sf = supported_modes(view, dev), supported_fans(view)
    lines.append(f"  支持模式：{' '.join(f'{m[1]}({m[0]})' for m in sm) or '（未上报）'}")
    lines.append(f"  支持风速：{' '.join(f'{f[1]}({f[0]})' for f in sf) or '（未上报）'}")
    locks = [n for k, n in (("run_model_fixed", "模式"), ("set_temp_fixed", "温度"), ("B9", "风速"))
             if is_on(view.get(k))]
    if locks:
        lines.append(f"  面板锁定：{'、'.join(locks)}")
    al = alarms(view)
    if al:
        lines.append(f"  ⚠ 故障代码：{', '.join(al)}")
    if is_on(view.get("otaFlg")):
        lines.append("  ⚠ 线控器正在升级固件")
    return "\n".join(lines)


# ---------------------------------------------------------------- 指令

def resolve(table, aliases, word: str, what: str):
    w = aliases.get(word.lower(), word.lower())
    for row in table:
        if w in (row[0], row[1]) or word == row[1]:
            return row
    raise Fail(f"不认识的{what}：{word}。可选：" + "、".join(f"{r[0]}({r[1]})" for r in table))


def build_command(view: dict, dev: dict, *, power=None, mode=None, temp=None, fan=None) -> dict:
    """生成 ctrlJson：只包含和当前状态不同的字段（和 App 一样）。"""
    cmd: dict = {}
    cur_mode = current_mode(view, dev)
    target_mode = cur_mode
    known_modes = supported_modes(view, dev)

    if power is not None and power != is_on(view.get(KEY_POWER)):
        cmd[KEY_POWER] = "1" if power else "0"

    if mode is not None:
        row = resolve(mode_list(dev), MODE_ALIASES, mode, "模式")
        if known_modes and row not in known_modes:
            raise Fail(f"这台线控器不支持「{row[1]}」模式。")
        if is_on(view.get("run_model_fixed")):
            raise Fail("面板锁定了模式，不能改。")
        target_mode = row
        if row != cur_mode:
            cmd[row[2]] = "1"

    if temp is not None:
        mid = target_mode[0] if target_mode else None
        if mid in MODES_WITHOUT_TEMP:
            raise Fail(f"「{target_mode[1]}」模式不能设温度。")
        if is_on(view.get("set_temp_fixed")):
            raise Fail("面板锁定了温度，不能改。")
        half_ok = str(view.get("is_set_temperature05_avalable")) != "0"
        t = round(temp * 2) / 2 if half_ok else float(round(temp))
        lo, hi = temp_limits(view, mid)
        if not lo <= t <= hi:
            clamped = min(max(t, lo), hi)
            print(f"（{fmt_t(t)} 超出当前模式范围 {fmt_t(lo)}~{fmt_t(hi)}，改为 {fmt_t(clamped)}）")
            t = clamped
        if t != setpoint(view):
            whole = int(t)
            cmd[KEY_SET_TEMP] = whole
            cmd[KEY_SET_TEMP_HALF] = "1" if t != whole else "0"
    elif mode is not None and target_mode != cur_mode and target_mode[0] not in MODES_WITHOUT_TEMP:
        # 切换模式时把设定温度收进新模式的范围（App 也这样做）
        sp = setpoint(view)
        if sp is not None:
            lo, hi = temp_limits(view, target_mode[0])
            t = min(max(sp, lo), hi)
            if t != sp:
                whole = int(t)
                cmd[KEY_SET_TEMP] = whole
                cmd[KEY_SET_TEMP_HALF] = "1" if t != whole else "0"

    if fan is not None:
        row = resolve(FANS, FAN_ALIASES, fan, "风速")
        known = supported_fans(view)
        if known and row not in known:
            raise Fail(f"这台线控器不支持「{row[1]}」风速。")
        if target_mode and target_mode[0] in MODES_WITHOUT_FAN:
            raise Fail("地暖模式不能调风速。")
        if is_on(view.get("B9")):
            raise Fail("面板锁定了风速，不能改。")
        if row != current_fan(view):
            cmd[row[2]] = "1"

    # 开关机或切模式时，App 会顺带关掉“单向人感”
    if (KEY_POWER in cmd or (target_mode != cur_mode)) and is_on(view.get("one_direction_human_sense")) \
            and str(dev.get("xkqType")) != "8":
        cmd["one_direction_human_sense"] = "0"
    return cmd


def same(a, b) -> bool:
    na, nb = num(a), num(b)
    if na is not None and nb is not None:
        return na == nb
    return str(a) == str(b)


def matches(view: dict, cmd: dict) -> bool:
    return all(same(view.get(k), v) for k, v in cmd.items() if k != "one_direction_human_sense")


# ---------------------------------------------------------------- 命令行

def pick_device(client: Client, index: int | None) -> dict:
    cfg = client.cfg
    if index is None and cfg.get("device"):
        return cfg["device"]
    devs = [d for d in client.controllers() if d.get("xkqCode")]
    if not devs:
        raise Fail("这个账号下没有找到 Wi-Fi 线控器。确认面板已经在约克智慧家 App 里绑定到这个账号（或它所在的家庭）。")
    if index is None:
        if len(devs) > 1:
            raise Fail("账号下有多个线控器，先用 devices 查看编号，再运行：python3 tools/york_ac.py use <编号>")
        index = 1
    if not 1 <= index <= len(devs):
        raise Fail(f"编号 {index} 不存在（共 {len(devs)} 个）。")
    d = devs[index - 1]
    dev = {k: d.get(k) for k in ("homeId", "homeName", "xkqCode", "xkqName", "type", "xkqType", "brand")}
    cfg["device"] = dev
    save_config(cfg)
    return dev


def load_view(client: Client, dev: dict, constants: dict | None = None):
    report = client.status(dev, 0)
    if report is None:
        raise Fail("没有拿到这台线控器的状态（可能离线，或者型号不在支持范围内）。")
    if constants is None:
        constants = client.detail_constants(dev)
    view = dict(report)
    view.update({k: v for k, v in constants.items() if v is not None and v != ""})
    return view, report, constants


def cmd_login(args, client: Client):
    phone = input("约克智慧家手机号：").strip()
    if args.sms:
        client.request_sms(phone)
        code = input("短信验证码：").strip()
        client.login_sms(phone, code)
    else:
        pw = getpass.getpass("密码（输入时不显示）：")
        client.login_password(phone, pw)
        keep = input("把密码保存在本机配置里，登录失效时自动重新登录？[y/N] ").strip().lower()
        if keep == "y":
            client.cfg["password"] = pw
        else:
            client.cfg.pop("password", None)
        save_config(client.cfg)
    print(f"✓ 登录成功（配置保存在 {CONFIG_PATH}，权限 600）")
    client.cfg.pop("device", None)
    save_config(client.cfg)
    cmd_devices(args, client)


def cmd_devices(args, client: Client):
    devs = client.controllers()
    if args.raw:
        safe = [{k: v for k, v in d.items() if k in (
            "homeId", "homeName", "xkqCode", "xkqName", "type", "xkqType", "brand", "constantJson")} for d in devs]
        print(json.dumps(safe, ensure_ascii=False, indent=2))
        return
    n = 0
    for d in devs:
        if d.get("_only_other"):
            print(f"  家庭「{d.get('homeName')}」：没有 Wi-Fi 线控器，另有 {d['_only_other']} 个网关/空气盒子类设备（本脚本不支持）")
            continue
        n += 1
        ok = str(d.get("type")) == "C" and str(d.get("xkqType")) in ("8", "9") and str(d.get("brand", "3")) == "3"
        kind = {"9": "彩屏线控器", "8": "普通线控器"}.get(str(d.get("xkqType")), f"xkqType={d.get('xkqType')}")
        print(f"  [{n}] {d.get('xkqName') or '(未命名)'}  — 家庭「{d.get('homeName')}」 {kind}"
              + ("" if ok else f"  ⚠ 型号参数 type={d.get('type')} brand={d.get('brand')}，可能不兼容"))
    if n == 0:
        print("  没有找到 Wi-Fi 线控器。")
    elif n == 1:
        print("只有一个线控器，之后的命令会自动用它。")
    else:
        print("用 python3 tools/york_ac.py use <编号> 选择默认线控器。")


def cmd_use(args, client: Client):
    dev = pick_device(client, args.index)
    print(f"✓ 默认线控器：{dev.get('xkqName')}")


def cmd_status(args, client: Client):
    dev = pick_device(client, args.device)
    view, report, _ = load_view(client, dev)
    if args.raw:
        print(json.dumps(view, ensure_ascii=False, indent=2, sort_keys=True))
        return
    print(describe(view, dev, client.online(dev)))


def send(args, client: Client, **target):
    dev = pick_device(client, args.device)
    view, report, constants = load_view(client, dev)
    if is_on(view.get("otaFlg")):
        raise Fail("线控器正在升级固件，暂时不能控制。")
    if num(view.get("self_clean")) == 2:
        raise Fail("系统冷却中（自清洁刚结束），暂时不能控制。")
    cmd = build_command(view, dev, **target)
    if not cmd:
        print("状态已经是这样了，不用发送。")
        print(describe(view, dev))
        return
    log("ctrlJson =", json.dumps(cmd, ensure_ascii=False))
    t0 = time.time()
    client.control(dev, cmd)
    print(f"✓ 云端已接受指令（{(time.time() - t0) * 1000:.0f} ms），等面板确认…")
    # 像 App 一样用上一次上报的 roundTime 做增量查询，等线控器上报新状态
    cursor = cursor_of(report)
    latest = dict(view)
    deadline = time.time() + 15
    while time.time() < deadline:
        time.sleep(1.5)
        new = client.status(dev, cursor)
        if new:
            cursor = cursor_of(new) or cursor
            latest.update(new)
            latest.update({k: v for k, v in constants.items() if v is not None and v != ""})
            if matches(latest, cmd):
                print(f"✓ 面板已确认（共 {time.time() - t0:.1f} 秒）")
                print(describe(latest, dev))
                return
    print("⚠ 15 秒内没等到面板上报新状态。指令可能还在路上，稍后运行 status 看看。")
    print(describe(latest, dev))


def cmd_watch(args, client: Client):
    dev = pick_device(client, args.device)
    view, report, constants = load_view(client, dev)
    print(describe(view, dev, client.online(dev)))
    print("— 正在监听面板上报（在面板上按一下试试），Ctrl+C 退出 —")
    cursor = cursor_of(report)
    last = describe(view, dev)
    try:
        while True:
            time.sleep(2)
            new = client.status(dev, cursor)
            if not new:
                continue
            cursor = cursor_of(new) or cursor
            view.update(new)
            view.update({k: v for k, v in constants.items() if v is not None and v != ""})
            text = describe(view, dev)
            if text != last:
                print(time.strftime("%H:%M:%S"), "有变化：")
                print(text)
                last = text
    except KeyboardInterrupt:
        print()


def main(argv=None):
    global VERBOSE
    p = argparse.ArgumentParser(prog="york_ac.py", description="约克智慧家 Wi-Fi 线控器命令行控制")
    p.add_argument("-v", "--verbose", action="store_true", help="打印请求和指令内容")
    p.add_argument("-d", "--device", type=int, help="线控器编号（见 devices）")
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("login", help="登录")
    s.add_argument("--sms", action="store_true", help="用短信验证码登录")
    s.add_argument("--raw", action="store_true", help=argparse.SUPPRESS)
    s = sub.add_parser("devices", help="列出线控器")
    s.add_argument("--raw", action="store_true", help="输出原始 JSON（排查用）")
    s = sub.add_parser("use", help="选择默认线控器")
    s.add_argument("index", type=int)
    s = sub.add_parser("status", help="查看状态")
    s.add_argument("--raw", action="store_true", help="输出全部原始字段（排查用）")
    sub.add_parser("on", help="开机")
    sub.add_parser("off", help="关机")
    s = sub.add_parser("temp", help="设定温度")
    s.add_argument("value", type=float)
    s = sub.add_parser("mode", help="切换模式（会同时开机）")
    s.add_argument("value")
    s = sub.add_parser("fan", help="风速")
    s.add_argument("value")
    s = sub.add_parser("set", help="一次改多项")
    g = s.add_mutually_exclusive_group()
    g.add_argument("--on", dest="power", action="store_const", const=True)
    g.add_argument("--off", dest="power", action="store_const", const=False)
    s.add_argument("--mode")
    s.add_argument("--temp", type=float)
    s.add_argument("--fan")
    sub.add_parser("watch", help="持续监听状态")

    args = p.parse_args(argv)
    VERBOSE = args.verbose
    client = Client(load_config())
    try:
        if args.cmd == "login":
            cmd_login(args, client)
        elif args.cmd == "devices":
            cmd_devices(args, client)
        elif args.cmd == "use":
            cmd_use(args, client)
        elif args.cmd == "status":
            cmd_status(args, client)
        elif args.cmd == "on":
            send(args, client, power=True)
        elif args.cmd == "off":
            send(args, client, power=False)
        elif args.cmd == "temp":
            send(args, client, temp=args.value)
        elif args.cmd == "mode":
            send(args, client, power=True, mode=args.value)
        elif args.cmd == "fan":
            send(args, client, fan=args.value)
        elif args.cmd == "set":
            if args.power is None and not (args.mode or args.temp is not None or args.fan):
                raise Fail("set 至少要带一个参数，例如：set --on --temp 26")
            send(args, client, power=args.power, mode=args.mode, temp=args.temp, fan=args.fan)
        elif args.cmd == "watch":
            cmd_watch(args, client)
    except Fail as e:
        print(f"✗ {e}", file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        return 130
    return 0


if __name__ == "__main__":
    sys.exit(main())
