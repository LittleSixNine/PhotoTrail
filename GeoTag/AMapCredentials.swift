import Security
import SwiftUI

struct AMapCredentials: Codable {
    let key: String
    let securityJsCode: String

    private static let service = "local.GeoTagCN.AMap"
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "js-api"]
    }

    static func load() throws -> Self? {
        var query = Self.query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError(status: status)
        }
        return try JSONDecoder().decode(Self.self, from: data)
    }

    func save() throws {
        let data = try JSONEncoder().encode(self)
        let values = [kSecValueData as String: data]
        let status = SecItemUpdate(Self.query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var item = Self.query
            item[kSecValueData as String] = data
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw KeychainError(status: added) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "无法访问高德凭据的钥匙串记录（\(status)）。" }
    }
}

struct AMapSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var code = ""
    @State private var error: String?
    let onSave: (AMapCredentials) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("高德地图设置").font(.title2)
            Text("填写你自己的 Web 端（JS API）凭据，仅保存在本机钥匙串。")
            SecureField("JS API Key", text: $key)
            SecureField("安全密钥 securityJsCode", text: $code)
            Text("此版本用于自用开发验证。加载后，显示照片和校验选点会向高德发送经纬度；照片文件留在本机。")
                .font(.footnote).foregroundStyle(.secondary)
            Link("高德安全密钥说明", destination:
                    URL(string: "https://lbs.amap.com/api/javascript-api-v2/guide/abc/jscode")!)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存并加载") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
        .task {
            do {
                if let saved = try AMapCredentials.load() {
                    key = saved.key
                    code = saved.securityJsCode
                }
            } catch { self.error = error.localizedDescription }
        }
    }

    private func save() {
        let credentials = AMapCredentials(key: key.trimmingCharacters(in: .whitespacesAndNewlines),
                                          securityJsCode: code.trimmingCharacters(in: .whitespacesAndNewlines))
        do {
            try credentials.save()
            onSave(credentials)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
