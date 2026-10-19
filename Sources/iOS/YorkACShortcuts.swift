import AppIntents

/// 对 Siri 说的话。每句都必须包含 App 名（约克空调；Info.plist 里另加了别名“空调”）。
struct YorkACShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PowerIntent(),
            phrases: [
                "\(.applicationName)\(\.$state)",
                "用\(.applicationName)\(\.$state)",
                "把\(.applicationName)\(\.$state)",
            ],
            shortTitle: "开机 / 关机",
            systemImageName: "power"
        )
        AppShortcut(
            intent: FunctionIntent(),
            phrases: [
                "\(.applicationName)\(\.$action)",
                "把\(.applicationName)\(\.$action)",
            ],
            shortTitle: "附加功能",
            systemImageName: "moon.zzz"
        )
        AppShortcut(
            intent: SetTemperatureIntent(),
            phrases: [
                "\(.applicationName)调到\(\.$temperature)",
                "\(.applicationName)温度\(\.$temperature)",
                "\(.applicationName)设置\(\.$temperature)",
                "把\(.applicationName)调到\(\.$temperature)",
            ],
            shortTitle: "设定温度",
            systemImageName: "thermometer"
        )
        AppShortcut(
            intent: AdjustTemperatureIntent(),
            phrases: [
                "\(.applicationName)\(\.$direction)温度",
                "把\(.applicationName)温度\(\.$direction)",
                "\(.applicationName)温度\(\.$direction)一点",
            ],
            shortTitle: "调高/调低",
            systemImageName: "plusminus"
        )
        AppShortcut(
            intent: SetModeIntent(),
            phrases: [
                "\(.applicationName)\(\.$mode)",
                "\(.applicationName)切换到\(\.$mode)",
                "\(.applicationName)\(\.$mode)模式",
            ],
            shortTitle: "切换模式",
            systemImageName: "snowflake"
        )
        AppShortcut(
            intent: SetFanIntent(),
            phrases: [
                "\(.applicationName)风速\(\.$fan)",
                "\(.applicationName)风速调到\(\.$fan)",
            ],
            shortTitle: "风速",
            systemImageName: "fanblades"
        )
        AppShortcut(
            intent: TimerOffIntent(),
            phrases: [
                "\(.applicationName)\(\.$duration)后关机",
                "\(.applicationName)\(\.$duration)以后关机",
                "\(.applicationName)定时\(\.$duration)关机",
            ],
            shortTitle: "定时关机",
            systemImageName: "timer"
        )
        AppShortcut(
            intent: TimerOnIntent(),
            phrases: [
                "\(.applicationName)\(\.$duration)后开机",
                "\(.applicationName)\(\.$duration)以后开机",
                "\(.applicationName)定时\(\.$duration)开机",
            ],
            shortTitle: "定时开机",
            systemImageName: "alarm"
        )
        AppShortcut(
            intent: CancelTimerIntent(),
            phrases: [
                "\(.applicationName)取消定时",
                "取消\(.applicationName)定时",
            ],
            shortTitle: "取消定时",
            systemImageName: "timer.circle"
        )
        AppShortcut(
            intent: GetStatusIntent(),
            phrases: [
                "\(.applicationName)状态",
                "\(.applicationName)现在多少度",
                "查看\(.applicationName)",
            ],
            shortTitle: "查询状态",
            systemImageName: "info.circle"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .blue
}
