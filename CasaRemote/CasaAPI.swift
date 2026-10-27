import Foundation
import SwiftUI

enum APIError: LocalizedError {
    case badURL, unauthorized, http(Int, String), noToken
    var errorDescription: String? {
        switch self {
        case .badURL: return "Неверный адрес сервера"
        case .unauthorized: return "Сессия истекла или неверные данные"
        case .http(let c, let m): return "Ошибка HTTP \(c) \(m)"
        case .noToken: return "Сервер не вернул токен (проверьте версию CasaOS)"
        }
    }
}

struct Stats {
    var cpu = 0.0
    var temp: Double? = nil
    var memUsed = 0.0
    var memTotal = 0.0
    var memPercent = 0.0
}

struct AppItem: Identifiable {
    let id: String
    let title: String
    let icon: URL?
    let running: Bool
}

private func num(_ v: Any?) -> Double {
    if let n = v as? NSNumber { return n.doubleValue }
    if let s = v as? String, let d = Double(s) { return d }
    return 0
}

@MainActor
final class CasaAPI: ObservableObject {
    @Published var isLoggedIn = false
    @Published var baseURL = UserDefaults.standard.string(forKey: "baseURL") ?? ""
    @Published var username = UserDefaults.standard.string(forKey: "username") ?? ""
    private var token: String?

    init() {
        if !baseURL.isEmpty, !username.isEmpty, let p = Keychain.get("password") {
            Task { try? await login(url: baseURL, user: username, pass: p) }
        }
    }

    static func normalize(_ s: String) -> String {
        var u = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if !u.hasPrefix("http://") && !u.hasPrefix("https://") { u = "http://" + u }
        while u.hasSuffix("/") { u.removeLast() }
        return u
    }

    // MARK: HTTP
    func request(_ method: String, _ path: String, body: Any? = nil) async throws -> [String: Any] {
        guard let url = URL(string: baseURL + path) else { throw APIError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 15
        if let t = token { req.setValue(t, forHTTPHeaderField: "Authorization") }
        if let b = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: b, options: [.fragmentsAllowed])
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if code == 401 { isLoggedIn = false; throw APIError.unauthorized }
        guard (200..<300).contains(code) else {
            throw APIError.http(code, obj["message"] as? String ?? "")
        }
        return obj
    }

    // MARK: Auth
    func login(url: String, user: String, pass: String) async throws {
        baseURL = Self.normalize(url)
        token = nil
        let r = try await request("POST", "/v1/users/login", body: ["username": user, "password": pass])
        let d = r["data"] as? [String: Any]
        let t = d?["token"] as? [String: Any]
        guard let access = t?["access_token"] as? String else { throw APIError.noToken }
        token = access
        username = user
        UserDefaults.standard.set(baseURL, forKey: "baseURL")
        UserDefaults.standard.set(user, forKey: "username")
        Keychain.set(pass, for: "password")
        isLoggedIn = true
    }

    func logout() {
        token = nil
        Keychain.remove("password")
        isLoggedIn = false
    }

    // MARK: Data
    func stats() async throws -> Stats {
        let r = try await request("GET", "/v1/sys/utilization")
        let d = r["data"] as? [String: Any] ?? [:]
        let cpu = d["cpu"] as? [String: Any] ?? [:]
        let mem = d["mem"] as? [String: Any] ?? [:]
        var s = Stats()
        s.cpu = num(cpu["percent"])
        if cpu["temperature"] != nil { s.temp = num(cpu["temperature"]) }
        s.memTotal = num(mem["total"])
        s.memUsed = num(mem["used"])
        s.memPercent = num(mem["usedPercent"])
        if s.memPercent == 0, s.memTotal > 0 { s.memPercent = s.memUsed / s.memTotal * 100 }
        return s
    }

    func apps() async throws -> [AppItem] {
        let r = try await request("GET", "/v2/app_management/web/appgrid")
        let arr = r["data"] as? [[String: Any]] ?? []
        return arr.compactMap { a in
            guard let name = a["name"] as? String else { return nil }
            var title = name
            if let t = a["title"] as? String { title = t }
            else if let t = a["title"] as? [String: Any],
                    let v = (t["en_us"] ?? t["en_US"] ?? t.values.first) as? String { title = v }
            let status = (a["status"] as? String ?? "").lowercased()
            return AppItem(id: name, title: title,
                           icon: (a["icon"] as? String).flatMap(URL.init(string:)),
                           running: status == "running")
        }
    }

    /// action: start | stop | restart
    func control(_ id: String, _ action: String) async throws {
        do {
            _ = try await request("PATCH", "/v2/app_management/compose/\(id)/status", body: action)
        } catch {
            // fallback для старых версий CasaOS
            _ = try await request("PUT", "/v1/container/\(id)/state", body: ["state": action])
        }
    }
}
