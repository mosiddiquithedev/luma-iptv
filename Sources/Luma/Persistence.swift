import Foundation
import Security
import LumaCore

enum SecureSource {
    static let service = (Bundle.main.bundleIdentifier ?? "app.luma.iptv") + ".source"
    static func save(_ source: Source) throws {
        let data = try JSONEncoder().encode(source)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "current"]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(add as CFDictionary, nil)
            guard added == errSecSuccess else { throw keychainError(added) }
        } else if status != errSecSuccess { throw keychainError(status) }
    }
    static func load() throws -> Source? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "current", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw NSError(domain: "Keychain", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Your saved login could not be opened. Unlock your Mac or allow Luma to access its login in Keychain, then retry."])
        }
        return try JSONDecoder().decode(Source.self, from: data)
    }
    static func delete() { SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary) }
    static func keychainError(_ code: OSStatus) -> NSError { NSError(domain: "Keychain", code: Int(code), userInfo: [NSLocalizedDescriptionKey: "macOS Keychain could not save this login. You can still watch, but may need to sign in again."]) }
}

struct LibraryStorage {
    let root: URL
    init() {
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Luma", isDirectory: true)
    }
    func file(for source: Source) -> URL { root.appendingPathComponent(M3UParser.stableID(source.type.rawValue + source.address + source.username) + ".json") }
    func load(_ source: Source) -> UserLibrary {
        guard let data = try? Data(contentsOf: file(for: source)), let state = try? JSONDecoder().decode(UserLibrary.self, from: data) else { return UserLibrary() }
        return state
    }
    func save(_ state: UserLibrary, source: Source) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(state).write(to: file(for: source), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file(for: source).path)
    }
}
