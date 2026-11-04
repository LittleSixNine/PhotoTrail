import Security
import LocalAuthentication
import SwiftUI

struct AMapCredentials: Codable, Sendable {
    let key: String
    let securityJsCode: String
    var storage: AMapCredentialStore.Storage = .local

    private enum CodingKeys: String, CodingKey { case key, securityJsCode }

    private static let service = "local.PhotoTrail.AMap"
    private static let keychainLock = NSLock()
    private static func query(service serviceName: String = Self.service) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: serviceName,
         kSecAttrAccount as String: "js-api"]
    }

    static func load(bundleIdentifier: String? = Bundle.main.bundleIdentifier) throws -> Self? {
        #if DEBUG
        // Metadata-only validation apps never request access to the user's map credentials.
        if bundleIdentifier?.hasPrefix("local.PhotoTrail.MetadataReference") == true { return nil }
        #endif
        return try AMapCredentialStore.shared().load()
    }

    static func keychainExists() throws -> Bool {
        try keychainExists(services: [Self.service, "local.GeoTagCN.AMap"])
    }

    static func keychainExists(services: [String]) throws -> Bool {
        for service in services {
            let query = readQuery(service: service, allowUI: false, returnData: false)
            let (status, _) = try copyKeychain(query, allowUI: false)
            if status == errSecSuccess || status == errSecInteractionNotAllowed || status == errSecAuthFailed {
                return true
            }
            if status != errSecItemNotFound { throw KeychainError(status: status) }
        }
        return false
    }

    private static func copyKeychain(_ query: [String: Any], allowUI: Bool) throws -> (OSStatus, CFTypeRef?) {
        try keychainLock.withLock {
            // LAContext alone does not suppress the classic macOS keychain's authorization UI.
            var previous = DarwinBoolean(false)
            if !allowUI {
                let status = SecKeychainGetUserInteractionAllowed(&previous)
                guard status == errSecSuccess else { throw KeychainError(status: status) }
                let disabled = SecKeychainSetUserInteractionAllowed(false)
                guard disabled == errSecSuccess else { throw KeychainError(status: disabled) }
            }
            defer { if !allowUI { SecKeychainSetUserInteractionAllowed(previous.boolValue) } }
            var result: CFTypeRef?
            return (SecItemCopyMatching(query as CFDictionary, &result), result)
        }
    }

    private static func readQuery(service: String, allowUI: Bool, returnData: Bool) -> [String: Any] {
        var query = Self.query(service: service)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[returnData ? kSecReturnData as String : kSecReturnAttributes as String] = true
        if !allowUI {
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext as String] = context
        }
        return query
    }

    func save() throws {
        try AMapCredentialStore.shared().save(self)
    }

    static func loadKeychain(_ allowUI: Bool) throws -> Self? {
        try loadKeychain(allowUI, services: [Self.service, "local.GeoTagCN.AMap"])
    }

    static func loadKeychain(_ allowUI: Bool, services: [String]) throws -> Self? {
        for service in services {
            let query = readQuery(service: service, allowUI: allowUI, returnData: true)
            let (status, result) = try copyKeychain(query, allowUI: allowUI)
            if status == errSecItemNotFound { continue }
            guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status: status) }
            var credentials = try JSONDecoder().decode(Self.self, from: data)
            credentials.storage = .keychain
            return credentials
        }
        return nil
    }

    static func saveKeychain(_ credentials: Self) throws {
        try keychainLock.withLock { try writeKeychain(credentials) }
    }

    private static func writeKeychain(_ credentials: Self) throws {
        let data = try JSONEncoder().encode(credentials)
        let values = [kSecValueData as String: data]
        let status = SecItemUpdate(Self.query() as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var item = Self.query()
            item[kSecValueData as String] = data
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError(status: added) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            if status == errSecInteractionNotAllowed || status == errSecAuthFailed {
                return L10n.text("旧钥匙串需要授权，请点击“从钥匙串读取”。也可改用本地共享，保存后不再请求钥匙串。")
            }
            return L10n.text("无法访问高德凭据的钥匙串记录（%1$@）。", status)
        }
    }
}

struct AMapSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var code = ""
    @State private var error: String?
    @State private var loadingCredentials = false
    @State private var storage: AMapCredentialStore.Storage = .local
    @State private var initialized = false
    var initialCredentials: AMapCredentials?
    var makeStore: @Sendable () throws -> AMapCredentialStore = AMapCredentialStore.shared
    let onSave: (AMapCredentials) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text("高德地图设置")).font(.title2)
            HStack {
                Label(L10n.text(storage == .local ? "本机加密 · 正式版与测试版共用" : "钥匙串 · 旧版兼容"),
                      systemImage: storage == .local ? "lock.doc" : "key")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                if storage == .keychain {
                    Button(L10n.text("改用本地共享")) { useLocalStorage() }
                        .controlSize(.small)
                        .disabled(loadingCredentials || !initialized)
                }
            }
            SecureField("JS API Key", text: $key)
            SecureField(L10n.text("安全密钥 securityJsCode"), text: $code)
            Text(L10n.text("此版本用于自用开发验证。加载后，显示照片和校验选点会向高德发送经纬度；照片文件留在本机。"))
                .font(.footnote).foregroundStyle(.secondary)
            Link(L10n.text("高德安全密钥说明"), destination:
                    URL(string: "https://lbs.amap.com/api/javascript-api-v2/guide/abc/jscode")!)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                if storage == .keychain {
                    Button(L10n.text("从钥匙串读取")) { loadFromKeychain() }
                        .disabled(loadingCredentials || !initialized)
                }
                Spacer()
                Button(L10n.text("取消")) { dismiss() }.disabled(loadingCredentials)
                Button(L10n.text("保存并加载")) { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!initialized || loadingCredentials || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
        .task { await initialize() }
    }

    private func initialize() async {
        let makeStore = makeStore
        do {
            storage = try await Task.detached { try makeStore().preferredStorage() }.value
            guard !Task.isCancelled else { return }
            initialized = true
            if storage == .keychain, let saved = initialCredentials, saved.storage == .keychain { fill(saved) }
            else if let saved = try await Task.detached(operation: { try makeStore().load() }).value {
                guard !Task.isCancelled else { return }
                storage = saved.storage
                fill(saved)
            }
        } catch { show(error) }
    }

    private func save() {
        let credentials = AMapCredentials(key: key.trimmingCharacters(in: .whitespacesAndNewlines),
                                          securityJsCode: code.trimmingCharacters(in: .whitespacesAndNewlines), storage: storage)
        loadingCredentials = true
        error = nil
        let makeStore = makeStore
        Task {
            defer { loadingCredentials = false }
            do {
                try await Task.detached { try makeStore().save(credentials) }.value
                onSave(credentials)
                dismiss()
            } catch { show(error) }
        }
    }

    private func fill(_ credentials: AMapCredentials) {
        key = credentials.key
        code = credentials.securityJsCode
    }

    private func show(_ failure: Error) {
        error = failure is AMapCredentials.KeychainError ? failure.localizedDescription
            : L10n.text("本地高德凭据读写失败，原文件已保留。%1$@", failure.localizedDescription)
    }

    private func useLocalStorage() {
        if !key.isEmpty && !code.isEmpty { storage = .local }
        else { loadFromKeychain(migrate: true) }
    }

    private func loadFromKeychain(migrate: Bool = false) {
        loadingCredentials = true
        error = nil
        let makeStore = makeStore
        Task {
            defer { loadingCredentials = false }
            do {
                guard let saved = try await Task.detached(operation: { try makeStore().readKeychain(true) }).value else {
                    error = L10n.text("钥匙串中未找到高德凭据。")
                    return
                }
                fill(saved)
                if migrate { storage = .local }
            } catch { show(error) }
        }
    }
}
