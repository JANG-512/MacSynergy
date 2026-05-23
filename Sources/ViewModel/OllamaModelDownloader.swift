import Foundation

class OllamaModelDownloader: ObservableObject {
    @Published var progress: Double = 0.0
    @Published var statusText: String = "Idle"
    @Published var isDownloading: Bool = false
    
    private var activeTask: Task<Void, Never>?
    private let ollamaBase = "http://localhost:11434"

    /// Pulls a model from local Ollama in a background stream task.
    func pullModel(name: String, onComplete: @escaping (Bool, String) -> Void) {
        cancel()
        
        isDownloading = true
        progress = 0.0
        statusText = "Starting download..."
        
        activeTask = Task {
            guard let url = URL(string: "\(ollamaBase)/api/pull") else {
                await finish(success: false, message: "Invalid Ollama endpoint URL.", callback: onComplete)
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 600.0 // Allow up to 10 min for big downloads
            
            let body: [String: Any] = ["name": name, "stream": true]
            guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
                await finish(success: false, message: "Failed to serialize request body.", callback: onComplete)
                return
            }
            request.httpBody = bodyData
            
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? 500
                    await finish(success: false, message: "Ollama returned HTTP status \(code).", callback: onComplete)
                    return
                }
                
                for try await line in bytes.lines {
                    guard let data = line.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        continue
                    }
                    
                    let status = json["status"] as? String ?? ""
                    let total = json["total"] as? Double ?? 0.0
                    let completed = json["completed"] as? Double ?? 0.0
                    
                    await MainActor.run {
                        self.statusText = status
                        if total > 0 {
                            // Calculate layer progress
                            let pct = completed / total
                            self.progress = pct
                        } else if status == "success" {
                            self.progress = 1.0
                        }
                    }
                    
                    if status == "success" {
                        await finish(success: true, message: "Model successfully pulled!", callback: onComplete)
                        return
                    }
                }
                
                // If it finished without explicit "success" status but lines ended, check if done
                await finish(success: true, message: "Download completed.", callback: onComplete)
            } catch {
                await finish(success: false, message: "Error downloading: \(error.localizedDescription)", callback: onComplete)
            }
        }
    }
    
    func cancel() {
        activeTask?.cancel()
        activeTask = nil
        isDownloading = false
        progress = 0.0
        statusText = "Cancelled"
    }
    
    @MainActor
    private func finish(success: Bool, message: String, callback: @escaping (Bool, String) -> Void) {
        isDownloading = false
        if success {
            progress = 1.0
            statusText = "Success"
        } else {
            statusText = "Failed: \(message)"
        }
        callback(success, message)
    }
}
