import Foundation

/// iOS 上 App、Siri 意图、小组件运行在不同进程，靠 App Group 共享登录态和缓存。
/// App Group 的名字来自 Info.plist 的 YorkAppGroup（= group.$(YORK_BUNDLE_ID)，见 Config/Base.xcconfig）。
enum AppConfig {
    #if os(iOS)
    static let appGroup: String? = Bundle.main.object(forInfoDictionaryKey: "YorkAppGroup") as? String
    #else
    static let appGroup: String? = nil
    #endif
}

enum Storage {
    static let defaults: UserDefaults =
        AppConfig.appGroup.flatMap { UserDefaults(suiteName: $0) } ?? .standard

    static var clientId: String {
        if let id = defaults.string(forKey: "clientId"), !id.isEmpty { return id }
        // 登录时要带一个推送 id（不能为空），用自己的随机 id，免得抢走手机 App 的推送
        let id = String((0..<19).map { _ in "0123456789abcdef".randomElement()! })
        defaults.set(id, forKey: "clientId")
        return id
    }

    static var phone: String {
        get { defaults.string(forKey: "phone") ?? "" }
        set { defaults.set(newValue, forKey: "phone") }
    }

    static var session: Session? {
        get { decode(Session.self, "session") }
        set { encode(newValue, "session") }
    }

    static var controller: Controller? {
        get { decode(Controller.self, "controller") }
        set { encode(newValue, "controller") }
    }

    /// 上次看到的线控器状态（打开 App / 小组件时先显示它）
    static var lastState: JSON? {
        get { json("lastState") }
        set {
            setJSON(newValue, "lastState")
            defaults.set(Date().timeIntervalSince1970, forKey: "lastStateAt")
        }
    }

    /// lastState 是多久之前更新的（秒）
    static var lastStateAge: TimeInterval {
        let t = defaults.double(forKey: "lastStateAt")
        return t > 0 ? Date().timeIntervalSince1970 - t : .infinity
    }

    /// 线控器常量：能力位、锁定位、温度范围
    static var constants: JSON {
        get { json("constants") ?? [:] }
        set { setJSON(newValue.isEmpty ? nil : newValue, "constants") }
    }

    /// 刚发过指令时，小组件先显示预期状态，等面板确认后再从云端刷新
    static var optimisticUntil: Date {
        get { Date(timeIntervalSince1970: defaults.double(forKey: "optimisticUntil")) }
        set { defaults.set(newValue.timeIntervalSince1970, forKey: "optimisticUntil") }
    }

    static func clearAccount() {
        for k in ["session", "controller", "lastState", "lastStateAt", "constants", "optimisticUntil"] {
            defaults.removeObject(forKey: k)
        }
    }

    // MARK: -

    private static func decode<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let d = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: d)
    }

    private static func encode<T: Encodable>(_ value: T?, _ key: String) {
        if let v = value, let d = try? JSONEncoder().encode(v) {
            defaults.set(d, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private static func json(_ key: String) -> JSON? {
        guard let d = defaults.data(forKey: key) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? JSON
    }

    private static func setJSON(_ value: JSON?, _ key: String) {
        if let v = value, JSONSerialization.isValidJSONObject(v),
           let d = try? JSONSerialization.data(withJSONObject: v) {
            defaults.set(d, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
