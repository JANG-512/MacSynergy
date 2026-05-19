import Foundation

struct ChatMessage: Codable, Identifiable {
    let id: UUID
    let role: String        // "user", "assistant", or "model"
    let content: String     // full content sent to AI (may include system directives)
    let displayContent: String? // user-visible label (stripped of system prompts)
    let engine: AIEngine    // which engine generated this message (for label display)

    init(role: String, content: String, displayContent: String? = nil, engine: AIEngine = .local) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.displayContent = displayContent
        self.engine = engine
    }

    /// Clean text to show in conversation history UI
    var visibleContent: String { displayContent ?? content }

    private enum CodingKeys: String, CodingKey {
        case id, role, content, displayContent, engine
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.role = try container.decode(String.self, forKey: .role)
        self.content = try container.decode(String.self, forKey: .content)
        self.displayContent = try? container.decode(String.self, forKey: .displayContent)
        self.engine = (try? container.decode(AIEngine.self, forKey: .engine)) ?? .local
    }
}

class HybridAIService {
    private let ollamaChatEndpoint = "http://localhost:11434/api/chat"

    // MARK: - Local Ollama Streaming

    func generateLocalStream(
        history: [ChatMessage],
        systemInstruction: String? = nil,
        model: String = "exaone3.5:7.8b"
    ) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                guard let url = URL(string: self.ollamaChatEndpoint) else {
                    continuation.finish(throwing: NSError(
                        domain: "HybridAIService", code: 400,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid Local Ollama URL endpoint."]
                    ))
                    return
                }

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 120.0

                var messagesJson = history.map { [
                    "role": $0.role == "user" ? "user" : ($0.role == "system" ? "system" : "assistant"),
                    "content": $0.content
                ] }

                if let system = systemInstruction {
                    messagesJson.insert(["role": "system", "content": system], at: 0)
                }

                let body: [String: Any] = ["model": model, "messages": messagesJson, "stream": true]

                do {
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        let code = (response as? HTTPURLResponse)?.statusCode ?? 500
                        continuation.finish(throwing: NSError(
                            domain: "HybridAIService", code: code,
                            userInfo: [NSLocalizedDescriptionKey: "Ollama returned HTTP \(code)."]
                        ))
                        return
                    }

                    for try await line in bytes.lines {
                        guard let data = line.data(using: .utf8) else { continue }
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let message = json["message"] as? [String: Any],
                           let token = message["content"] as? String {
                            continuation.yield(token)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Cloud Gemini Streaming (SSE)

    func generateCloudStream(
        history: [ChatMessage],
        systemInstruction: String? = nil,
        apiKey: String,
        model: String = "gemini-2.0-flash"
    ) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                guard !apiKey.isEmpty else {
                    continuation.finish(throwing: NSError(
                        domain: "HybridAIService", code: 401,
                        userInfo: [NSLocalizedDescriptionKey: "Cloud API Key is empty. Please enter your Gemini API Key."]
                    ))
                    return
                }

                let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):streamGenerateContent?alt=sse&key=\(apiKey)"
                guard let url = URL(string: urlString) else {
                    continuation.finish(throwing: NSError(
                        domain: "HybridAIService", code: 400,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid Cloud API URL path."]
                    ))
                    return
                }

                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 120.0

                let contentsJson = history.map { [
                    "role": $0.role == "user" ? "user" : "model",
                    "parts": [["text": $0.content]]
                ] }

                var requestBody: [String: Any] = ["contents": contentsJson]
                if let system = systemInstruction {
                    requestBody["systemInstruction"] = ["parts": [["text": system]]]
                }

                do {
                    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        let code = (response as? HTTPURLResponse)?.statusCode ?? 500
                        continuation.finish(throwing: NSError(
                            domain: "HybridAIService", code: code,
                            userInfo: [NSLocalizedDescriptionKey: "Gemini API returned HTTP \(code)."]
                        ))
                        return
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonStr = String(line.dropFirst(6))
                        guard let data = jsonStr.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let candidates = json["candidates"] as? [[String: Any]],
                              let first = candidates.first,
                              let content = first["content"] as? [String: Any],
                              let parts = content["parts"] as? [[String: Any]],
                              let text = parts.first?["text"] as? String else { continue }
                        continuation.yield(text)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Cloud Gemini Batch (used by Ultimate Mode synthesis)

    func generateCloudResponse(
        history: [ChatMessage],
        systemInstruction: String? = nil,
        apiKey: String,
        model: String = "gemini-2.0-flash"
    ) async throws -> String {
        guard !apiKey.isEmpty else {
            throw NSError(domain: "HybridAIService", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "Cloud API Key is empty."])
        }

        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "HybridAIService", code: 400,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid Cloud API URL path."])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120.0

        let contentsJson = history.map { [
            "role": $0.role == "user" ? "user" : "model",
            "parts": [["text": $0.content]]
        ] }

        var requestBody: [String: Any] = ["contents": contentsJson]
        if let system = systemInstruction {
            requestBody["systemInstruction"] = ["parts": [["text": system]]]
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 500
            let errorMsg: String
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorDetails = errorJson["error"] as? [String: Any],
               let message = errorDetails["message"] as? String {
                errorMsg = message
            } else {
                errorMsg = "HTTP Status Code \(code)"
            }
            throw NSError(domain: "HybridAIService", code: code,
                          userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let firstCandidate = candidates.first,
              let content = firstCandidate["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw NSError(domain: "HybridAIService", code: 500,
                          userInfo: [NSLocalizedDescriptionKey: "Unparseable JSON from Cloud API."])
        }

        return text
    }
}
