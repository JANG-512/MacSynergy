import Foundation
import Combine

/// Manages Ollama process lifecycle to save battery.
///
/// Strategy:
/// - When a local generation starts → notifyActivity() keeps the model loaded.
/// - After `idleTimeout` seconds of no activity → automatically unloads the model from VRAM/RAM.
/// - Next generation request → ensureModelLoaded() warms it up again before streaming.
class OllamaLifecycleManager: ObservableObject {
    enum OllamaState: String {
        case unknown    = "Unknown"
        case loading    = "Loading…"
        case loaded     = "Loaded"
        case unloading  = "Unloading…"
        case unloaded   = "Unloaded"
        case error      = "Error"
    }

    @Published private(set) var state: OllamaState = .unknown
    @Published private(set) var modelName: String = ""

    /// Seconds of inactivity before the model is auto-unloaded. Default: 5 min.
    var idleTimeout: TimeInterval = 300

    private var idleTimer: AnyCancellable?
    private let ollamaBase = "http://localhost:11434"

    // MARK: - Public API

    /// Call before every local generation. Ensures the model is warm.
    func ensureModelLoaded(_ model: String) async {
        modelName = model
        cancelIdleTimer()

        if state == .loaded { return }

        state = .loading
        do {
            try await warmUpModel(model)
            state = .loaded
        } catch {
            state = .error
        }
    }

    /// Call after a local generation completes (or fails). Starts the idle countdown.
    func notifyGenerationFinished() {
        startIdleTimer()
    }

    /// Immediately unload the model (e.g., when the user switches to Cloud mode).
    func unloadNow() async {
        cancelIdleTimer()
        await performUnload()
    }

    /// Check if Ollama daemon is reachable at all.
    func checkDaemon() async -> Bool {
        guard let url = URL(string: "\(ollamaBase)/api/tags") else { return false }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Private helpers

    /// Warms up the model by sending a tiny keep-alive request.
    private func warmUpModel(_ model: String) async throws {
        guard let url = URL(string: "\(ollamaBase)/api/chat") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 60

        // keep_alive: -1 means "keep indefinitely until we explicitly unload"
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": "hi"]],
            "stream": false,
            "keep_alive": -1
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "Ollama", code: 500, userInfo: nil)
        }
    }

    /// Sends keep_alive: 0 to immediately evict the model from memory.
    private func performUnload() async {
        guard !modelName.isEmpty else { return }
        state = .unloading
        defer { state = .unloaded }

        guard let url = URL(string: "\(ollamaBase)/api/chat") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 10

        let body: [String: Any] = [
            "model": modelName,
            "messages": [],
            "keep_alive": 0   // evict immediately
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: req)
    }

    // MARK: - Idle timer

    private func startIdleTimer() {
        cancelIdleTimer()
        idleTimer = Just(())
            .delay(for: .seconds(idleTimeout), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                Task { await self.performUnload() }
            }
    }

    private func cancelIdleTimer() {
        idleTimer?.cancel()
        idleTimer = nil
    }
}
