import Foundation
import Security
import CryptoKit

struct ChatSession: Codable, Identifiable, Hashable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    let createdAt: Date
    var updatedAt: Date
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: ChatSession, rhs: ChatSession) -> Bool {
        return lhs.id == rhs.id
    }
}

struct KeychainHelper {
    static let service = "com.antigravity.MacSynergy"
    static let account = "history_key"
    
    /// Retrieves the existing 256-bit symmetric encryption key from the macOS Keychain or generates a new one.
    static func getOrGenerateKey() -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        if status == errSecSuccess, let data = dataTypeRef as? Data {
            return SymmetricKey(data: data)
        }
        
        // Key not found in Keychain; generate a fresh 256-bit cryptographic symmetric key
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            print("⚠️ Warning: Failed to save encryption key to Keychain: \(addStatus)")
        }
        
        return newKey
    }
}

struct EncryptedHistoryManager {
    /// Encrypts and writes the chat sessions securely to a local file.
    static func saveSessions(_ sessions: [ChatSession]) {
        do {
            let data = try JSONEncoder().encode(sessions)
            let key = KeychainHelper.getOrGenerateKey()
            
            // Seal data using AES-GCM encryption
            let sealedBox = try AES.GCM.seal(data, using: key)
            
            if let encryptedData = sealedBox.combined {
                let fileURL = getSessionsFileURL()
                try encryptedData.write(to: fileURL, options: .atomic)
            }
        } catch {
            print("❌ Failed to save encrypted chat sessions: \(error)")
        }
    }
    
    /// Reads and decrypts the chat sessions list from the local encrypted file.
    static func loadSessions() -> [ChatSession] {
        let fileURL = getSessionsFileURL()
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        
        do {
            let encryptedData = try Data(contentsOf: fileURL)
            let key = KeychainHelper.getOrGenerateKey()
            
            // Decrypt the AES-GCM package
            let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
            let decryptedData = try AES.GCM.open(sealedBox, using: key)
            
            let sessions = try JSONDecoder().decode([ChatSession].self, from: decryptedData)
            return sessions.sorted(by: { $0.updatedAt > $1.updatedAt })
        } catch {
            print("❌ Failed to load or decrypt chat sessions (re-initializing empty): \(error)")
            try? FileManager.default.removeItem(at: fileURL)
            return []
        }
    }
    
    /// Safe location directory for secure user application support storage
    private static func getSessionsFileURL() -> URL {
        let fileManager = FileManager.default
        let appSupportURLs = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupportURL = appSupportURLs.first ?? fileManager.temporaryDirectory
        let folderURL = appSupportURL.appendingPathComponent("MacSynergy", isDirectory: true)
        
        if !fileManager.fileExists(atPath: folderURL.path) {
            try? fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
        }
        
        return folderURL.appendingPathComponent("sessions.enc")
    }
}
