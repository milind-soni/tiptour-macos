//
//  KeychainStore.swift
//  TipTour
//
//  Minimal Keychain helper for storing sensitive strings (like API keys)
//  that shouldn't live in UserDefaults. Uses kSecClassGenericPassword —
//  the standard macOS pattern for service-scoped secrets.
//
//  Scoped to TipTour's bundle identifier so the entries are isolated
//  from anything else on the system and auto-cleaned when the app is
//  uninstalled. No iCloud sync — these are device-local keys only.
//

import Foundation
import Security

enum KeychainStore {

    private static let serviceName: String = Bundle.main.bundleIdentifier ?? "com.milindsoni.tiptour"

    /// Write (or overwrite) a UTF-8 string for the given key. Returns
    /// true on success. Empty / whitespace-only input is treated as a
    /// delete so callers can implement "clear the key" as just writing
    /// an empty string.
    @discardableResult
    static func set(_ value: String, forKey key: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return delete(forKey: key)
        }
        guard let data = trimmed.data(using: .utf8) else { return false }

        // Baseline query: find the existing item (if any).
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]

        let updateAttributes: [String: Any] = [
            kSecValueData as String: data
        ]

        // Try update first; if the item doesn't exist, fall through to add.
        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }

        // Either no existing item or update failed — try to add fresh.
        var addQuery = query
        addQuery[kSecValueData as String] = data
        // Only accessible after the device has been unlocked (standard
        // behavior for a Mac app — keys shouldn't leak to background
        // processes on a locked machine).
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        return addStatus == errSecSuccess
    }

    /// Read the stored UTF-8 string for the given key. Returns nil if
    /// nothing was ever stored, or if the item exists but isn't valid
    /// UTF-8 (shouldn't happen for keys written via `set`).
    static func get(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    /// Delete the item for the given key. Returns true if deleted OR
    /// if there was nothing to delete (either is "success" from the
    /// caller's perspective — the key is gone).
    @discardableResult
    static func delete(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    // MARK: - TipTour-specific keys

    /// Gemini API key the user has pasted directly into the app.
    /// Source builds require this local Keychain key. Distributed
    /// builds may optionally fall back to a configured Worker proxy.
    static var geminiAPIKey: String? {
        get { get(forKey: "geminiAPIKey") }
        set { set(newValue ?? "", forKey: "geminiAPIKey") }
    }

    /// Anthropic API key used by the text command planner when Hermes is off.
    static var claudeAPIKey: String? {
        get { get(forKey: "claudeAPIKey") }
        set { set(newValue ?? "", forKey: "claudeAPIKey") }
    }

    /// OpenRouter API key used for optional follow-along video/context enrichment.
    static var openRouterAPIKey: String? {
        get { get(forKey: "openRouterAPIKey") }
        set { set(newValue ?? "", forKey: "openRouterAPIKey") }
    }

}
