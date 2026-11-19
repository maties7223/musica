import Foundation

/// Lista de instancias de Cobalt con la última que funcionó al principio.
enum InstancePool {
    private static let listKey = "cobaltInstances"
    private static let goodKey = "cobaltLastGood"
    private static let publicKey = "cobaltUsePublic"
    private static let cacheKey = "cobaltPublicCache"

    /// Instancias públicas de reserva. Cambian a menudo; se pueden refrescar.
    private static let builtIn = [
        "https://api.cobalt.tools",
        "https://cobalt-api.kwiatekmiki.com",
        "https://cobalt-backend.canine.tools",
        "https://cobalt.aeong.one",
        "https://cobalt-api.ayo.tf",
        "https://api.cobalt.best"
    ]

    private static let sources = [
        "https://instances.cobalt.best/api/instances.json",
        "https://instances.hyper.lol/instances.json"
    ]

    static var userList: [String] {
        get { UserDefaults.standard.stringArray(forKey: listKey) ?? [] }
        set { UserDefaults.standard.set(newValue.map(\.trimmed).filter { !$0.isEmpty }, forKey: listKey) }
    }

    static var usePublic: Bool {
        get { UserDefaults.standard.object(forKey: publicKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: publicKey) }
    }

    private static var publicCache: [String] {
        get { UserDefaults.standard.stringArray(forKey: cacheKey) ?? builtIn }
        set { UserDefaults.standard.set(Array(newValue.prefix(20)), forKey: cacheKey) }
    }

    /// Orden de intento: la última que funcionó, tus instancias y, si está activo, las públicas.
    static func ordered() -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        func add(_ raw: String) {
            let text = raw.trimmed
            guard !text.isEmpty, seen.insert(text.lowercased()).inserted else { return }
            result.append(text)
        }
        if let good = UserDefaults.standard.string(forKey: goodKey) { add(good) }
        userList.forEach(add)
        if usePublic { publicCache.forEach(add) }
        return result
    }

    static func markGood(_ instance: String) {
        UserDefaults.standard.set(instance, forKey: goodKey)
    }

    /// Descarga la lista pública de instancias activas. Devuelve cuántas se añadieron.
    static func refreshPublic() async -> Int {
        for source in sources {
            guard let url = URL(string: source) else { continue }
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            else { continue }

            let found: [String] = rows.compactMap { row in
                let services = row["services"] as? [String] ?? []
                guard services.contains("youtube") else { return nil }
                if let score = row["score"] as? Int, score < 40 { return nil }
                let raw = (row["api"] as? String) ?? (row["url"] as? String)
                guard let raw, raw.lowercased().hasPrefix("https") else { return nil }
                return raw.trimmed
            }
            if !found.isEmpty {
                publicCache = found
                return found.count
            }
        }
        return 0
    }
}
