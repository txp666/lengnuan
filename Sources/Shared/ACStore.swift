import Foundation
import SwiftUI
#if os(iOS)
import WidgetKit
#endif

/// App 界面的状态：登录、设备、轮询、发指令。网络和登录态交给 ACService。
@MainActor
final class ACStore: ObservableObject {
    @Published var loggedIn = false
    @Published var phone = ""
    @Published var controllers: [Controller] = []
    @Published var current: Controller?
    @Published var state = ACState()
    @Published var stale = true            // 显示的是上次缓存的状态
    @Published var online: Bool?
    @Published var loading = false
    @Published var busy = false
    @Published var message: String?
    @Published var error: String?
    @Published var sessionLost = false
    @Published var pendingTemp: Double?    // 连点 +/- 时先显示目标温度，停手后再发送
    @Published var timerBusy = false

    private let service: ACService
    /// 演示模式：不联网，用样例数据（预览界面用）
    let isDemo: Bool
    private var started = false
    private var api: YorkAPI { service.api }
    private var constants: JSON = [:]
    private var pollTask: Task<Void, Never>?
    private var tempTask: Task<Void, Never>?
    private var pending: (cmd: JSON, sentAt: Date, until: Date)?
    private var polling = false
    private var pollFailures = 0
    private var lastOnlineCheck = Date.distantPast
    private var visible = 0
    /// 刚设/取消定时：这段时间内面板旧的定时上报不覆盖本地
    private var expectedTimer: (flag: Bool, until: Date)?
    /// 定时到点后重新读一次完整状态（增量上报不一定带定时字段）
    private var timerRecheckedFor: Double?
    /// 刚复位滤网：这段时间内不让旧的滤网提醒上报覆盖
    private var filterResetUntil: Date?

    init(demo: Bool = false, demoState: ACState = .sample()) {
        service = ACService.shared
        isDemo = demo
        if demo {
            let c = Controller(homeId: 0, homeName: "我的家", code: "demo", name: "卧室",
                               type: "C", xkqType: "9", brand: "3")
            loggedIn = true
            controllers = [c]
            current = c
            state = demoState
            stale = false
            online = true
            return
        }
        phone = Storage.phone
        if let c = Storage.controller {
            current = c
            // 先显示上次的状态，打开就能用；后台再刷新
            if let values = Storage.lastState {
                state = ACState(values: values, xkqType: c.xkqType)
            }
            constants = Storage.constants
        }
        loggedIn = service.isLoggedIn
        // 不在这里联网：Siri / 小组件在后台拉起 App 时不需要；界面出现时再开始
    }

    // MARK: - 显示用

    var displayTemp: Double? { pendingTemp ?? state.setpoint }

    var menuTitle: String {
        guard loggedIn, !state.isEmpty else { return "" }
        if !state.power { return "关" }
        return displayTemp.map { fmtTemp($0) + "°" } ?? "开"
    }

    var menuSymbol: String {
        guard state.power, let m = state.mode else { return "power" }
        return m.symbol
    }

    // MARK: - 登录

    func login(phone: String, password: String, remember: Bool) async {
        loading = true
        defer { loading = false }
        do {
            try await service.loginPassword(phone: phone, password: password, remember: remember)
            didLogin(phone)
            started = true
            await start()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func requestCode(phone: String) async -> Bool {
        do {
            try await service.requestSMSCode(phone: phone)
            error = nil
            message = "验证码已发送"
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func loginSMS(phone: String, code: String) async {
        loading = true
        defer { loading = false }
        do {
            try await service.loginSMS(phone: phone, code: code)
            didLogin(phone)
            started = true
            await start()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func didLogin(_ phone: String) {
        if Storage.controller == nil {
            current = nil
            state = ACState()
            constants = [:]
        }
        self.phone = phone
        loggedIn = true
        sessionLost = false
        error = nil
        message = nil
    }

    func logout() {
        pollTask?.cancel()
        service.logout()
        loggedIn = false
        controllers = []
        current = nil
        state = ACState()
        constants = [:]
        online = nil
        sessionLost = false
        error = nil
        message = nil
        reloadWidgets()
    }

    func reconnect() {
        Task {
            do {
                if try await service.relogin() {
                    sessionLost = false
                    error = nil
                    await start()
                } else {
                    // 没有保存密码：回到登录页
                    loggedIn = false
                    error = "请重新登录"
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func withSession<T>(reclaim: Bool, _ op: () async throws -> T) async throws -> T {
        let result = try await service.withSession(reclaim: reclaim, op)
        sessionLost = false
        return result
    }

    // MARK: - 设备 & 状态

    func start() async {
        guard !isDemo else { return }
        loading = true
        defer { loading = false }
        do {
            let list = try await service.controllers(reclaim: false)
            sessionLost = false
            controllers = list
            if let cur = current, let fresh = list.first(where: { $0.code == cur.code }) {
                setCurrent(fresh)
            } else if let first = list.first(where: { $0.supported }) ?? list.first {
                setCurrent(first)
            } else {
                current = nil
                error = "这个账号下没有找到 Wi-Fi 线控器。确认面板已在约克智慧家里绑定到这个账号或它所在的家庭。"
                return
            }
            await fullRefresh()
            startPolling()
        } catch {
            handle(error)
        }
    }

    private func setCurrent(_ c: Controller) {
        if current?.code != c.code {
            state = ACState(xkqType: c.xkqType)
            constants = [:]
            Storage.constants = [:]
            stale = true
        }
        current = c
        Storage.controller = c
    }

    func select(code: String) {
        guard let c = controllers.first(where: { $0.code == code }), c.code != current?.code else { return }
        setCurrent(c)
        Task { await fullRefresh() }
    }

    func fullRefresh() async {
        guard !isDemo, let c = current else { return }
        do {
            let consts = await service.refreshConstants(c, reclaim: false)
            if !consts.isEmpty { constants = consts }
            let report = try await withSession(reclaim: false) { try await self.api.status(c, cursor: 0) }
            guard let report = report else {
                error = "没有拿到线控器状态（可能离线，或型号不在支持范围内）"
                return
            }
            var s = ACState(values: report, xkqType: c.xkqType)
            s.overlay(constants)
            state = s
            stale = false
            pending = nil
            pollFailures = 0
            error = nil
            Storage.lastState = state.values
            reloadWidgets()
            await checkOnline(force: true)
        } catch {
            handle(error)
        }
    }

    private func checkOnline(force: Bool) async {
        guard let c = current, force || Date().timeIntervalSince(lastOnlineCheck) > 120 else { return }
        lastOnlineCheck = Date()
        if let o = try? await api.online(c) { online = o }
    }

    // MARK: - 轮询（和约克智慧家一样每 2 秒，用上次的 roundTime 做增量查询）

    func viewAppeared() {
        visible += 1
        guard visible == 1, loggedIn, !isDemo else { return }
        if !started {
            started = true
            Task { await self.start() }
        } else {
            startPolling()
            Task { await self.pollOnce() }
        }
    }

    func viewDisappeared() {
        visible = max(0, visible - 1)
    }

    /// App 回到前台
    func becameActive() {
        guard loggedIn, !isDemo else { return }
        service.reloadSession()
        sessionLost = false
        // 小组件 / Siri 可能刚改过状态，先显示它们留下的缓存
        if let cached = service.cachedState(), Storage.lastStateAge < 60 {
            state = cached
        }
        if !started {
            started = true
            Task { await start() }
        } else {
            Task { await fullRefresh() }
            startPolling()
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval: UInt64 = (self?.visible ?? 0) > 0 ? 2 : 30
                try? await Task.sleep(nanoseconds: interval * 1_000_000_000)
                if Task.isCancelled { return }
                guard let self = self else { return }
                await self.pollOnce()
            }
        }
    }

    func pollOnce() async {
        guard !isDemo, let c = current, loggedIn, !sessionLost, !polling else { return }
        polling = true
        defer { polling = false }
        do {
            let cursor = state.cursor
            let report = try await withSession(reclaim: false) { try await self.api.status(c, cursor: cursor) }
            guard c.code == current?.code else { return }
            if let r = report { merge(r) }
            pollFailures = 0
            if state.timerFlag, let ms = num(state.values[keyTimerTime]), timerRecheckedFor != ms,
               Date().timeIntervalSince1970 * 1000 > ms + 60_000 {
                timerRecheckedFor = ms
                await fullRefresh()
            }
            if stale && report == nil && cursor > 0 { stale = false }
            if let p = pending, Date() > p.until {
                pending = nil
                message = "⚠ 15 秒内没等到面板确认，已重新读取状态"
                await fullRefresh()
            }
            await checkOnline(force: false)
        } catch {
            pollFailures += 1
            if let e = error as? YorkError, e.isAuthFailure {
                handle(error)
            } else if pollFailures >= 5 {
                handle(error)
            }
        }
    }

    private func merge(_ report: JSON) {
        var r = report
        if let exp = expectedTimer {
            if Date() > exp.until {
                expectedTimer = nil
            } else if r[keyTimerFlag] != nil {
                if isOn(r[keyTimerFlag]) != exp.flag {
                    for k in [keyTimerFlag, keyTimerOnOff, keyTimerTime] { r.removeValue(forKey: k) }
                } else {
                    expectedTimer = nil
                }
            }
        }
        if let until = filterResetUntil {
            if Date() < until {
                for i in 1...5 { r.removeValue(forKey: "filter_life_tips\(i)") }
            } else {
                filterResetUntil = nil
            }
        }
        var s = state
        if let p = pending, Date() < p.until {
            var full = s
            full.values.merge(r) { $1 }
            full.overlay(constants)
            if full.matches(p.cmd) {
                s = full
                pending = nil
                message = String(format: "✓ 面板已确认（%.1f 秒）", Date().timeIntervalSince(p.sentAt))
                reloadWidgets()
            } else {
                let protected = ACState.protectedKeys(for: p.cmd)
                for (k, v) in r where !protected.contains(k) { s.values[k] = v }
                s.overlay(constants)
            }
        } else {
            s.values.merge(r) { $1 }
            s.overlay(constants)
        }
        state = s
        stale = false
        error = nil
        Storage.lastState = state.values
    }

    // MARK: - 控制

    func send(power: Bool? = nil, mode: String? = nil, temp: Double? = nil, fan: String? = nil,
              funcs: [String: Bool] = [:]) async {
        guard current != nil else { return }
        if state.ota { error = "线控器正在升级固件，暂时不能控制"; return }
        if state.coolingDown { error = "系统冷却中（自清洁刚结束），暂时不能控制"; return }
        let cmd: JSON
        do {
            cmd = try state.command(power: power, mode: mode, temp: temp, fan: fan, funcs: funcs)
        } catch {
            self.error = error.localizedDescription
            return
        }
        guard !cmd.isEmpty else { return }
        if isDemo {
            var s = state
            s.apply(cmd)
            state = s
            message = "✓ 面板已确认（演示）"
            return
        }
        busy = true
        defer { busy = false }
        let sentAt = Date()
        do {
            try await service.send(cmd)
            sessionLost = false
            var s = state
            s.apply(cmd)
            state = s
            Storage.lastState = s.values
            pending = (cmd, sentAt, sentAt.addingTimeInterval(15))
            error = nil
            message = "已发送，等面板确认…"
            reloadWidgets()
            Task {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                await self.pollOnce()
            }
        } catch {
            handle(error)
        }
    }

    // MARK: - 定时

    /// hours 为 nil：取消定时。开着就定时关机，关着就定时开机（和约克智慧家一样）
    func setTimer(hours: Double?) {
        Task { await applyTimer(hours) }
    }

    private func applyTimer(_ hours: Double?) async {
        guard let c = current else { return }
        var s = state
        let turnOn = !s.power
        if isDemo {
            if let h = hours { s.applyTimer(hours: h, turnOn: turnOn, reply: [:]) } else { s.applyTimerCancel() }
            state = s
            message = hours == nil ? "✓ 已取消定时" : "✓ 已定时：\(s.timerText ?? "")"
            return
        }
        timerBusy = true
        defer { timerBusy = false }
        do {
            if let h = hours {
                let reply = try await withSession(reclaim: true) {
                    try await self.api.setSimpleTimer(c, hours: h, turnOn: turnOn)
                }
                s.applyTimer(hours: h, turnOn: turnOn, reply: reply)
                message = "✓ 已定时：\(s.timerText ?? "")"
            } else {
                _ = try await withSession(reclaim: true) { try await self.api.cancelSimpleTimer(c) }
                s.applyTimerCancel()
                message = "✓ 已取消定时"
            }
            // 等待期间面板的上报可能改了别的字段，只覆盖定时这几项
            var merged = state
            for k in [keyTimerFlag, keyTimerOnOff, keyTimerTime] { merged.values[k] = s.values[k] }
            state = merged
            Storage.lastState = merged.values
            expectedTimer = (hours != nil, Date().addingTimeInterval(15))
            error = nil
            reloadWidgets()
        } catch {
            handle(error)
        }
    }

    // MARK: - 附加功能 / 滤网

    func toggleFunc(_ id: String) {
        let active = state.activeFuncIds.contains(id)
        Task { await send(funcs: [id: !active]) }
    }

    /// 停止正在进行的自清洁 / 高温杀菌
    func stopRunning() {
        guard let id = state.stoppableFunc else { return }
        Task { await send(funcs: [id: false]) }
    }

    func resetFilter() {
        Task {
            if isDemo {
                var s = state
                s.applyFilterReset()
                state = s
                message = "✓ 滤网已复位"
                return
            }
            busy = true
            defer { busy = false }
            do {
                try await service.send(filterResetCommand)
                var s = state
                s.applyFilterReset()
                state = s
                Storage.lastState = s.values
                filterResetUntil = Date().addingTimeInterval(15)
                message = "✓ 滤网已复位"
                error = nil
            } catch {
                handle(error)
            }
        }
    }

    func togglePower() {
        Task { await send(power: !state.power) }
    }

    func setMode(_ id: String) {
        Task { await send(power: true, mode: id) }
    }

    func setFan(_ id: String) {
        Task { await send(fan: id) }
    }

    func nudgeTemp(_ direction: Double) {
        guard let base = displayTemp else { return }
        let step = state.halfStep ? 0.5 : 1.0
        let (lo, hi) = state.limits(for: state.mode?.id)
        let t = min(max(base + direction * step, lo), hi)
        pendingTemp = t
        tempTask?.cancel()
        tempTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard let self = self, !Task.isCancelled else { return }
            await self.send(temp: t)
            if self.pendingTemp == t { self.pendingTemp = nil }
        }
    }

    private func handle(_ err: Error) {
        if let e = err as? YorkError {
            switch e {
            case .sessionTaken:
                sessionLost = true
            case .notLoggedIn:
                loggedIn = false
            default:
                break
            }
        }
        error = err.localizedDescription
    }

    private func reloadWidgets() {
        #if os(iOS)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
