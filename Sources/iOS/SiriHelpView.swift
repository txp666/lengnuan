import SwiftUI

/// “Siri 与自动化”说明页
struct SiriHelpView: View {
    @Environment(\.dismiss) private var dismiss

    private let phrases: [(String, String)] = [
        ("冷暖开机", "开机"),
        ("冷暖关机", "关机"),
        ("冷暖调到26度", "设定温度（16–30 度）"),
        ("冷暖调高温度 / 调低温度", "温度 ±1 度"),
        ("冷暖制冷 / 制热 / 送风 / 除湿", "切换模式（会同时开机）"),
        ("冷暖风速自动", "调风速"),
        ("冷暖打开睡眠 / 关闭静音", "附加功能：节能、睡眠、静音、森林风、强力、自清洁、高温杀菌等"),
        ("冷暖两小时后关机", "定时关机（半小时–12 小时）"),
        ("冷暖一小时后开机", "定时开机"),
        ("冷暖取消定时", "取消定时"),
        ("冷暖状态", "播报当前状态和室温"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(phrases, id: \.0) { p in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("“\(p.0)”").font(.body.weight(.medium))
                            Text(p.1).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("对 Siri 说")
                } footer: {
                    Text("第一次用时 Siri 可能会问是否允许，选“允许”。也可以在“快捷指令”App 的“App 快捷指令”里看到这些指令。")
                }

                Section {
                    Label("打开“快捷指令”App → 底部“自动化” → 右上角“+”", systemImage: "1.circle")
                    Label("选触发条件：特定时间、到达/离开某地、连接 Wi-Fi、闹钟、专注模式等", systemImage: "2.circle")
                    Label("选“立即运行”，然后搜索“冷暖”，添加“设置空调”（可一次设好开关、模式、温度、风速）", systemImage: "3.circle")
                } header: {
                    Text("每天定时 / 家庭自动化（快捷指令）")
                } footer: {
                    Text("例：工作日 18:30 → 设置空调：开机、制冷、26 度；每天 23:00 → 定时关空调 2 小时；离开家 → 关闭空调。App 里的“定时”是线控器自带的倒计时（一次性，手机关了也有效）；每天重复的定时用快捷指令自动化。")
                }

                Section {
                    Label("主屏幕：长按空白处 → 编辑 → 添加小组件 → 冷暖（可直接点按钮开关、调温）", systemImage: "square.grid.2x2")
                    Label("控制中心 / 锁定屏幕（iOS 18+）：添加控制 → 空调开关", systemImage: "switch.2")
                } header: {
                    Text("不打开 App 控制")
                }

                Section {
                    Text("所有控制都通过约克云端，需要联网。同一账号只能在一处登录：冷暖的 App、小组件、Siri 共用一个登录，但会和手机上的“约克智慧家”互相挤下线，建议给本 App 单独用一个账号。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Siri 与自动化")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
