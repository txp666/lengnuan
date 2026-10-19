import Foundation

/// 无界面的控制服务：登录态、自动重连、读状态、发指令。
/// App 界面（ACStore）、Siri/快捷指令、小组件都用它。
@MainActor
final class ACService {
    static let shared = ACService()

    let api: YorkAPI

    private init() {
        api = YorkAPI(session: Storage.session, clientId: Storage.clientId)
    }

    var isLoggedIn: Bool { api.session != nil }

    // MARK: - 登录态

    /// 另一个进程（App / 小组件 / Siri）可能刚重新登录过，读最新的 token
    func reloadSession() {
        api.session = Storage.session
    }

    func saveSession() {
        Storage.session = api.session
    }

    func loginPassword(phone: String, password: String, remember: Bool) async throws {
        try await api.loginPassword(phone: phone, password: password)
        if remember { Keychain.save(password, account: phone) } else { Keychain.delete(account: phone) }
        didLogin(phone)
    }

    func requestSMSCode(phone: String) async throws {
        try await api.requestSMSCode(phone: phone)
    }

    func loginSMS(phone: String, code: String) async throws {
        try await api.loginSMS(phone: phone, code: code)
        didLogin(phone)
    }

    private func didLogin(_ phone: String) {
        if phone != Storage.phone {
            Storage.controller = nil
            Storage.lastState = nil
            Storage.constants = [:]
        }
        Storage.phone = phone
        saveSession()
    }

    func logout() {
        Keychain.delete(account: Storage.phone)
        api.session = nil
        Storage.clearAccount()
    }

    /// 会话失效时重新登录：有记住的密码用密码，短信登录的用 refreshToken
    func relogin() async throws -> Bool {
        let phone = Storage.phone
        guard !phone.isEmpty else { return false }
        if let pw = Keychain.load(account: phone) {
            try await api.loginPassword(phone: phone, password: pw)
        } else if api.session?.refreshToken != nil {
            try await api.loginRefresh(phone: phone)
        } else {
            return false
        }
        saveSession()
        return true
    }

    /// reclaim = true：用户主动操作，账号被别处登录时也抢回来（和约克智慧家 App 一样）
    func withSession<T>(reclaim: Bool, _ op: () async throws -> T) async throws -> T {
        do {
            return try await op()
        } catch let e as YorkError {
            guard e.isAuthFailure else { throw e }
            // 先看看是不是本机另一个进程已经换了新 token
            let before = api.session?.token
            reloadSession()
            if let now = api.session?.token, now != before {
                do {
                    return try await op()
                } catch let e2 as YorkError where e2.isAuthFailure {
                    // 新 token 也不行，继续往下重新登录
                }
            }
            guard reclaim || e.isExpired else { throw e }
            guard try await relogin() else { throw e }
            return try await op()
        }
    }

    // MARK: - 设备与状态

    func controllers(reclaim: Bool) async throws -> [Controller] {
        try await withSession(reclaim: reclaim) { try await self.api.controllers() }
    }

    func ensureController() async throws -> Controller {
        if let c = Storage.controller { return c }
        let list = try await controllers(reclaim: true)
        guard let c = list.first(where: { $0.supported }) ?? list.first else {
            throw Refused("这个账号下没有找到 Wi-Fi 线控器")
        }
        Storage.controller = c
        return c
    }

    func refreshConstants(_ c: Controller, reclaim: Bool) async -> JSON {
        if let fresh = try? await withSession(reclaim: reclaim, { try await self.api.constants(c) }),
           !fresh.isEmpty {
            Storage.constants = fresh
            return fresh
        }
        return Storage.constants
    }

    /// 从云端读完整状态（常量 + 当前上报）
    func fetchState(reclaim: Bool, refreshConstants refresh: Bool = false) async throws -> ACState {
        guard isLoggedIn else { throw Refused("还没登录，请先打开冷暖 App 登录") }
        let c = try await ensureController()
        var consts = Storage.constants
        if refresh || consts.isEmpty {
            consts = await refreshConstants(c, reclaim: reclaim)
        }
        let report = try await withSession(reclaim: reclaim) { try await self.api.status(c, cursor: 0) }
        guard let r = report else { throw Refused("没有拿到空调状态，线控器可能离线了") }
        var s = ACState(values: r, xkqType: c.xkqType)
        s.overlay(consts)
        Storage.lastState = s.values
        return s
    }

    func send(_ cmd: JSON) async throws {
        let c = try await ensureController()
        try await withSession(reclaim: true) { try await self.api.control(c, cmd) }
        Storage.optimisticUntil = Date().addingTimeInterval(20)
    }

    /// 本地缓存的状态（App 轮询、小组件刷新、上次指令都会更新它）
    func cachedState() -> ACState? {
        guard let values = Storage.lastState, let c = Storage.controller else { return nil }
        var s = ACState(values: values, xkqType: c.xkqType)
        s.overlay(Storage.constants)
        return s
    }

    /// 给 Siri / 快捷指令 / 小组件用，尽量只发 1 次网络请求：
    /// 用本地缓存的状态生成指令直接发送（指定的项强制发送，不怕缓存过时）；
    /// 只有“开关切换 / 温度 ±1”这种依赖当前值的操作，在缓存太旧时才先读一次云端。
    func run(power: Bool? = nil, toggle: Bool = false, mode: String? = nil, temp: Double? = nil,
             tempSteps: Double? = nil, fan: String? = nil, funcs: [String: Bool] = [:]) async throws -> ACState {
        reloadSession()
        guard isLoggedIn else { throw Refused("还没登录，请先打开冷暖 App 登录") }
        // 依赖当前值的操作（开关切换、温度 ±1、附加功能的互斥）要较新的状态
        let relative = toggle || tempSteps != nil || !funcs.isEmpty
        var s: ACState
        let age = Storage.lastStateAge
        if let cached = cachedState(), age < (relative ? 180 : 7 * 24 * 3600) {
            s = cached
        } else {
            s = try await fetchState(reclaim: true)
        }
        // 这两个是临时状态，只信最近的数据
        if age < 180 || Storage.lastStateAge < 5 {
            if s.ota { throw Refused("线控器正在升级固件，暂时不能控制") }
            if s.coolingDown { throw Refused("系统冷却中，暂时不能控制") }
        }

        var targetPower = power
        if toggle { targetPower = !s.power }
        var target = temp
        if let steps = tempSteps {
            guard let sp = s.setpoint else { throw Refused("当前模式不能调温度") }
            target = sp + steps * (s.halfStep ? 0.5 : 1)
        }
        let cmd = try s.command(power: targetPower, mode: mode, temp: target, fan: fan, funcs: funcs, force: true)
        if !cmd.isEmpty {
            try await send(cmd)
            s.apply(cmd)
            Storage.lastState = s.values
        }
        return s
    }
}

extension ACService {
    /// 设定简易定时。turnOn 为 nil 时和约克智慧家一样：开着就定时关机，关着就定时开机。
    func setTimer(hours: Double, turnOn: Bool? = nil) async throws -> ACState {
        reloadSession()
        guard isLoggedIn else { throw Refused("还没登录，请先打开冷暖 App 登录") }
        guard timerHours.contains(hours) else { throw Refused("定时时长只能是半小时到 24 小时") }
        // 定时的方向取决于当前开关，缓存超过 1 分钟就先读一次云端
        var s: ACState
        if let cached = cachedState(), Storage.lastStateAge < 60 {
            s = cached
        } else {
            s = try await fetchState(reclaim: true)
        }
        let action = turnOn ?? !s.power
        if action && s.power { throw Refused("空调已经开着了") }
        if !action && !s.power { throw Refused("空调现在是关着的") }
        let c = try await ensureController()
        let reply = try await withSession(reclaim: true) {
            try await self.api.setSimpleTimer(c, hours: hours, turnOn: action)
        }
        s.applyTimer(hours: hours, turnOn: action, reply: reply)
        Storage.lastState = s.values
        return s
    }

    func cancelTimer() async throws -> ACState {
        reloadSession()
        guard isLoggedIn else { throw Refused("还没登录，请先打开冷暖 App 登录") }
        let c = try await ensureController()
        _ = try await withSession(reclaim: true) { try await self.api.cancelSimpleTimer(c) }
        guard var s = cachedState() else { return ACState(xkqType: c.xkqType) }
        s.applyTimerCancel()
        Storage.lastState = s.values
        return s
    }
}

extension ACState {
    /// 给 Siri 念的一句话（尽量短，念完 Siri 才会消失）
    var summary: String {
        var parts: [String] = []
        if !power {
            parts.append("已关机")
        } else {
            var t = mode?.name ?? "开机"
            if hasTemp, let sp = setpoint { t += "\(fmtTemp(sp))度" }
            parts.append(t)
        }
        if let room = roomTemp { parts.append("室内\(room)度") }
        return parts.joined(separator: "，")
    }
}
