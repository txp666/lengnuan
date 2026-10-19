import Foundation
import SwiftUI

// 线控器的状态字段和指令规则，照着约克智慧家 App 的控制页实现。

struct ModeDef: Identifiable, Hashable {
    let id: String
    let name: String
    let key: String       // 控制键：发送 {key: "1"} 选中这个模式
    let support: String   // 能力键："1" 表示支持
    let symbol: String
}

struct FanDef: Identifiable, Hashable {
    let id: String
    let name: String
    let key: String
    let support: String
}

let allModes: [ModeDef] = [
    ModeDef(id: "fresh_air_eco", name: "节能新风", key: "wire_controller_saveene_freshair", support: "saveene_freshair", symbol: "leaf"),
    ModeDef(id: "cool", name: "制冷", key: "wire_controller_makecold", support: "wire_controller_makecold_fix", symbol: "snowflake"),
    ModeDef(id: "heat", name: "制热", key: "wire_controller_heating", support: "wire_controller_heating_fix", symbol: "sun.max"),
    ModeDef(id: "fan", name: "送风", key: "wire_controller_makewind", support: "wire_controller_makewind_fix", symbol: "wind"),
    ModeDef(id: "dry", name: "除湿", key: "wire_controller_rmwet", support: "wire_controller_rmwet_fix", symbol: "drop"),
    ModeDef(id: "auto", name: "自动", key: "wire_controller_auto", support: "wire_controller_auto_fix", symbol: "a.circle"),
    ModeDef(id: "dry_comfort", name: "干爽除湿", key: "wire_controller_dry_comfortable_rmwet", support: "is_dehumidification2_avalable", symbol: "drop"),
    ModeDef(id: "dry_strong", name: "强力除湿", key: "wire_controller_strong_rmwet", support: "is_dehumidification3_avalable", symbol: "drop.fill"),
    ModeDef(id: "dry_auto", name: "自动除湿", key: "wire_controller_auto_rmwet", support: "wire_controller_auto_rmwet_fix", symbol: "drop"),
    ModeDef(id: "floor_heat", name: "地暖", key: "wire_controller_floor_heat", support: "is_floor_heating_avalable", symbol: "flame"),
    ModeDef(id: "dry_floor_heat", name: "除湿+地暖", key: "wire_controller_rmwet_floor_heating", support: "controllerFloorRmwetFix", symbol: "flame"),
    ModeDef(id: "fan_floor_heat", name: "送风+地暖", key: "wire_controller_air_supply_floor_heating", support: "air_supply_floor_heating", symbol: "flame"),
    ModeDef(id: "heat_floor_heat", name: "制热+地暖", key: "wire_controller_heat_floor_heating", support: "controllerFloorHeatFix", symbol: "flame"),
    ModeDef(id: "purify", name: "净化", key: "wire_controller_purification", support: "is_purification_available", symbol: "sparkles"),
    ModeDef(id: "heat_supply", name: "供热", key: "wire_controller_heating_mode", support: "is_heating_mode_available", symbol: "flame"),
]
let basicModeIds = ["cool", "heat", "fan", "dry", "auto"]

let allFans: [FanDef] = [
    FanDef(id: "silent", name: "微风", key: "wire_controller_wind_light", support: "wire_controller_wind_silent"),
    FanDef(id: "super_low", name: "超低", key: "wire_controller_wind_superlow", support: "wire_controller_wind_superlow_fix"),
    FanDef(id: "low", name: "低", key: "wire_controller_wind_low", support: "wire_controller_wind_low_fix"),
    FanDef(id: "medium", name: "中", key: "wire_controller_wind_mid", support: "wire_controller_wind_mid_fix"),
    FanDef(id: "high", name: "高", key: "wire_controller_wind_high", support: "wire_controller_wind_high_fix"),
    FanDef(id: "super_high", name: "超高", key: "wire_controller_wind_superhigh", support: "wire_controller_wind_superhign_fix"),
    FanDef(id: "auto", name: "自动", key: "wire_controller_wind_auto", support: "wire_controller_wind_auto_fix"),
]
let basicFanIds = ["low", "medium", "high", "auto"]

private let coolRangeModes: Set<String> = ["cool", "fan", "dry", "dry_comfort", "dry_strong", "dry_auto"]
private let heatRangeModes: Set<String> = ["heat", "floor_heat", "dry_floor_heat", "fan_floor_heat",
                                           "heat_floor_heat", "heat_supply", "purify"]
private let modesWithoutTemp: Set<String> = ["fresh_air_eco", "dry_auto", "dry_floor_heat"]
private let modesWithoutFan: Set<String> = ["floor_heat"]

let keyPower = "if_run"
let keySetTemp = "set_temp"
let keySetTempHalf = "set_temperature_add05"

struct Refused: LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}

func fmtTemp(_ t: Double) -> String {
    t == t.rounded() ? String(Int(t)) : String(format: "%.1f", t)
}

/// 线控器状态 = 面板上报的字段 + 详情接口里的常量（能力位/锁定位/温度范围）
struct ACState {
    var values: JSON = [:]
    var xkqType: String = "9"

    var modes: [ModeDef] {
        xkqType == "8" ? allModes.filter { $0.id != "fresh_air_eco" && $0.id != "heat_supply" } : allModes
    }
    var isEmpty: Bool { values.isEmpty }
    var power: Bool { isOn(values[keyPower]) }
    var mode: ModeDef? { modes.first { isOn(values[$0.key]) } }
    var supportedModes: [ModeDef] { modes.filter { isOn(values[$0.support]) } }
    /// 界面上显示的模式：上报了能力就按能力，没上报就显示五个基本模式
    var shownModes: [ModeDef] {
        let s = supportedModes
        return s.isEmpty ? modes.filter { basicModeIds.contains($0.id) } : s
    }
    var fan: FanDef? { allFans.first { isOn(values[$0.key]) } }
    var supportedFans: [FanDef] { allFans.filter { isOn(values[$0.support]) } }
    var shownFans: [FanDef] {
        let s = supportedFans
        return s.isEmpty ? allFans.filter { basicFanIds.contains($0.id) } : s
    }

    var setpoint: Double? {
        guard let t = num(values[keySetTemp]), (5...40).contains(t) else { return nil }
        return t + (isOn(values[keySetTempHalf]) ? 0.5 : 0)
    }
    var roomTemp: Int? {
        guard let v = num(values["indoor_temperature"]) else { return nil }
        var t = Int(v)
        if t > 128 { t -= 256 }
        return (-40...60).contains(t) ? t : nil
    }
    var halfStep: Bool { str(values["is_set_temperature05_avalable"]) != "0" }
    var hasTemp: Bool { !(mode.map { modesWithoutTemp.contains($0.id) } ?? false) }
    var hasFan: Bool { !(mode.map { modesWithoutFan.contains($0.id) } ?? false) }
    var lockMode: Bool { isOn(values["run_model_fixed"]) }
    var lockTemp: Bool { isOn(values["set_temp_fixed"]) }
    var lockFan: Bool { isOn(values["B9"]) }
    var ota: Bool { isOn(values["otaFlg"]) }
    var coolingDown: Bool { num(values["self_clean"]) == 2 }

    var cursor: Int {
        for key in ["roundTime", "timestamp"] {
            if let v = num(values[key]), v > 0 { return Int(v) }
        }
        return 0
    }

    var alarms: [String] {
        var out: [String] = []
        for n in 1...16 {
            guard let code = num(values["iu\(n)_alarm_code"]), code != 0 else { continue }
            let sys = num(values["iu\(n)_system_no"]), addr = num(values["iu\(n)_addr_no"])
            if sys == 255 || addr == 255 { continue }
            out.append(String(format: "%02X", Int(code)))
        }
        return out
    }

    func limits(for modeId: String?) -> (Double, Double) {
        if modeId == "auto" { return (16, 32) }
        let heat = modeId.map { heatRangeModes.contains($0) } ?? false
        if let m = modeId, !heat, !coolRangeModes.contains(m) { return (1, 99) }
        let lo = num(values[heat ? "heat_down_value" : "cold_down_value"])
        let hi = num(values[heat ? "heat_up_value" : "cold_up_value"])
        if let lo = lo, let hi = hi, 5 <= lo, lo < hi, hi <= 40 { return (lo, hi) }
        return heat ? (16, 32) : (19, 30)
    }

    mutating func overlay(_ constants: JSON) {
        for (k, v) in constants where !(v is NSNull) && !str(v).isEmpty {
            values[k] = v
        }
    }

    // MARK: - 指令

    private static func encodeTemp(_ t: Double) -> JSON {
        let whole = t.rounded(.down)
        return [keySetTemp: Int(whole), keySetTempHalf: t != whole ? "1" : "0"]
    }

    /// 生成 ctrlJson，规则和约克智慧家的控制页一样：
    /// 只发和当前状态不同的字段；调温/调风速/切模式/关机会顺带关掉相应的附加功能；
    /// 附加功能有互斥关系，任何一项变化时把所有附加功能的开关一起发出。
    /// force = true：不和本地状态比较，指定的开关/模式/温度/风速都发送（Siri/小组件用缓存状态时，缓存可能过时）
    func command(power: Bool? = nil, mode modeId: String? = nil, temp: Double? = nil,
                 fan fanId: String? = nil, funcs: [String: Bool] = [:], force: Bool = false) throws -> JSON {
        // 停止正在进行的自清洁 / 高温杀菌：和 App 遮罩上的“停止”一样
        for id in ["clean", "sterilize"] where funcs[id] == false {
            if let f = allFuncs.first(where: { $0.id == id }), isOn(values[f.key]) {
                return [f.key: 0, keyPower: "0"]
            }
        }
        let rules = FuncRules.for(xkqType)
        let offered = offeredFuncs
        let preOn = self.power, preMode = mode, preTemp = setpoint, preFan = fan
        let preFuncs = activeFuncIds
        var on = preOn, target = preMode, t = preTemp, f = preFan, fs = preFuncs

        if let p = power, p != on {
            on = p
            if !p { fs.formIntersection(rules.keptOnPowerOff) }
        }

        if let id = modeId {
            guard let m = modes.first(where: { $0.id == id }) else { throw Refused("未知模式") }
            let known = supportedModes
            if !known.isEmpty && !known.contains(m) { throw Refused("这台线控器不支持「\(m.name)」模式") }
            if lockMode { throw Refused("面板锁定了模式，不能修改") }
            if m != target {
                target = m
                // 切换模式时把设定温度收进新模式的范围；附加功能只保留“健康”
                if let cur = t, !modesWithoutTemp.contains(m.id) {
                    let (lo, hi) = limits(for: m.id)
                    t = min(max(cur, lo), hi)
                }
                fs = fs.contains("health") && m.id != "floor_heat" ? ["health"] : []
            }
        }

        if let t0 = temp {
            if let tm = target, modesWithoutTemp.contains(tm.id) { throw Refused("「\(tm.name)」模式不能设温度") }
            if lockTemp { throw Refused("面板锁定了温度，不能修改") }
            var nt = halfStep ? (t0 * 2).rounded() / 2 : t0.rounded()
            let (lo, hi) = limits(for: target?.id)
            nt = min(max(nt, lo), hi)
            if nt != t {
                t = nt
                fs.subtract(rules.cancelOnTemp)
            }
        }

        if let id = fanId {
            guard let fd = allFans.first(where: { $0.id == id }) else { throw Refused("未知风速") }
            let known = supportedFans
            if !known.isEmpty && !known.contains(fd) { throw Refused("这台线控器不支持「\(fd.name)」风速") }
            if let tm = target, modesWithoutFan.contains(tm.id) { throw Refused("地暖模式不能调风速") }
            if lockFan { throw Refused("面板锁定了风速，不能修改") }
            if fd != f {
                f = fd
                fs.subtract(rules.cancelOnFan)
            }
        }

        for (id, wantOn) in funcs.sorted(by: { $0.key < $1.key }) {
            guard offered.contains(where: { $0.id == id }) else {
                throw Refused("这台线控器没有「\(allFuncs.first { $0.id == id }?.name ?? id)」功能")
            }
            if wantOn == fs.contains(id) { continue }
            if let why = funcBlockedReason(id, on: on, mode: target?.id) { throw Refused(why) }
            if wantOn {
                fs.subtract(rules.exclusions[id] ?? [])
                fs.insert(id)
            } else {
                fs.remove(id)
            }
            // 和 App 一样的联动
            if fs.contains("sleep") {
                let fans = supportedFans
                let want = [3: "low", 4: "low", 6: "silent", 7: "silent"][fans.count]
                if let w = fans.first(where: { $0.id == want }) { f = w }
            }
            if fs.contains("clean") || fs.contains("sterilize") { on = true }
            if fs.contains("leave") {
                let hd = num(values["heat_down_value"])
                t = (hd ?? 0) > 19 ? hd : 19
            }
        }

        var cmd: JSON = [:]
        if on != preOn || (force && power != nil) { cmd[keyPower] = on ? "1" : "0" }
        if let m = target, m != preMode || (force && modeId != nil) { cmd[m.key] = "1" }
        if let nt = t, nt != preTemp || (force && temp != nil) { cmd.merge(Self.encodeTemp(nt)) { $1 } }
        if let nf = f, nf != preFan || (force && fanId != nil) { cmd[nf.key] = "1" }
        if fs != preFuncs {
            for fd in offered {
                let active = fs.contains(fd.id)
                if fd.isInt {
                    // 自清洁、高温杀菌发数字；普通线控器关高温杀菌发字符串 "0"
                    if active {
                        cmd[fd.key] = 1
                    } else if fd.id == "sterilize" && rules.sterilizeOffIsString {
                        cmd[fd.key] = "0"
                    } else {
                        cmd[fd.key] = 0
                    }
                } else {
                    cmd[fd.key] = active ? "1" : "0"
                }
            }
        }

        // 开关机或切模式时，App 会顺带关掉“单向人感”
        if (on != preOn || target != preMode), isOn(values["one_direction_human_sense"]), xkqType != "8" {
            cmd["one_direction_human_sense"] = "0"
        }
        return cmd
    }

    /// 乐观更新：指令发出后先按指令改本地状态
    mutating func apply(_ cmd: JSON) {
        for (k, v) in cmd {
            if allModes.contains(where: { $0.key == k }) {
                for m in allModes where values[m.key] != nil { values[m.key] = "0" }
            }
            if allFans.contains(where: { $0.key == k }) {
                for f in allFans where values[f.key] != nil { values[f.key] = "0" }
            }
            values[k] = v
        }
    }

    func matches(_ cmd: JSON) -> Bool {
        cmd.allSatisfy { $0.key == "one_direction_human_sense" || same(values[$0.key], $0.value) }
    }

    /// 指令待确认期间，面板旧状态的上报不能覆盖这些字段
    static func protectedKeys(for cmd: JSON) -> Set<String> {
        var keys = Set<String>()
        for k in cmd.keys {
            if allModes.contains(where: { $0.key == k }) { keys.formUnion(allModes.map(\.key)) }
            else if allFans.contains(where: { $0.key == k }) { keys.formUnion(allFans.map(\.key)) }
            else if k == keySetTemp || k == keySetTempHalf { keys.formUnion([keySetTemp, keySetTempHalf]) }
            else { keys.insert(k) }
        }
        return keys
    }
}

extension ModeDef {
    var color: Color { gradient[1] }

    /// 卡片 / 小组件背景用的两色渐变
    var gradient: [Color] {
        switch id {
        case "cool": return [Color(red: 0.31, green: 0.67, blue: 1.00), Color(red: 0.16, green: 0.42, blue: 0.93)]
        case "heat", "heat_supply", "floor_heat", "heat_floor_heat", "fan_floor_heat", "dry_floor_heat":
            return [Color(red: 1.00, green: 0.62, blue: 0.27), Color(red: 0.94, green: 0.36, blue: 0.20)]
        case "fan", "fresh_air_eco": return [Color(red: 0.24, green: 0.82, blue: 0.72), Color(red: 0.07, green: 0.60, blue: 0.53)]
        case "dry", "dry_comfort", "dry_strong", "dry_auto":
            return [Color(red: 0.35, green: 0.80, blue: 0.95), Color(red: 0.13, green: 0.56, blue: 0.80)]
        case "purify": return [Color(red: 0.45, green: 0.85, blue: 0.45), Color(red: 0.20, green: 0.65, blue: 0.30)]
        default: return [Color(red: 0.63, green: 0.55, blue: 0.98), Color(red: 0.42, green: 0.35, blue: 0.88)]
        }
    }
}

let offGradient: [Color] = [Color(red: 0.45, green: 0.47, blue: 0.52), Color(red: 0.27, green: 0.28, blue: 0.32)]

extension ACState {
    /// 当前状态对应的配色：开机用模式色，关机用灰色
    var gradient: [Color] { power ? (mode?.gradient ?? offGradient) : offGradient }
    var tint: Color { gradient[1] }

    /// 设定温度在可调范围里的位置 0~1（表盘用）
    func fraction(of temp: Double?) -> Double {
        guard let t = temp else { return 0 }
        let (lo, hi) = limits(for: mode?.id)
        guard hi > lo, hi - lo < 50 else { return 0.5 }
        return min(max((t - lo) / (hi - lo), 0), 1)
    }

    /// 演示 / 预览用的样例状态
    static func sample(power: Bool = true, mode: String = "cool", temp: Double = 26) -> ACState {
        var v: JSON = [
            "if_run": power ? "1" : "0", "set_temp": Int(temp), "set_temperature_add05": temp != temp.rounded(.down) ? "1" : "0",
            "indoor_temperature": 25, "wire_controller_wind_auto": "1",
            "cold_down_value": 18, "cold_up_value": 30, "heat_down_value": 16, "heat_up_value": 30,
            "roundTime": 1,
        ]
        for m in allModes { v[m.key] = m.id == mode ? "1" : "0" }
        for id in ["cool", "heat", "fan", "dry"] {
            if let m = allModes.first(where: { $0.id == id }) { v[m.support] = "1" }
        }
        for f in allFans { v[f.support] = "1" }
        for id in ["save", "sleep", "mute", "forest", "clean", "strong", "leave", "sterilize"] {
            if let f = allFuncs.first(where: { $0.id == id }) { v[f.support] = "1"; v[f.key] = f.isInt ? 0 : "0" }
        }
        return ACState(values: v)
    }
}

// MARK: - 简易定时

let keyTimerFlag = "timerSimpleFlg"      // 1：有定时
let keyTimerOnOff = "timerSimpleOnoff"   // 1：到点开机，否则关机
let keyTimerTime = "timerSimpleTime"     // 到点时间（毫秒时间戳）

/// 线控器支持的定时时长（小时）：0.5~10 每半小时一档，11~24 每小时一档
let timerHours: [Double] = Array(stride(from: 0.5, through: 10, by: 0.5)) + (11...24).map { Double($0) }
/// 界面上直接列出来的常用时长
let commonTimerHours: [Double] = [0.5, 1, 1.5, 2, 3, 4, 6, 8, 10, 12]

func timerDurationText(_ hours: Double) -> String {
    if hours < 1 { return "\(Int(hours * 60))分钟" }
    return fmtTemp(hours) + "小时"
}

/// “22:30” / “明天 08:00”
func clockText(_ date: Date, now: Date = Date()) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "zh_CN")
    f.dateFormat = "HH:mm"
    let cal = Calendar.current
    if cal.isDate(date, inSameDayAs: now) { return f.string(from: date) }
    if let tomorrow = cal.date(byAdding: .day, value: 1, to: now), cal.isDate(date, inSameDayAs: tomorrow) {
        return "明天 " + f.string(from: date)
    }
    f.dateFormat = "M月d日 HH:mm"
    return f.string(from: date)
}

/// “还剩 1小时20分” / “还剩 5分钟” / “即将执行”
func remainingText(until end: Date, now: Date = Date()) -> String {
    let mins = Int((end.timeIntervalSince(now) / 60).rounded(.up))
    if mins <= 0 { return "即将执行" }
    if mins < 60 { return "还剩 \(mins)分钟" }
    let h = mins / 60, m = mins % 60
    return m == 0 ? "还剩 \(h)小时" : "还剩 \(h)小时\(m)分"
}

extension ACState {
    var timerFlag: Bool { isOn(values[keyTimerFlag]) }
    var timerTurnsOn: Bool { isOn(values[keyTimerOnOff]) }

    /// 正在等待执行的定时的到点时间；没有定时、或已经过点 10 分钟以上时为 nil
    var timerEnd: Date? {
        guard timerFlag, let ms = num(values[keyTimerTime]) else { return nil }
        let end = Date(timeIntervalSince1970: ms / 1000)
        let now = Date()
        guard end > now.addingTimeInterval(-600), end < now.addingTimeInterval(25 * 3600) else { return nil }
        return end
    }

    /// “22:30 关机”
    var timerText: String? {
        guard let end = timerEnd else { return nil }
        return clockText(end) + (timerTurnsOn ? " 开机" : " 关机")
    }

    /// 设定定时后先在本地记下（云端答复里有到点时间就用它）
    mutating func applyTimer(hours: Double, turnOn: Bool, reply: JSON) {
        let ms = num(reply[keyTimerTime]) ?? (Date().timeIntervalSince1970 + hours * 3600) * 1000
        values[keyTimerFlag] = 1
        values[keyTimerOnOff] = turnOn ? 1 : 0
        values[keyTimerTime] = Int64(ms)
    }

    mutating func applyTimerCancel() {
        values[keyTimerFlag] = 0
    }
}

// MARK: - 附加功能（节能、睡眠、静音、森林风、自清洁、强力、离家、高温杀菌……）

struct FuncDef: Identifiable, Hashable {
    let id: String
    let name: String
    let key: String       // 控制键
    let support: String   // 能力键
    let symbol: String
    var isInt = false     // 自清洁、高温杀菌用数字 1/0
}

/// App 里的顺序；线控器支持哪些按能力键决定
let allFuncs: [FuncDef] = [
    FuncDef(id: "save", name: "节能", key: "energy_conservation", support: "is_energy_conservation_avalable", symbol: "leaf"),
    FuncDef(id: "sleep", name: "睡眠", key: "sleep", support: "is_sleep_avalable", symbol: "moon.zzz"),
    FuncDef(id: "mute", name: "静音", key: "indoor_unit_silent", support: "is_indoor_unit_silent_avalable", symbol: "speaker.slash"),
    FuncDef(id: "health", name: "健康", key: "health", support: "is_health_avalable", symbol: "heart"),
    FuncDef(id: "forest", name: "森林风", key: "forest_wind", support: "is_forest_wind_avalable", symbol: "tree"),
    FuncDef(id: "aux_heat", name: "辅热", key: "auxiliary_heat", support: "is_auxiliary_heat_avalable", symbol: "flame"),
    FuncDef(id: "clean", name: "自清洁", key: "self_clean", support: "is_self_clean_avalable", symbol: "sparkles", isInt: true),
    FuncDef(id: "strong", name: "强力", key: "force_switch", support: "is_force_avalable", symbol: "bolt"),
    FuncDef(id: "no_wind", name: "无风感", key: "no_sense_of_wind", support: "is_nosense_wind_avalable", symbol: "aqi.low"),
    FuncDef(id: "leave", name: "离家", key: "away_home_energy_saving", support: "is_awayhome_saveenergy_avalable", symbol: "figure.walk"),
    FuncDef(id: "sterilize", name: "高温杀菌", key: "hig_temperature_sterilization", support: "hig_temperature_sterilization_fix", symbol: "thermometer.sun", isInt: true),
]

/// 两种线控器页面（彩屏 xkqType 9 / 普通 xkqType 8）的附加功能规则，照搬约克智慧家
struct FuncRules {
    let exclusions: [String: Set<String>]   // 打开某项时会关掉的其他项
    let cancelOnTemp: Set<String>           // 调温度时关掉
    let cancelOnFan: Set<String>            // 调风速时关掉
    let keptOnPowerOff: Set<String>         // 关机时保留
    let sterilizeOffIsString: Bool

    static func `for`(_ xkqType: String) -> FuncRules { xkqType == "8" ? standard : color }

    private static let all: Set<String> = ["save", "mute", "sleep", "health", "aux_heat", "forest",
                                           "no_wind", "leave", "strong", "clean", "sterilize"]

    static let color = FuncRules(
        exclusions: [
            "save": ["mute", "sleep", "aux_heat", "forest", "no_wind", "leave", "strong", "clean", "sterilize"],
            "sleep": ["save", "mute", "forest", "no_wind", "leave", "strong", "clean", "sterilize"],
            "mute": ["save", "sleep", "forest", "no_wind", "leave", "strong", "clean", "sterilize"],
            "health": ["leave", "clean", "sterilize"],
            "aux_heat": ["save", "forest", "no_wind", "leave", "clean", "sterilize"],
            "forest": ["save", "mute", "sleep", "aux_heat", "no_wind", "leave", "strong", "clean", "sterilize"],
            "no_wind": FuncRules.all.subtracting(["health", "no_wind"]),
            "leave": FuncRules.all.subtracting(["leave"]),
            "strong": ["save", "mute", "sleep", "forest", "no_wind", "leave", "clean", "sterilize"],
            "clean": FuncRules.all.subtracting(["clean"]),
            "sterilize": FuncRules.all.subtracting(["sterilize"]),
        ],
        cancelOnTemp: ["save"],
        cancelOnFan: ["save", "mute", "forest", "strong", "no_wind"],
        keptOnPowerOff: [],
        sterilizeOffIsString: false
    )

    static let standard = FuncRules(
        exclusions: [
            "save": ["sleep", "mute", "forest", "aux_heat", "clean", "strong", "no_wind", "sterilize"],
            "sleep": ["save", "mute", "forest", "clean", "strong", "no_wind", "sterilize"],
            "mute": ["save", "sleep", "forest", "clean", "strong", "no_wind", "sterilize"],
            "health": ["clean", "sterilize"],
            "forest": ["save", "sleep", "mute", "aux_heat", "clean", "strong", "no_wind", "sterilize"],
            "aux_heat": ["clean", "no_wind", "save", "forest", "sterilize"],
            "clean": ["save", "sleep", "mute", "health", "forest", "aux_heat", "strong", "no_wind", "sterilize"],
            "strong": ["save", "sleep", "mute", "forest", "clean", "no_wind", "sterilize"],
            "no_wind": ["save", "sleep", "mute", "forest", "aux_heat", "clean", "strong", "sterilize"],
            "sterilize": ["save", "sleep", "mute", "health", "forest", "aux_heat", "strong", "clean", "no_wind"],
            "leave": [],
        ],
        cancelOnTemp: ["save"],
        cancelOnFan: ["save", "mute", "forest", "strong", "no_wind"],
        keptOnPowerOff: ["clean"],
        sterilizeOffIsString: true
    )
}

extension ACState {
    /// 线控器支持的附加功能（彩屏要求能力键为 "1"，普通线控器只要不是 "0"）
    var offeredFuncs: [FuncDef] {
        allFuncs.filter { f in
            let v = values[f.support]
            if xkqType != "8" { return isOn(v) }
            if let n = num(v) { return n != 0 }
            let s = str(v)
            return !s.isEmpty && s != "0"
        }
    }

    var activeFuncIds: Set<String> {
        Set(offeredFuncs.filter { isOn(values[$0.key]) }.map(\.id))
    }

    /// 现在不能切换这个功能的原因（nil = 可以）。规则同 App 的 refreshFuncEnable
    func funcBlockedReason(_ id: String, on: Bool? = nil, mode modeId: String? = nil) -> String? {
        let on = on ?? power
        let m = modeId ?? mode?.id ?? ""
        let color = xkqType != "8"
        var blocked: Set<String> = ["floor_heat", "dry_floor_heat", "heat_floor_heat", "fan_floor_heat"]
        if color { blocked.insert("purify") }
        let name = allFuncs.first { $0.id == id }?.name ?? id
        let needOn = "开机后才能用\(name)"
        let badMode = "当前模式不能用\(name)"
        switch id {
        case "save", "sleep":
            if lockTemp || lockFan { return "面板锁定了温度或风速，不能用\(name)" }
            if !on { return needOn }
            if blocked.contains(m) || m == "fan" || m == "auto" { return badMode }
        case "mute", "no_wind":
            if lockFan { return "面板锁定了风速，不能用\(name)" }
            if !on { return needOn }
            if blocked.contains(m) || m == "auto" { return badMode }
        case "health":
            if !on { return needOn }
            if blocked.contains(m) { return badMode }
        case "forest":
            if !on { return needOn }
            if m != "cool" { return "制冷模式下才能用森林风" }
        case "aux_heat":
            if !on { return needOn }
            if m != "heat" { return "制热模式下才能用辅热" }
        case "strong":
            if !on { return needOn }
            if m != "cool" && m != "heat" { return "制冷或制热时才能用强力" }
        case "leave":
            if !on { return needOn }
            if m != "floor_heat" { return "地暖模式下才能用离家" }
            if !color && lockTemp { return "面板锁定了温度，不能用离家" }
        case "clean":
            if on { return "关机后才能自清洁" }
            if blocked.contains(m) { return badMode }
        case "sterilize":
            if on { return "关机后才能高温杀菌" }
            if blocked.contains(m) || (color && m == "dry_auto") { return badMode }
        default:
            return "不支持\(name)"
        }
        return nil
    }

    /// 运行中的特殊状态（App 首页卡片上的遮罩）
    var runningState: String? {
        if num(values["self_clean"]) == 1 { return "自清洁中" }
        if num(values["hig_temperature_sterilization"]) == 1 { return "高温杀菌中" }
        if num(values["self_clean"]) == 2 { return "系统冷却中" }
        if ota { return "线控器升级中" }
        return nil
    }

    /// 正在运行、可以停止的功能（自清洁 / 高温杀菌）
    var stoppableFunc: String? {
        if num(values["self_clean"]) == 1 { return "clean" }
        if num(values["hig_temperature_sterilization"]) == 1 { return "sterilize" }
        return nil
    }

    // MARK: 滤网

    private static let filterKeys = (1...5).map { "filter_life_tips\($0)" }

    private func filterSlotDue(_ key: String) -> Bool {
        guard let v = num(values[key]) else { return false }
        if xkqType == "8" { return key == "filter_life_tips1" && v == 2 }
        return v == 2 || (v == 3 && key == "filter_life_tips3")
    }

    /// 滤网需要清洗（App 上的“滤网异常”）
    var filterDue: Bool { Self.filterKeys.contains { filterSlotDue($0) } }

    /// 滤网复位后先在本地清掉提醒
    mutating func applyFilterReset() {
        for k in Self.filterKeys where filterSlotDue(k) {
            if values[k] is String { values[k] = "0" } else { values[k] = 0 }
        }
    }
}

let filterResetCommand: JSON = ["screen_mark_reset": "1"]
