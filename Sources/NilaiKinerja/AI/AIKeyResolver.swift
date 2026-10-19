import Foundation
import SQLite3

/// Resolves a usable bearer token for an OpenAI-compatible endpoint.
///
/// The app does not ship hardcoded secrets. Resolution order:
/// 1. A key the user typed in Settings.
/// 2. Standard environment variables (`NILAIKINERJA_AI_KEY` or `OPENAI_API_KEY`).
/// 3. The live key from a local gateway database (`~/.9router/db/data.sqlite`) if running locally.
/// 4. `nil` — no Authorization header is sent (ideal for local runners like Ollama or LM Studio).
enum AIKeyResolver {

    private static let gatewayDBPath = "~/.9router/db/data.sqlite"

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
        if isPlausibleToken(storedKey) {
            return storedKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let env = environmentKey() {
            return env
        }
        if isLocalGateway(baseURL), let live = liveGatewayKey() {
            return live
        }
        return nil
    }

    /// Checks standard environment variables for an API key.
    private static func environmentKey() -> String? {
        if let env = ProcessInfo.processInfo.environment["NILAIKINERJA_AI_KEY"], isPlausibleToken(env) {
            return env
        }
        if let env = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], isPlausibleToken(env) {
            return env
        }
        return nil
    }

    /// Key the app can read from a local gateway database if present.
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

    private static func isLocalGateway(_ baseURL: String) -> Bool {
        let lowered = baseURL.lowercased()
        return lowered.contains("localhost") || lowered.contains("127.0.0.1") || lowered.contains("0.0.0.0")
    }
}