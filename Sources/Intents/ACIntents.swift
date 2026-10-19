import AppIntents
import Foundation
import WidgetKit

// Siri / 快捷指令 / 小组件共用的动作（App 和小组件扩展都编译这个文件）

// MARK: - 参数类型

enum ACTempOption: String, AppEnum {
    case t16 = "16"
    case t17 = "17"
    case t18 = "18"
    case t19 = "19"
    case t20 = "20"
    case t21 = "21"
    case t22 = "22"
    case t23 = "23"
    case t24 = "24"
    case t25 = "25"
    case t26 = "26"
    case t27 = "27"
    case t28 = "28"
    case t29 = "29"
    case t30 = "30"

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "温度"
    static let caseDisplayRepresentations: [ACTempOption: DisplayRepresentation] = [
        .t16: DisplayRepresentation(title: "16度", synonyms: ["16", "16°", "16摄氏度", "十六度"]),
        .t17: DisplayRepresentation(title: "17度", synonyms: ["17", "17°", "17摄氏度", "十七度"]),
        .t18: DisplayRepresentation(title: "18度", synonyms: ["18", "18°", "18摄氏度", "十八度"]),
        .t19: DisplayRepresentation(title: "19度", synonyms: ["19", "19°", "19摄氏度", "十九度"]),
        .t20: DisplayRepresentation(title: "20度", synonyms: ["20", "20°", "20摄氏度", "二十度"]),
        .t21: DisplayRepresentation(title: "21度", synonyms: ["21", "21°", "21摄氏度", "二十一度"]),
        .t22: DisplayRepresentation(title: "22度", synonyms: ["22", "22°", "22摄氏度", "二十二度"]),
        .t23: DisplayRepresentation(title: "23度", synonyms: ["23", "23°", "23摄氏度", "二十三度"]),
        .t24: DisplayRepresentation(title: "24度", synonyms: ["24", "24°", "24摄氏度", "二十四度"]),
        .t25: DisplayRepresentation(title: "25度", synonyms: ["25", "25°", "25摄氏度", "二十五度"]),
        .t26: DisplayRepresentation(title: "26度", synonyms: ["26", "26°", "26摄氏度", "二十六度"]),
        .t27: DisplayRepresentation(title: "27度", synonyms: ["27", "27°", "27摄氏度", "二十七度"]),
        .t28: DisplayRepresentation(title: "28度", synonyms: ["28", "28°", "28摄氏度", "二十八度"]),
        .t29: DisplayRepresentation(title: "29度", synonyms: ["29", "29°", "29摄氏度", "二十九度"]),
        .t30: DisplayRepresentation(title: "30度", synonyms: ["30", "30°", "30摄氏度", "三十度"]),
    ]

    var degrees: Double { Double(rawValue) ?? 26 }
}

enum ACModeOption: String, AppEnum {
    case cool, heat, fan, dry, auto

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "模式"
    static let caseDisplayRepresentations: [ACModeOption: DisplayRepresentation] = [
        .cool: DisplayRepresentation(title: "制冷", synonyms: ["冷气", "制冷模式"]),
        .heat: DisplayRepresentation(title: "制热", synonyms: ["暖气", "制热模式", "取暖"]),
        .fan: DisplayRepresentation(title: "送风", synonyms: ["通风", "送风模式"]),
        .dry: DisplayRepresentation(title: "除湿", synonyms: ["抽湿", "除湿模式"]),
        .auto: DisplayRepresentation(title: "自动", synonyms: ["自动模式"]),
    ]
}

enum ACFanOption: String, AppEnum {
    case silent, super_low, low, medium, high, super_high, auto

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "风速"
    static let caseDisplayRepresentations: [ACFanOption: DisplayRepresentation] = [
        .silent: DisplayRepresentation(title: "微风"),
        .super_low: DisplayRepresentation(title: "超低"),
        .low: DisplayRepresentation(title: "低", synonyms: ["低风", "小风"]),
        .medium: DisplayRepresentation(title: "中", synonyms: ["中风", "中速"]),
        .high: DisplayRepresentation(title: "高", synonyms: ["高风", "大风"]),
        .super_high: DisplayRepresentation(title: "超高", synonyms: ["最大"]),
        .auto: DisplayRepresentation(title: "自动", synonyms: ["自动风"]),
    ]
}

enum ACPowerOption: String, AppEnum {
    case on, off

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "开关"
    static let caseDisplayRepresentations: [ACPowerOption: DisplayRepresentation] = [
        .on: DisplayRepresentation(title: "开机", synonyms: ["打开", "开"]),
        .off: DisplayRepresentation(title: "关机", synonyms: ["关闭", "关"]),
    ]
}

enum ACTempDirection: String, AppEnum {
    case up, down

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "方向"
    static let caseDisplayRepresentations: [ACTempDirection: DisplayRepresentation] = [
        .up: DisplayRepresentation(title: "调高", synonyms: ["升高", "提高", "加一度"]),
        .down: DisplayRepresentation(title: "调低", synonyms: ["降低", "减一度"]),
    ]
}

enum ACTimerOption: String, AppEnum {
    case m30 = "0.5", h1 = "1", h1_5 = "1.5", h2 = "2", h3 = "3", h4 = "4", h5 = "5",
         h6 = "6", h7 = "7", h8 = "8", h9 = "9", h10 = "10", h12 = "12"

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "时长"
    static let caseDisplayRepresentations: [ACTimerOption: DisplayRepresentation] = [
        .m30: DisplayRepresentation(title: "半小时", synonyms: ["30分钟", "三十分钟", "半个小时"]),
        .h1: DisplayRepresentation(title: "1小时", synonyms: ["一小时", "一个小时", "1个小时"]),
        .h1_5: DisplayRepresentation(title: "1个半小时", synonyms: ["一个半小时", "1.5小时", "九十分钟"]),
        .h2: DisplayRepresentation(title: "2小时", synonyms: ["两小时", "两个小时", "2个小时", "二小时"]),
        .h3: DisplayRepresentation(title: "3小时", synonyms: ["三小时", "三个小时", "3个小时"]),
        .h4: DisplayRepresentation(title: "4小时", synonyms: ["四小时", "四个小时", "4个小时"]),
        .h5: DisplayRepresentation(title: "5小时", synonyms: ["五小时", "五个小时", "5个小时"]),
        .h6: DisplayRepresentation(title: "6小时", synonyms: ["六小时", "六个小时", "6个小时"]),
        .h7: DisplayRepresentation(title: "7小时", synonyms: ["七小时", "七个小时", "7个小时"]),
        .h8: DisplayRepresentation(title: "8小时", synonyms: ["八小时", "八个小时", "8个小时"]),
        .h9: DisplayRepresentation(title: "9小时", synonyms: ["九小时", "九个小时", "9个小时"]),
        .h10: DisplayRepresentation(title: "10小时", synonyms: ["十小时", "十个小时", "10个小时"]),
        .h12: DisplayRepresentation(title: "12小时", synonyms: ["十二小时", "十二个小时", "12个小时"]),
    ]

    var hours: Double { Double(rawValue) ?? 1 }
}

/// Siri 用：功能和开/关合成一个参数（App 快捷指令的一句话里只能有一个参数）
enum ACFuncAction: String, AppEnum {
    case save_on, save_off
    case sleep_on, sleep_off
    case mute_on, mute_off
    case health_on, health_off
    case forest_on, forest_off
    case aux_heat_on, aux_heat_off
    case clean_on, clean_off
    case strong_on, strong_off
    case no_wind_on, no_wind_off
    case leave_on, leave_off
    case sterilize_on, sterilize_off

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "功能"
    static let caseDisplayRepresentations: [ACFuncAction: DisplayRepresentation] = [
        .save_on: DisplayRepresentation(title: "打开节能", synonyms: ["开节能", "开启节能", "打开节能模式", "打开省电", "开节能模式", "开省电"]),
        .save_off: DisplayRepresentation(title: "关闭节能", synonyms: ["关节能", "关掉节能", "关闭节能模式", "关闭省电", "关节能模式", "关省电"]),
        .sleep_on: DisplayRepresentation(title: "打开睡眠", synonyms: ["开睡眠", "开启睡眠", "打开睡眠模式", "开睡眠模式"]),
        .sleep_off: DisplayRepresentation(title: "关闭睡眠", synonyms: ["关睡眠", "关掉睡眠", "关闭睡眠模式", "关睡眠模式"]),
        .mute_on: DisplayRepresentation(title: "打开静音", synonyms: ["开静音", "开启静音", "打开静音模式", "开静音模式"]),
        .mute_off: DisplayRepresentation(title: "关闭静音", synonyms: ["关静音", "关掉静音", "关闭静音模式", "关静音模式"]),
        .health_on: DisplayRepresentation(title: "打开健康", synonyms: ["开健康", "开启健康"]),
        .health_off: DisplayRepresentation(title: "关闭健康", synonyms: ["关健康", "关掉健康"]),
        .forest_on: DisplayRepresentation(title: "打开森林风", synonyms: ["开森林风", "开启森林风"]),
        .forest_off: DisplayRepresentation(title: "关闭森林风", synonyms: ["关森林风", "关掉森林风"]),
        .aux_heat_on: DisplayRepresentation(title: "打开辅热", synonyms: ["开辅热", "开启辅热", "打开电辅热", "开电辅热"]),
        .aux_heat_off: DisplayRepresentation(title: "关闭辅热", synonyms: ["关辅热", "关掉辅热", "关闭电辅热", "关电辅热"]),
        .clean_on: DisplayRepresentation(title: "打开自清洁", synonyms: ["开自清洁", "开启自清洁", "打开清洁", "开清洁"]),
        .clean_off: DisplayRepresentation(title: "关闭自清洁", synonyms: ["关自清洁", "关掉自清洁", "关闭清洁", "关清洁"]),
        .strong_on: DisplayRepresentation(title: "打开强力", synonyms: ["开强力", "开启强力", "打开强力模式", "打开强劲", "开强力模式", "开强劲"]),
        .strong_off: DisplayRepresentation(title: "关闭强力", synonyms: ["关强力", "关掉强力", "关闭强力模式", "关闭强劲", "关强力模式", "关强劲"]),
        .no_wind_on: DisplayRepresentation(title: "打开无风感", synonyms: ["开无风感", "开启无风感"]),
        .no_wind_off: DisplayRepresentation(title: "关闭无风感", synonyms: ["关无风感", "关掉无风感"]),
        .leave_on: DisplayRepresentation(title: "打开离家", synonyms: ["开离家", "开启离家", "打开离家模式", "开离家模式"]),
        .leave_off: DisplayRepresentation(title: "关闭离家", synonyms: ["关离家", "关掉离家", "关闭离家模式", "关离家模式"]),
        .sterilize_on: DisplayRepresentation(title: "打开高温杀菌", synonyms: ["开高温杀菌", "开启高温杀菌", "打开杀菌", "开杀菌"]),
        .sterilize_off: DisplayRepresentation(title: "关闭高温杀菌", synonyms: ["关高温杀菌", "关掉高温杀菌", "关闭杀菌", "关杀菌"]),
    ]

    var funcId: String { String(rawValue.dropLast(rawValue.hasSuffix("_on") ? 3 : 4)) }
    var turnOn: Bool { rawValue.hasSuffix("_on") }
}

// MARK: - 公共执行

struct ACIntentError: Error, CustomLocalizedStringResourceConvertible {
    let message: String
    var localizedStringResource: LocalizedStringResource { "\(message)" }
}

@MainActor
func runAC(power: Bool? = nil, toggle: Bool = false, mode: String? = nil, temp: Double? = nil,
           tempSteps: Double? = nil, fan: String? = nil, funcs: [String: Bool] = [:]) async throws -> ACState {
    do {
        let s = try await ACService.shared.run(power: power, toggle: toggle, mode: mode, temp: temp,
                                               tempSteps: tempSteps, fan: fan, funcs: funcs)
        WidgetCenter.shared.reloadAllTimelines()
        return s
    } catch {
        throw ACIntentError(message: error.localizedDescription)
    }
}

@MainActor
func runTimerAC(_ op: () async throws -> ACState) async throws -> ACState {
    do {
        let s = try await op()
        WidgetCenter.shared.reloadAllTimelines()
        return s
    } catch {
        throw ACIntentError(message: error.localizedDescription)
    }
}

// MARK: - 动作

struct PowerOnIntent: AppIntent {
    static let title: LocalizedStringResource = "打开空调"
    static let description = IntentDescription("让约克空调开机")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        _ = try await runAC(power: true)
        return .result(dialog: "已开机")
    }
}

struct PowerOffIntent: AppIntent {
    static let title: LocalizedStringResource = "关闭空调"
    static let description = IntentDescription("让约克空调关机")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        _ = try await runAC(power: false)
        return .result(dialog: "已关机")
    }
}

struct TogglePowerIntent: AppIntent {
    static let title: LocalizedStringResource = "开关空调"
    static let description = IntentDescription("开着就关，关着就开")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let s = try await runAC(toggle: true)
        let text = s.power ? "已开机" : "已关机"
        return .result(dialog: "\(text)")
    }
}

struct SetTemperatureIntent: AppIntent {
    static let title: LocalizedStringResource = "设置空调温度"
    static let description = IntentDescription("把设定温度调到指定度数")

    @Parameter(title: "温度")
    var temperature: ACTempOption

    init() {}
    init(temperature: ACTempOption) { self.temperature = temperature }

    static var parameterSummary: some ParameterSummary {
        Summary("把空调温度设为\(\.$temperature)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let s = try await runAC(temp: temperature.degrees)
        let t = fmtTemp(s.setpoint ?? temperature.degrees)
        return .result(dialog: "已调到\(t)度")
    }
}

struct AdjustTemperatureIntent: AppIntent {
    static let title: LocalizedStringResource = "调高或调低空调温度"
    static let description = IntentDescription("温度加一度或减一度")

    @Parameter(title: "方向")
    var direction: ACTempDirection

    init() {}
    init(direction: ACTempDirection) { self.direction = direction }

    static var parameterSummary: some ParameterSummary {
        Summary("空调温度\(\.$direction)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let s = try await runAC(tempSteps: direction == .up ? 1 : -1)
        let t = s.setpoint.map { fmtTemp($0) } ?? ""
        return .result(dialog: "已调到\(t)度")
    }
}

struct SetModeIntent: AppIntent {
    static let title: LocalizedStringResource = "设置空调模式"
    static let description = IntentDescription("切换制冷、制热、送风、除湿、自动（会同时开机）")

    @Parameter(title: "模式")
    var mode: ACModeOption

    init() {}
    init(mode: ACModeOption) { self.mode = mode }

    static var parameterSummary: some ParameterSummary {
        Summary("把空调切换到\(\.$mode)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let s = try await runAC(power: true, mode: mode.rawValue)
        let name = s.mode?.name ?? ""
        return .result(dialog: "已切换到\(name)")
    }
}

struct SetFanIntent: AppIntent {
    static let title: LocalizedStringResource = "设置空调风速"

    @Parameter(title: "风速")
    var fan: ACFanOption

    init() {}
    init(fan: ACFanOption) { self.fan = fan }

    static var parameterSummary: some ParameterSummary {
        Summary("把空调风速设为\(\.$fan)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let s = try await runAC(fan: fan.rawValue)
        let name = s.fan?.name ?? ""
        return .result(dialog: "风速已调到\(name)")
    }
}

struct GetStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "查询空调状态"
    static let description = IntentDescription("返回开关、模式、设定温度和室温")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        do {
            ACService.shared.reloadSession()
            let s = try await ACService.shared.fetchState(reclaim: true)
            WidgetCenter.shared.reloadAllTimelines()
            return .result(value: s.summary, dialog: "\(s.summary)")
        } catch {
            throw ACIntentError(message: error.localizedDescription)
        }
    }
}

/// 给自动化用：一步设好开关、模式、温度、风速（不填的项保持不变）
struct ConfigureACIntent: AppIntent {
    static let title: LocalizedStringResource = "设置空调"
    static let description = IntentDescription("一次设置开关、模式、温度、风速，没填的项保持不变。适合放进自动化。")

    @Parameter(title: "开关")
    var power: ACPowerOption?

    @Parameter(title: "模式")
    var mode: ACModeOption?

    @Parameter(title: "温度")
    var temperature: ACTempOption?

    @Parameter(title: "风速")
    var fan: ACFanOption?

    static var parameterSummary: some ParameterSummary {
        Summary("设置空调：\(\.$power) \(\.$mode) \(\.$temperature) \(\.$fan)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let s: ACState
        if power == .off {
            s = try await runAC(power: false)
        } else {
            let turnOn: Bool? = (power == .on || mode != nil) ? true : nil
            s = try await runAC(power: turnOn, mode: mode?.rawValue,
                                temp: temperature?.degrees, fan: fan?.rawValue)
        }
        let text = s.summary
        return .result(dialog: "好的，\(text)")
    }
}

/// 控制中心 / 锁屏开关用（iOS 18+）
struct SetPowerIntent: SetValueIntent {
    static let title: LocalizedStringResource = "空调开关"
    static let isDiscoverable = false

    @Parameter(title: "开机")
    var value: Bool

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        _ = try await runAC(power: value)
        return .result()
    }
}

// MARK: - 定时（线控器自带的倒计时，到点由线控器执行，手机关了也有效）

struct TimerOffIntent: AppIntent {
    static let title: LocalizedStringResource = "定时关空调"
    static let description = IntentDescription("过一段时间自动关机。线控器自己计时，手机关了也有效。")

    @Parameter(title: "多久后")
    var duration: ACTimerOption

    init() {}
    init(duration: ACTimerOption) { self.duration = duration }

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$duration)后关空调")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let s = try await runTimerAC { try await ACService.shared.setTimer(hours: duration.hours, turnOn: false) }
        let t = s.timerEnd.map { clockText($0) } ?? ""
        return .result(dialog: "好的，\(t)关机")
    }
}

struct TimerOnIntent: AppIntent {
    static let title: LocalizedStringResource = "定时开空调"
    static let description = IntentDescription("过一段时间自动开机。线控器自己计时，手机关了也有效。")

    @Parameter(title: "多久后")
    var duration: ACTimerOption

    init() {}
    init(duration: ACTimerOption) { self.duration = duration }

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$duration)后开空调")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let s = try await runTimerAC { try await ACService.shared.setTimer(hours: duration.hours, turnOn: true) }
        let t = s.timerEnd.map { clockText($0) } ?? ""
        return .result(dialog: "好的，\(t)开机")
    }
}

struct CancelTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "取消空调定时"

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        _ = try await runTimerAC { try await ACService.shared.cancelTimer() }
        return .result(dialog: "已取消定时")
    }
}

// MARK: - 附加功能

struct FunctionIntent: AppIntent {
    static let title: LocalizedStringResource = "空调附加功能"
    static let description = IntentDescription("打开或关闭节能、睡眠、静音、森林风、强力、自清洁等（要线控器支持）")

    @Parameter(title: "操作")
    var action: ACFuncAction

    init() {}
    init(action: ACFuncAction) { self.action = action }

    static var parameterSummary: some ParameterSummary {
        Summary("空调\(\.$action)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        _ = try await runAC(funcs: [action.funcId: action.turnOn])
        let name = allFuncs.first { $0.id == action.funcId }?.name ?? ""
        let text = (action.turnOn ? "已打开" : "已关闭") + name
        return .result(dialog: "\(text)")
    }
}

/// Siri 用：开机 / 关机合成一个（省出 App 快捷指令的名额）
struct PowerIntent: AppIntent {
    static let title: LocalizedStringResource = "空调开机或关机"

    @Parameter(title: "开关")
    var state: ACPowerOption

    init() {}
    init(state: ACPowerOption) { self.state = state }

    static var parameterSummary: some ParameterSummary {
        Summary("空调\(\.$state)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        _ = try await runAC(power: state == .on)
        let text = state == .on ? "已开机" : "已关机"
        return .result(dialog: "\(text)")
    }
}
