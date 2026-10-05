import Foundation
import SQLite3

/// Resolves a usable bearer token for an OpenAI-compatible endpoint.
///
/// The app must not ship a hardcoded gateway secret: 9router rotates its keys
/// (and a stale literal was the reason chat returned `invalid_api_key` while
/// "Tes Koneksi" still looked green, because `/v1/models` answers 200 for any
/// caller). Resolution order:
///
/// 1. A key the user typed in Settings, when it looks like a real token.
/// 2. The live key from the local 9router database (`~/.9router/db/data.sqlite`,
///    `apiKeys` where `isActive = 1`). Also covers VansRouter, which shares it.
/// 3. A gateway key exported in `~/.hermes/.env` (used when 9router is remote).
/// 4. `nil` — the caller then sends no Authorization header at all, which is
///    exactly what Ollama and LM Studio want.
enum AIKeyResolver {

    private static let gatewayDBPath = "~/.9router/db/data.sqlite"
    private static let hermesEnvPath = "~/.hermes/.env"

    /// A stored value that is empty, or is literally one of our own UserDefaults
    /// key names (a `resetToDefaults()` bug once persisted that), is not a token.
    static func isPlausibleToken(_ value: String?) -> Bool {
        guard let value else { return false }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 12, !trimmed.contains(" ") else { return false }
        guard !trimmed.hasPrefix("settings."), !trimmed.hasPrefix("«") else { return false }
        return true
    }

    /// Best available key for `baseURL`, or nil for endpoints that need none.
    static func resolve(baseURL: String, storedKey: String?) -> String? {
        // Local gateways rotate their keys in place, so the live one from the
        // shared 9router database wins over whatever was persisted earlier.
        if isLocalGateway(baseURL), let live = liveGatewayKey() {
            return live
        }
        if isPlausibleToken(storedKey) {
            return storedKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let env = hermesEnvKey() {
            return env
        }
        return nil
    }

    /// Key the app should persist after a request fails with 401 so the next
    /// launch starts from a known-good value instead of the stale literal.
    static func liveGatewayKey() -> String? {
        let path = (gatewayDBPath as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: path) else { return nil }

        var handle: OpaquePointer?
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let handle
        else {
            if handle != nil { sqlite3_close(handle) }
            return nil
        }
        defer { sqlite3_close(handle) }

        let sql = "SELECT key FROM apiKeys WHERE isActive = 1 AND length(key) > 8 ORDER BY createdAt DESC LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else { return nil }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW,
              let raw = sqlite3_column_text(statement, 0)
        else { return nil }

        let value = String(cString: raw)
        return isPlausibleToken(value) ? value : nil
    }

    private static func hermesEnvKey() -> String? {
        let path = (hermesEnvPath as NSString).expandingTildeInPath
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        for line in contents.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            guard name == "HERMES_CUSTOM_9ROUTER_API_KEY" || name == "NILAIKINERJA_AI_KEY" else { continue }
            let value = parts[1].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if isPlausibleToken(value) { return value }
        }
        return nil
    }

    private static func isLocalGateway(_ baseURL: String) -> Bool {
        let lowered = baseURL.lowercased()
        return lowered.contains("localhost") || lowered.contains("127.0.0.1") || lowered.contains("0.0.0.0")
    }
}