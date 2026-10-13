/*
 * YunXiOS - 云析 iOS 版
 * 移植自 YunX (AGPL-3.0)。
 *
 * 本文件：凭证加密存储（对应 data/security/CredentialCipher.kt + 账号 Dao 加密装饰器）。
 * iOS 侧使用 Keychain 存密钥、AES-GCM 加密落盘，保障 Cookie / JWT 不裸存。
 */

import Foundation
import CryptoKit
import Security

enum CredentialStore {

    private static let keyAccount = "com.yunx.app.ios.credential.key"
    private static let service = "com.yunx.app.ios"

    /// 获取（或首次生成）本机加密主密钥
    private static func masterKey() -> SymmetricKey {
        if let existing = readKeychainData(keyAccount), existing.count == 32 {
            return SymmetricKey(data: existing)
        }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        writeKeychainData(keyAccount, data)
        return key
    }

    /// 加密（AES-GCM，返回 base64(nonce + ciphertext + tag)）
    static func encrypt(_ plaintext: String, purpose: String) -> String {
        guard let data = plaintext.data(using: .utf8) else { return "" }
        let key = deriveKey(purpose: purpose)
        do {
            let sealed = try AES.GCM.seal(data, using: key)
            guard let combined = sealed.combined else { return "" }
            return combined.base64EncodedString()
        } catch {
            return ""
        }
    }

    /// 解密
    static func decrypt(_ ciphertext: String, purpose: String) -> String? {
        guard let data = Data(base64Encoded: ciphertext) else { return nil }
        let key = deriveKey(purpose: purpose)
        do {
            let box = try AES.GCM.SealedBox(combined: data)
            let opened = try AES.GCM.open(box, using: key)
            return String(data: opened, encoding: .utf8)
        } catch {
            return nil
        }
    }

    /// 由主密钥 + 用途派生密钥（HKDF），不同用途互不通用
    private static func deriveKey(purpose: String) -> SymmetricKey {
        let master = masterKey()
        let info = Data(purpose.utf8)
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: master,
            salt: Data("yunx-ios-salt".utf8),
            info: info,
            outputByteCount: 32
        )
    }

    // MARK: - Keychain 基础读写

    private static func readKeychainData(_ account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    @discardableResult
    private static func writeKeychainData(_ account: String, _ data: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(attributes as CFDictionary, nil)
        return status == errSecSuccess
    }

    static func deleteKeychainData(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
