import Foundation

// 约克智慧家（海信日立 hicloud）云端接口。
// 协议参考开源项目 ha-york-smart-home（MIT）：https://github.com/mufeng05/ha-york-smart-home

typealias JSON = [String: Any]

enum YorkError: LocalizedError {
    case sessionTaken          // HTTP 401：账号在别处登录了
    case expired               // HTTP 403：token 失效
    case notLoggedIn
    case server(String)
    case network(String)
    case outdated
    case rateLimited
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .sessionTaken: return "账号已在其他设备登录（同一账号只能在一处登录）"
        case .expired: return "登录已过期"
        case .notLoggedIn: return "还没登录"
        case .server(let m): return m
        case .network(let m): return "网络错误：\(m)"
        case .outdated: return "云端要求升级 App 版本（需要更新代码里的 appVersion）"
        case .rateLimited: return "请求太频繁，稍后再试"
        case .invalid(let m): return "返回数据异常：\(m)"
        }
    }

    var isExpired: Bool {
        if case .expired = self { return true }
        return false
    }

    var isAuthFailure: Bool {
        switch self {
        case .sessionTaken, .expired: return true
        default: return false
        }
    }
}

struct Envelope {
    let code: String
    let message: String?
    let data: Any?
}

struct Session: Codable {
    var token: String
    var userId: Int?
    var refreshToken: String?
    var loginVersion: Int
}

struct Controller: Codable, Identifiable, Hashable {
    var homeId: Int
    var homeName: String
    var code: String
    var name: String
    var type: String
    var xkqType: String
    var brand: String

    var id: String { code }
    var supported: Bool { type == "C" && (xkqType == "8" || xkqType == "9") && brand == "3" }
}

@MainActor
final class YorkAPI {
    static let base = "https://1app.hicloud.hisensehitachi.com"
    static let apiKey = "61PdDpLyYzpctYwwVpbHRb2"
    static let appId = "com.hisensehitachi.iyes2"
    static let appVersion = "1.8.2.260807104325_release"
    static let appTag = "V1"
    static let ctrlTypeSingle = "YO420"

    var session: Session?
    let clientId: String
    private let http: URLSession

    init(session: Session?, clientId: String) {
        self.session = session
        self.clientId = clientId
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 15
        http = URLSession(configuration: cfg)
    }

    // MARK: - HTTP

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private static func escape(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: unreserved) ?? s
    }

    private func headers(_ token: String?) -> [String: String] {
        [
            "Content-Type": "application/json",
            "Accept": "application/json, text/plain, */*",
            "X-His-AppId": Self.appId,
            "X-His-AppTag": Self.appTag,
            "X-His-APIKey": Self.apiKey,
            "X-His-Version": Self.appVersion,
            "X-His-OS": "Android",
            "X-His-Locale": "zh_CN",
            "X-His-Timestamp": String(Int64(Date().timeIntervalSince1970 * 1000)),
            "Authorization": token.map { "Bearer \($0)" } ?? "Bearer",
        ]
    }

    /// 发一个请求，返回 {code, message, data}。错误信息里不带 URL（登录 URL 里有密码）。
    func envelope(_ method: String, _ path: String, query: [(String, String)] = [],
                  body: Any? = nil, token: String? = nil) async throws -> Envelope {
        var s = Self.base + path
        if !query.isEmpty {
            s += "?" + query.map { "\(Self.escape($0.0))=\(Self.escape($0.1))" }.joined(separator: "&")
        }
        guard let url = URL(string: s) else { throw YorkError.invalid("URL") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        for (k, v) in headers(token) { req.setValue(v, forHTTPHeaderField: k) }
        if let body = body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let result: (Data, URLResponse)
        do {
            result = try await http.data(for: req)
        } catch {
            throw YorkError.network((error as NSError).localizedDescription)
        }
        let (data, resp) = result
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw YorkError.sessionTaken }
        if status == 403 { throw YorkError.expired }
        if status == 429 { throw YorkError.rateLimited }
        guard status == 200 else { throw YorkError.server("服务器返回 HTTP \(status)") }

        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? JSON,
              let rawCode = obj["code"] else {
            throw YorkError.invalid(path)
        }
        let code = str(rawCode)
        if code == "401" { throw YorkError.sessionTaken }
        if code == "403" { throw YorkError.expired }
        if code == "300" { throw YorkError.outdated }
        return Envelope(code: code, message: obj["message"] as? String, data: obj["data"])
    }

    private func authed(_ method: String, _ path: String, body: Any? = nil) async throws -> Envelope {
        guard let token = session?.token else { throw YorkError.notLoggedIn }
        return try await envelope(method, path, body: body, token: token)
    }

    private func data(_ method: String, _ path: String, body: Any? = nil) async throws -> Any? {
        let env = try await authed(method, path, body: body)
        guard env.code == "200" else {
            throw YorkError.server(env.message ?? "请求失败（code \(env.code)）")
        }
        return env.data
    }

    // MARK: - 登录

    private func accept(_ env: Envelope) throws {
        guard env.code == "200" else {
            throw YorkError.server(env.message ?? "登录失败（code \(env.code)）")
        }
        guard let d = env.data as? JSON, let user = d["user"] as? JSON,
              let token = user["token"] as? String, !token.isEmpty else {
            throw YorkError.invalid("登录返回里没有 token")
        }
        let refresh = (user["refreshToken"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        session = Session(
            token: token,
            userId: num(user["userId"]).map { Int($0) },
            refreshToken: refresh ?? session?.refreshToken,
            loginVersion: Int(num(user["version"]) ?? 0)
        )
    }

    private func loginRequest(_ path: String, _ query: [(String, String)]) async throws {
        do {
            let env = try await envelope("GET", path, query: query + [("jgRegId", clientId)])
            try accept(env)
        } catch let e as YorkError where e.isAuthFailure {
            throw YorkError.server("登录被拒绝")
        }
    }

    func loginPassword(phone: String, password: String) async throws {
        try await loginRequest("/login", [
            ("phoneNo", phone), ("password", password),
            ("version", String(session?.loginVersion ?? 0)),
        ])
    }

    func requestSMSCode(phone: String) async throws {
        let env = try await envelope("POST", "/smsLogin/getVerifyCode", body: ["phoneNo": phone])
        guard env.code == "200" else {
            throw YorkError.server(env.message ?? "发送验证码失败（code \(env.code)）")
        }
    }

    func loginSMS(phone: String, code: String) async throws {
        try await loginRequest("/smsLogin", [
            ("phoneNo", phone), ("version", "0"), ("verifyCode", code), ("refreshToken", ""),
        ])
    }

    func loginRefresh(phone: String) async throws {
        guard let rt = session?.refreshToken else { throw YorkError.notLoggedIn }
        try await loginRequest("/smsLogin", [
            ("phoneNo", phone), ("version", String(session?.loginVersion ?? 0)), ("refreshToken", rt),
        ])
    }

    // MARK: - 设备

    func controllers() async throws -> [Controller] {
        let d = try await data("GET", "/api/apphome/homes/homeList/deviceList") as? JSON
        guard let homes = d?["allHomeDeviceList"] as? [JSON] else {
            throw YorkError.invalid("设备列表")
        }
        var out: [Controller] = []
        for h in homes {
            guard let homeId = num(h["homeId"]).map({ Int($0) }) else { continue }
            for x in (h["xkqList"] as? [JSON]) ?? [] {
                let code = str(x["xkqCode"])
                guard !code.isEmpty else { continue }
                let brand = str(x["brand"])
                out.append(Controller(
                    homeId: homeId,
                    homeName: str(h["homeName"]),
                    code: code,
                    name: str(x["xkqName"]).isEmpty ? "线控器" : str(x["xkqName"]),
                    type: str(x["type"]).isEmpty ? "C" : str(x["type"]),
                    xkqType: str(x["xkqType"]).isEmpty ? "9" : str(x["xkqType"]),
                    brand: brand.isEmpty ? "3" : brand
                ))
            }
        }
        return out
    }

    private func path(_ c: Controller) -> String {
        let code = c.code.addingPercentEncoding(withAllowedCharacters: Self.unreserved) ?? c.code
        return "/api/appdevice/homes/\(c.homeId)/xkqs/\(code)"
    }

    /// 线控器的能力位、锁定位、温度范围（App 每次打开控制页读一次）
    func constants(_ c: Controller) async throws -> JSON {
        let d = try await data("GET", path(c)) as? JSON
        return parseConstants(d?["constantJson"])
    }

    /// 状态。cursor = 0 取当前完整状态；否则只在面板有更新的上报时返回。
    func status(_ c: Controller, cursor: Int) async throws -> JSON? {
        let body: JSON = [
            "homeId": c.homeId,
            "boxList": [String](),
            "iuIdList": [String](),
            "iuIdListGjy": [String](),
            "xkqListGjy": [["xkqCode": c.code, "timestamp": cursor] as JSON],
        ]
        let d = try await data("POST", "/api/appstatus/homes/\(c.homeId)/status", body: body) as? JSON
        let list = (d?["xkqStatusListGjy"] as? [JSON]) ?? []
        return list.first { str($0["xkqCode"]) == c.code }
    }

    func online(_ c: Controller) async throws -> Bool? {
        let body: JSON = ["xkqCtrlList": [["xkqCode": c.code, "deviceType": c.type] as JSON]]
        let d = try await data("POST", "/api/appcontrol/cmds/xkqOnlineStatus", body: body)
        for item in (d as? [JSON]) ?? [] where str(item["xkqCode"]) == c.code {
            return isOn(item["online"])
        }
        return nil
    }

    func control(_ c: Controller, _ ctrl: JSON) async throws {
        let body: JSON = [
            "homeId": c.homeId,
            "ctrlType": Self.ctrlTypeSingle,
            "ctrlList": [String](),
            "xkqCtrlList": [[
                "xkqCode": c.code,
                "deviceType": c.type,
                "xkqType": c.xkqType,
                "ctrlJson": ctrl,
            ] as JSON],
        ]
        let env = try await authed("POST", "/api/appcontrol/cmds/multiIuOuCtrl", body: body)
        guard env.code == "200" else {
            throw YorkError.server(env.message ?? "指令被拒绝（code \(env.code)）")
        }
    }

    // MARK: - 简易定时（线控器自带的倒计时，到点由线控器执行，手机关了也有效）

    /// hours：0.5~10 小时（每半小时一档）或 11~24 小时；turnOn：到点开机（否则关机）。
    /// 返回云端答复的 data，里面的 timerSimpleTime 是到点时间（毫秒时间戳）。
    func setSimpleTimer(_ c: Controller, hours: Double, turnOn: Bool) async throws -> JSON {
        try await simpleTimer(c, [
            "timerSimpleMinute": Int(hours * 60),
            "ctrlJson": ["timer_switch": turnOn ? "1" : "0", "simple_timer_time": Int(hours * 2)] as JSON,
        ])
    }

    func cancelSimpleTimer(_ c: Controller) async throws -> JSON {
        try await simpleTimer(c, [
            "timerSimpleMinute": 0,
            "ctrlJson": ["simple_timer_time": 0] as JSON,
        ])
    }

    private func simpleTimer(_ c: Controller, _ body: JSON) async throws -> JSON {
        let env = try await authed("POST", path(c) + "/simpleTimer", body: body)
        guard env.code == "200" else {
            throw YorkError.server(env.message ?? "定时设置失败（code \(env.code)）")
        }
        return (env.data as? JSON) ?? [:]
    }
}

// MARK: - 宽松的取值工具（接口里 "1"、1、true 混用）

func str(_ v: Any?) -> String {
    guard let v = v else { return "" }
    switch v {
    case let s as String: return s
    case let n as NSNumber: return n.stringValue
    default: return ""
    }
}

func num(_ v: Any?) -> Double? {
    guard let v = v else { return nil }
    switch v {
    case let s as String: return Double(s.trimmingCharacters(in: .whitespaces))
    case let n as NSNumber:
        if CFGetTypeID(n as CFTypeRef) == CFBooleanGetTypeID() { return nil }
        let d = n.doubleValue
        return d.isFinite ? d : nil
    default: return nil
    }
}

func isOn(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    switch v {
    case let s as String: return s == "1"
    case let n as NSNumber: return n.intValue == 1
    default: return false
    }
}

func same(_ a: Any?, _ b: Any?) -> Bool {
    if let x = num(a), let y = num(b) { return x == y }
    return str(a) == str(b)
}

func parseConstants(_ v: Any?) -> JSON {
    if let s = v as? String, let d = s.data(using: .utf8),
       let obj = (try? JSONSerialization.jsonObject(with: d)) as? JSON {
        return obj
    }
    return (v as? JSON) ?? [:]
}
