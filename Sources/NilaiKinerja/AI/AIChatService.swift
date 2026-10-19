import Foundation
import Combine

/// A chat message exchanged in the notch AI assistant.
struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    enum Role: String {
        case user
        case assistant
        case system
    }
    var role: Role
    var content: String
    var isThinking: Bool = false
    var thinkingContent: String = ""
    var createdAt: Date = Date()

    static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id &&
        lhs.role == rhs.role &&
        lhs.content == rhs.content &&
        lhs.isThinking == rhs.isThinking &&
        lhs.thinkingContent == rhs.thinkingContent
    }
}

/// Service that coordinates streaming chat completions and model discovery with any
/// OpenAI-compatible endpoint (9router, VansRouter, ZeroKey, Ollama, LM Studio, or cloud OpenAI).
@MainActor
final class AIChatService: ObservableObject {
    static let shared = AIChatService()

    @Published var messages: [ChatMessage] = []
    @Published var isStreaming: Bool = false
    @Published var availableModels: [String] = []
    @Published var isFetchingModels: Bool = false
    @Published var statusInfo: String?
    @Published var errorMessage: String?

    /// Set by the settings screen so a successful probe can persist the key that
    /// actually worked, replacing a stale literal on the next launch.
    var onResolvedKey: ((String) -> Void)?

    private var currentTask: Task<Void, Never>?

    // MARK: - Normalization

    static func normalizeBaseURL(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        if trimmed.isEmpty { return "http://localhost:11434/v1" }
        return trimmed
    }

    private func completionsURL(for baseURL: String) -> URL? {
        let base = Self.normalizeBaseURL(baseURL)
        let endpoint = base.hasSuffix("/v1") ? "\(base)/chat/completions" : "\(base)/v1/chat/completions"
        return URL(string: endpoint)
    }

    private func modelsURL(for baseURL: String) -> URL? {
        let base = Self.normalizeBaseURL(baseURL)
        let endpoint = base.hasSuffix("/v1") ? "\(base)/models" : "\(base)/v1/models"
        return URL(string: endpoint)
    }

    // MARK: - Model Discovery

    func fetchModels(baseURL: String, storedKey: String?) async {
        let apiKey = AIKeyResolver.resolve(baseURL: baseURL, storedKey: storedKey)
        guard let url = modelsURL(for: baseURL) else {
            errorMessage = "URL endpoint tidak valid"
            statusInfo = nil
            return
        }

        isFetchingModels = true
        errorMessage = nil
        statusInfo = nil
        defer { isFetchingModels = false }

        var req = URLRequest(url: url, timeoutInterval: 15)
        if let apiKey {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                errorMessage = "Gagal menghubungi endpoint"
                statusInfo = nil
                return
            }

            guard http.statusCode == 200 else {
                errorMessage = "HTTP \(http.statusCode): Gagal mengambil daftar model"
                statusInfo = nil
                return
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let list = json["data"] as? [[String: Any]] else {
                errorMessage = "Format respons JSON /models tidak sesuai"
                statusInfo = nil
                return
            }

            let excluded = ["embed", "bge-", "all-minilm", "clip", "rerank", "t2v"]
            let ids = list.compactMap { item -> String? in
                guard let id = item["id"] as? String else { return nil }
                let lower = id.lowercased()
                if excluded.contains(where: { lower.contains($0) }) { return nil }
                return id
            }

            self.availableModels = ids
            self.statusInfo = "✓ Terhubung (\(ids.count) model tersedia)"
        } catch {
            self.errorMessage = "Koneksi gagal: \(error.localizedDescription)"
            self.statusInfo = nil
        }
    }

    // MARK: - Streaming Chat

    func sendMessage(
            _ text: String,
            baseURL: String,
            storedKey: String?,
            model: String,
            systemPrompt: String = """
            Kamu adalah Asisten AI eksekutif di MacBook Notch (NilaiKinerja). Jawab dalam format Markdown yang rapi, terstruktur, dan mudah dibaca:
            - Gunakan heading (### untuk sub-judul) agar tidak menumpuk.
            - Gunakan bullet points (- ) atau penomoran (1. ) untuk poin-poin dan rincian langkah kerja.
            - Cetak tebal (**kata kunci**) pada istilah, angka, atau intisari penting.
            - Gunakan blok kode (```bahasa ... ```) untuk sintaks perintah terminal, kode program, atau template teks formal.
            - Berikan jawaban yang ringkas, solutif, to the point, dan langsung dapat dieksekusi untuk pekerjaan ASN maupun teknis/pemrograman.
            """
        ) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !isStreaming else { return }

            guard let url = completionsURL(for: baseURL) else {
                errorMessage = "URL endpoint tidak valid"
                return
            }

            // Add user message
            messages.append(ChatMessage(role: .user, content: trimmed))

            // Placeholder assistant message
            messages.append(ChatMessage(role: .assistant, content: "", isThinking: true))
            isStreaming = true
            errorMessage = nil
            statusInfo = nil

            // History snapshot: the assistant placeholder is the last message.
            let history: [[String: String]] = [messages.dropLast()].compactMap { slice in
                slice.map { ["role": $0.role.rawValue, "content": $0.content] }
            }.first ?? []

            let selectedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
            let payloadMessages: [[String: String]] =
                [["role": "system", "content": systemPrompt]] + history

            let body: [String: Any] = [
                "model": selectedModel.isEmpty ? "llama3" : selectedModel,
                "messages": payloadMessages,
                "stream": true,
                "temperature": 0.7
            ]

            guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
                errorMessage = "Gagal memproses data pesan"
                messages.removeLast()
                isStreaming = false
                return
            }

            // Candidate keys in priority order. A stale stored literal must not
            // block a fresh gateway key from working.
            var candidates: [String] = []
            if let resolved = AIKeyResolver.resolve(baseURL: baseURL, storedKey: storedKey) {
                candidates.append(resolved)
            }
            if let live = AIKeyResolver.liveGatewayKey(), !candidates.contains(live) {
                candidates.append(live)
            }

            currentTask?.cancel()
            currentTask = Task {
                var lastError: String?

                if candidates.isEmpty {
                    let outcome = await stream(url: url, bodyData: bodyData, apiKey: nil)
                    if case .success = outcome {
                        self.finishStreaming(success: true)
                    } else {
                        self.finishStreaming(success: false, message: "Gagal menghubungi \(baseURL)")
                    }
                    return
                }

                for key in candidates {
                    if Task.isCancelled { break }
                    let outcome = await stream(url: url, bodyData: bodyData, apiKey: key)
                    switch outcome {
                    case .success:
                        self.onResolvedKey?(key)
                        self.finishStreaming(success: true)
                        return
                    case .authFailed(let detail):
                        lastError = detail
                        continue
                    case .failure(let detail):
                        lastError = detail
                        break
                    }
                }

                self.finishStreaming(success: false, message: lastError ?? "Gagal menghubungi server AI")
            }
        }

        private enum StreamOutcome {
            case success
            case authFailed(String)
            case failure(String)
        }

        private func stream(url: URL, bodyData: Data, apiKey: String?) async -> StreamOutcome {
            var req = URLRequest(url: url, timeoutInterval: 120)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            if let apiKey {
                req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            req.httpBody = bodyData

            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: req)
                guard let http = response as? HTTPURLResponse else {
                    return .failure("Respons server tidak dikenali")
                }

                guard http.statusCode == 200 else {
                    let detail = "HTTP \(http.statusCode)"
                    var message = ""
                    for try await line in bytes.lines {
                        if line.isEmpty { continue }
                        if let data = line.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let errObj = json["error"] as? [String: Any],
                           let msg = errObj["message"] as? String {
                            message = msg
                        } else {
                            message += line
                        }
                        break
                    }
                    let combined = message.isEmpty ? detail : "\(detail): \(message)"
                    if http.statusCode == 401 || http.statusCode == 403 {
                        return .authFailed(combined)
                    }
                    return .failure(combined)
                }

                var fullContent = ""
                var fullThinking = ""

                for try await line in bytes.lines {
                    if Task.isCancelled { break }
                    let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard trimmedLine.hasPrefix("data:") else { continue }
                    let payload = trimmedLine.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
                    if payload == "[DONE]" { break }

                    guard let data = payload.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let choices = json["choices"] as? [[String: Any]],
                          let first = choices.first
                    else { continue }

                    // Some gateways stream the payload under `delta`, others under `message`.
                    if let delta = first["delta"] as? [String: Any] {
                        if let content = delta["content"] as? String { fullContent += content }
                        if let reasoning = delta["reasoning_content"] as? String { fullThinking += reasoning }
                        if let reasoning = delta["reasoning"] as? String { fullThinking += reasoning }
                    }
                    if let message = first["message"] as? [String: Any],
                       let content = message["content"] as? String {
                        fullContent += content
                    }

                    if let lastIdx = self.messages.indices.last {
                        self.messages[lastIdx].content = fullContent
                        self.messages[lastIdx].thinkingContent = fullThinking
                        self.messages[lastIdx].isThinking = fullContent.isEmpty
                    }
                }

                // Handle explicit <think>...</think> tags if model embeds reasoning inside content
                if fullContent.contains("<think>") {
                    if let endRange = fullContent.range(of: "</think>") {
                        let thinkPart = fullContent[..<endRange.upperBound]
                            .replacingOccurrences(of: "<think>", with: "")
                            .replacingOccurrences(of: "</think>", with: "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if fullThinking.isEmpty {
                            fullThinking = thinkPart
                        }
                        fullContent = String(fullContent[endRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }

                if let lastIdx = self.messages.indices.last {
                    self.messages[lastIdx].isThinking = false
                    if self.messages[lastIdx].content.isEmpty {
                        // A 200 with no usable payload: treat as a transport failure so
                        // the next candidate key gets a chance.
                        return .failure("Server tidak mengirim isi balasan")
                    }
                }
                return .success
            } catch {
                if Task.isCancelled { return .failure("Dibatalkan") }
                return .failure(error.localizedDescription)
            }
        }

        private func finishStreaming(success: Bool, message: String? = nil) {
            isStreaming = false
            if success {
                errorMessage = nil
            } else {
                errorMessage = message
                if let lastIdx = messages.indices.last, messages[lastIdx].content.isEmpty {
                    messages.remove(at: lastIdx)
                }
            }
        }

        /// Real end-to-end probe: a one-token chat completion. `/v1/models` answers
        /// 200 for any caller (9router does not authenticate there), so probing it
        /// only proves the port is open — not that chat will work.
        func testConnection(baseURL: String, storedKey: String?, model: String) async -> String {
            errorMessage = nil
            statusInfo = nil

            guard let url = completionsURL(for: baseURL) else {
                return "URL endpoint tidak valid"
            }

            var candidates: [String] = []
            if let resolved = AIKeyResolver.resolve(baseURL: baseURL, storedKey: storedKey) {
                candidates.append(resolved)
            }
            if let live = AIKeyResolver.liveGatewayKey(), !candidates.contains(live) {
                candidates.append(live)
            }

            let probeModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
            let body: [String: Any] = [
                "model": probeModel.isEmpty ? "llama3" : probeModel,
                "messages": [["role": "user", "content": "ping"]],
                "stream": false,
                "max_tokens": 8
            ]
            guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
                return "Gagal menyusun payload uji"
            }

            let attempts: [String?] = candidates.isEmpty ? [nil] : candidates.map { Optional($0) }
            var lastDetail = "Gagal menghubungi server"

            for key in attempts {
                var req = URLRequest(url: url, timeoutInterval: 20)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                if let key {
                    req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                }
                req.httpBody = bodyData

                do {
                    let (data, response) = try await URLSession.shared.data(for: req)
                    guard let http = response as? HTTPURLResponse else {
                        lastDetail = "Respons server tidak dikenali"
                        continue
                    }
                    if http.statusCode == 200 {
                        let text = String(data: data, encoding: .utf8) ?? ""
                        let ok = text.contains("choices")
                        if ok {
                            if let key { onResolvedKey?(key) }
                            let modelName = probeModel.isEmpty ? "llama3" : probeModel
                            statusInfo = "✓ Terhubung (\(modelName) siap)"
                            return "ok"
                        }
                        lastDetail = "Server merespons 200 tanpa payload chat"
                        continue
                    }
                    var detail = "HTTP \(http.statusCode)"
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errObj = json["error"] as? [String: Any],
                       let msg = errObj["message"] as? String {
                        detail = msg
                    }
                    lastDetail = detail
                } catch {
                    lastDetail = error.localizedDescription
                }
            }
            return lastDetail
        }

    func stopStreaming() {
        currentTask?.cancel()
        currentTask = nil
        isStreaming = false
        if let lastIdx = messages.indices.last, messages[lastIdx].content.isEmpty {
            messages.remove(at: lastIdx)
        }
    }

    func clearChat() {
        stopStreaming()
        messages.removeAll()
        errorMessage = nil
        statusInfo = nil
    }
}
