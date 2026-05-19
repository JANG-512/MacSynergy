import Foundation
import Combine
import NaturalLanguage
import AppKit

enum AIEngine: String, CaseIterable, Identifiable, Codable {
    case local = "Local (Ollama)"
    case cloud = "Cloud (Gemini)"
    var id: String { self.rawValue }
}

enum AIEngineMode: String, CaseIterable, Identifiable {
    case auto  = "Auto (Smart)"
    case local = "Local (Ollama)"
    case cloud = "Cloud (Gemini)"
    var id: String { self.rawValue }
}

class MacSynergyViewModel: ObservableObject {
    @Published var inputText: String = ""
    @Published var detectedLanguage: String = "--"
    @Published var languageFlag: String = "🌐"
    @Published var maskedText: String = ""
    @Published var isExpanded: Bool = false
    @Published var isUltimateMode: Bool = false

    // Ultimate Ensemble live split states
    @Published var ultimateLocalResponse: String = ""
    @Published var ultimateCloudResponse: String = ""
    @Published var showUltimateToast: Bool = false

    // Context awareness
    @Published var selectedContextText: String = ""

    // Conversational chat sessions – single save point via chatSessions.didSet
    @Published var chatSessions: [ChatSession] = [] {
        didSet { EncryptedHistoryManager.saveSessions(self.chatSessions) }
    }
    @Published var currentSessionId: UUID? = nil
    @Published var showSidebar: Bool = false

    @Published var conversationHistory: [ChatMessage] = [] {
        didSet {
            guard let currentId = currentSessionId,
                  let index = chatSessions.firstIndex(where: { $0.id == currentId }) else { return }
            chatSessions[index].messages = conversationHistory
            chatSessions[index].updatedAt = Date()
            // Auto-title from first user message
            if chatSessions[index].title == "New Session",
               let first = conversationHistory.first(where: { $0.role == "user" }) {
                let src = first.visibleContent.trimmingCharacters(in: .whitespacesAndNewlines)
                chatSessions[index].title = src.count > 25 ? String(src.prefix(22)) + "..." : src
            }
            // chatSessions.didSet handles the actual save — no extra call needed
        }
    }

    @Published var selectedEngineMode: AIEngineMode = .auto {
        didSet { updateEngineFromMode() }
    }

    @Published var showSettings: Bool = false
    @Published var hasMaskedPII: Bool = false

    @Published var selectedEngine: AIEngine = .local
    @Published var aiResponse: String = ""
    @Published var formattedMarkdown: AttributedString? = nil
    @Published var isLoading: Bool = false
    @Published var isGenerating: Bool = false
    @Published var errorMessage: String? = nil
    @Published var selectedAction: String? = nil
    @Published var showResponse: Bool = false
    @Published var apiKey: String = ""
    @Published var ollamaModel: String = "exaone3.5:7.8b"
    @Published var geminiModel: String = "gemini-3.1-flash-lite"

    private var cancellables = Set<AnyCancellable>()
    private let recognizer = NLLanguageRecognizer()
    private let hybridService = HybridAIService()

    init() {
        self.apiKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"]
            ?? UserDefaults.standard.string(forKey: "GEMINI_API_KEY") ?? ""
        self.ollamaModel = UserDefaults.standard.string(forKey: "OLLAMA_MODEL_NAME") ?? "exaone3.5:7.8b"
        self.geminiModel = UserDefaults.standard.string(forKey: "GEMINI_MODEL_NAME") ?? "gemini-3.1-flash-lite"

        self.chatSessions = EncryptedHistoryManager.loadSessions()
        if let first = self.chatSessions.first {
            self.currentSessionId = first.id
            self.conversationHistory = first.messages
        } else {
            let s = ChatSession(id: UUID(), title: "New Session", messages: [], createdAt: Date(), updatedAt: Date())
            self.chatSessions = [s]
            self.currentSessionId = s.id
        }

        NotificationCenter.default.publisher(for: .didReceiveSelectedText)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self = self,
                      let text = notification.object as? String else { return }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }

                self.selectedContextText = ""
                self.resetResponse()

                Task {
                    let masked = await self.maskPII(text: trimmed)
                    await MainActor.run {
                        self.selectedContextText = masked
                        self.hasMaskedPII = (trimmed != masked)
                        self.isExpanded = true
                        self.updateEngineFromMode()
                    }
                }
            }
            .store(in: &cancellables)

        $inputText
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] text in
                guard let self = self else { return }
                self.detectLanguage(for: text)
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                let shouldExpand = !trimmed.isEmpty
                    || !self.selectedContextText.isEmpty
                    || !self.conversationHistory.isEmpty
                    || self.isLoading || self.isGenerating || self.showResponse

                if shouldExpand {
                    self.isExpanded = true
                } else {
                    self.isExpanded = false
                    self.hasMaskedPII = false
                    self.resetResponse()
                }

                Task {
                    let masked = await self.maskPII(text: text)
                    await MainActor.run {
                        self.maskedText = masked
                        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        let m = masked.trimmingCharacters(in: .whitespacesAndNewlines)
                        let inputHasPII = !t.isEmpty && (t != m)
                        let ctxHasPII = !self.selectedContextText.isEmpty
                            && (self.selectedContextText.contains("[EMAIL]")
                                || self.selectedContextText.contains("[PHONE]")
                                || self.selectedContextText.contains("[NAME]"))
                        self.hasMaskedPII = inputHasPII || ctxHasPII
                        self.updateEngineFromMode()
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Persistence

    func saveAPIKey(_ key: String) {
        let t = key.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = t
        UserDefaults.standard.set(t, forKey: "GEMINI_API_KEY")
    }

    func saveOllamaModel(_ model: String) {
        let t = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        self.ollamaModel = t
        UserDefaults.standard.set(t, forKey: "OLLAMA_MODEL_NAME")
    }

    func saveGeminiModel(_ model: String) {
        let t = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        self.geminiModel = t
        UserDefaults.standard.set(t, forKey: "GEMINI_MODEL_NAME")
    }

    // MARK: - Engine Routing

    func cycleEngineMode() {
        switch selectedEngineMode {
        case .auto:  selectedEngineMode = .local
        case .local: selectedEngineMode = .cloud
        case .cloud: selectedEngineMode = .auto
        }
    }

    private func updateEngineFromMode() {
        switch selectedEngineMode {
        case .local: self.selectedEngine = .local
        case .cloud: self.selectedEngine = .cloud
        case .auto:  routeRequest(prompt: inputText, context: selectedContextText)
        }
    }

    func routeRequest(prompt: String, context: String) {
        guard selectedEngineMode == .auto else { return }
        let combined = (prompt + " " + context).lowercased()
        let words = combined.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let complex = ["analyze","write code","explain","code","분석","코드","설명","구현"]
        let simple  = ["translate","fix","grammar","summarize","번역","요약","교정","수정"]
        if words.count > 300 || complex.contains(where: { combined.contains($0) }) {
            self.selectedEngine = .cloud
        } else if simple.contains(where: { combined.contains($0) }) {
            self.selectedEngine = .local
        } else {
            self.selectedEngine = .local
        }
    }

    // MARK: - Submit

    @MainActor
    func submitCustomInstruction() async {
        let instruction = self.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty || !self.selectedContextText.isEmpty else { return }

        routeRequest(prompt: instruction, context: self.selectedContextText)

        self.selectedAction = "Custom Command"
        self.isLoading = true
        self.errorMessage = nil
        self.showResponse = true
        self.aiResponse = ""
        self.formattedMarkdown = nil

        // Build the full prompt sent to AI
        let finalPrompt: String
        if self.conversationHistory.isEmpty && !self.selectedContextText.isEmpty {
            finalPrompt = """
            [System Directive]
            You are a helpful hybrid macOS assistant. Process the [Text Context] below according to the [User Instruction].

            [User Instruction]
            \(instruction.isEmpty ? "Summarize or explain this text." : instruction)

            [Text Context]
            \(self.selectedContextText)
            """
        } else {
            finalPrompt = instruction.isEmpty ? "Summarize or explain this text." : instruction
        }

        // Display label: short user-readable version
        let displayText: String
        if !self.selectedContextText.isEmpty {
            let preview = self.selectedContextText.prefix(60)
            displayText = instruction.isEmpty
                ? "Summarize: \"\(preview)\"..."
                : "\(instruction) — \"\(preview)\"..."
        } else {
            displayText = instruction
        }

        self.inputText = ""

        if isUltimateMode {
            await executeUltimateMode(prompt: finalPrompt)
            return
        }

        self.conversationHistory.append(
            ChatMessage(role: "user", content: finalPrompt, displayContent: displayText)
        )
        await runAIGeneration()
    }

    @MainActor
    func submitPrompt(action: String) async {
        self.selectedAction = action
        self.isLoading = true
        self.errorMessage = nil
        self.showResponse = true
        self.aiResponse = ""
        self.formattedMarkdown = nil

        let basePayload = self.selectedContextText.isEmpty ? self.inputText : self.selectedContextText
        routeRequest(prompt: action, context: basePayload)
        self.inputText = ""

        let finalPrompt = PromptManager.generatePrompt(inputText: basePayload, action: action)
        let preview = basePayload.prefix(60)
        let displayText = "\(action): \"\(preview)\(basePayload.count > 60 ? "..." : "")\""

        if isUltimateMode {
            await executeUltimateMode(prompt: finalPrompt)
            return
        }

        self.conversationHistory.append(
            ChatMessage(role: "user", content: finalPrompt, displayContent: displayText)
        )
        await runAIGeneration()
    }

    @MainActor
    private func runAIGeneration() async {
        if selectedEngine == .local {
            self.isGenerating = true
            do {
                let stream = hybridService.generateLocalStream(
                    history: self.conversationHistory,
                    model: self.ollamaModel
                )
                var first = true
                for try await token in stream {
                    if first { self.isLoading = false; first = false }
                    self.aiResponse += token
                    updateMarkdown()
                }
                self.isLoading = false
                self.isGenerating = false
                self.conversationHistory.append(
                    ChatMessage(role: "assistant", content: self.aiResponse, engine: .local)
                )
            } catch {
                self.isLoading = false
                self.isGenerating = false
                self.errorMessage = """
                Local Ollama Connection Failure:

                1. Make sure Ollama is running on your Mac.
                2. Pull the model if needed:
                   $ ollama pull \(self.ollamaModel)

                Details: \(error.localizedDescription)
                """
            }
        } else {
            guard !self.apiKey.isEmpty else {
                self.isLoading = false
                self.errorMessage = "Cloud Gemini API Key is missing. Configure it in Settings (⚙)."
                return
            }
            self.isGenerating = true
            do {
                let stream = hybridService.generateCloudStream(
                    history: self.conversationHistory,
                    apiKey: self.apiKey,
                    model: self.geminiModel
                )
                var first = true
                for try await token in stream {
                    if first { self.isLoading = false; first = false }
                    self.aiResponse += token
                    updateMarkdown()
                }
                self.isLoading = false
                self.isGenerating = false
                self.conversationHistory.append(
                    ChatMessage(role: "model", content: self.aiResponse, engine: .cloud)
                )
            } catch {
                self.isLoading = false
                self.isGenerating = false
                self.errorMessage = "Cloud Gemini Error: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Quick Action (from Selection Overlay)

    @MainActor
    func executeQuickAction(_ action: QuickAction, selectedText: String, writePrompt: String? = nil) {
        self.selectedContextText = selectedText
        self.isExpanded = true
        self.showResponse = true
        self.aiResponse = ""
        self.formattedMarkdown = nil
        self.errorMessage = nil
        self.isLoading = true
        self.isGenerating = false

        // Route BEFORE building the prompt so Auto mode uses the actual content to decide
        routeRequest(prompt: action.promptPrefix + selectedText, context: selectedText)

        let preview = String(selectedText.prefix(50))
        let finalPrompt: String
        let displayText: String

        switch action {
        case .summarize:
            finalPrompt = action.promptPrefix + selectedText
            displayText = "요약: \"\(preview)\(selectedText.count > 50 ? "…" : "")\""
        case .translate:
            finalPrompt = action.promptPrefix + selectedText
            displayText = "번역: \"\(preview)\(selectedText.count > 50 ? "…" : "")\""
        case .rewrite:
            finalPrompt = action.promptPrefix + selectedText
            displayText = "다시쓰기: \"\(preview)\(selectedText.count > 50 ? "…" : "")\""
        case .analyze:
            finalPrompt = action.promptPrefix + selectedText
            displayText = "분석: \"\(preview)\(selectedText.count > 50 ? "…" : "")\""
        case .write:
            let userPrompt = writePrompt ?? "이 내용을 바탕으로 글을 써주세요"
            finalPrompt = "\(userPrompt)\n\n[참고 텍스트]:\n\(selectedText)"
            displayText = "글쓰기: \(userPrompt)"
        }

        conversationHistory.append(
            ChatMessage(role: "user", content: finalPrompt, displayContent: displayText)
        )

        Task {
            if isUltimateMode {
                await executeUltimateMode(prompt: finalPrompt)
            } else {
                await runAIGeneration()
            }
        }
    }

    // MARK: - Ultimate Mode

    @MainActor
    func executeUltimateMode(prompt: String) async {
        self.isLoading = false
        self.errorMessage = nil
        self.showResponse = true
        self.formattedMarkdown = nil
        self.ultimateLocalResponse = ""
        self.ultimateCloudResponse = ""
        self.showUltimateToast = false

        NotificationCenter.default.post(name: Notification.Name("ultimateHandoffDidStart"), object: nil)

        let localSys = """
        [ULTIMATE ENSEMBLE] You are the LOCAL AI (Ollama - \(self.ollamaModel)). Focus on technical depth and precise code. Skip pleasantries.
        """
        let cloudSys = """
        [ULTIMATE ENSEMBLE] You are the CLOUD AI (Gemini - \(self.geminiModel)). Focus on conceptual breadth and synthesis. Skip pleasantries.
        """

        do {
            async let localTask: String = {
                let stream = self.hybridService.generateLocalStream(
                    history: [ChatMessage(role: "user", content: prompt)],
                    systemInstruction: localSys,
                    model: self.ollamaModel
                )
                var text = ""
                for try await token in stream {
                    text += token
                    let c = text
                    await MainActor.run { self.ultimateLocalResponse = c }
                }
                if text.isEmpty {
                    throw NSError(domain: "OllamaError", code: 404,
                                  userInfo: [NSLocalizedDescriptionKey: "Empty response from Ollama."])
                }
                return text
            }()

            async let cloudTask: String = {
                guard !self.apiKey.isEmpty else {
                    throw NSError(domain: "GeminiError", code: 401,
                                  userInfo: [NSLocalizedDescriptionKey: "Cloud API Key is missing."])
                }
                let result = try await self.hybridService.generateCloudResponse(
                    history: [ChatMessage(role: "user", content: prompt)],
                    systemInstruction: cloudSys,
                    apiKey: self.apiKey,
                    model: self.geminiModel
                )
                await MainActor.run { self.ultimateCloudResponse = result }
                return result
            }()

            let (ollama, gemini) = try await (localTask, cloudTask)

            let synthesized = """
            I asked two AI assistants the same task.

            [Original Task]: \(prompt)
            [Assistant 1 – Local Ollama]: \(ollama)
            [Assistant 2 – Cloud Gemini]: \(gemini)

            Act as a senior reasoning model. Synthesize the best parts, correct hallucinations, and give the ultimate answer.
            """

            try await runChromeHandoffAppleScript(prompt: synthesized)
            self.showUltimateToast = true
            NotificationCenter.default.post(name: Notification.Name("ultimateHandoffDidComplete"), object: nil)
        } catch {
            self.isLoading = false
            self.errorMessage = "Ultimate Mode Error: \(error.localizedDescription)\n\n(Automation permission? System Settings → Privacy & Security → Automation → enable Google Chrome for MacSynergy.)"
            NotificationCenter.default.post(name: Notification.Name("ultimateHandoffDidComplete"), object: nil)
        }
    }

    private func runChromeHandoffAppleScript(prompt: String) async throws {
        let b64 = Data(prompt.utf8).base64EncodedString()
        let script = """
        tell application "Google Chrome"
            activate
            if (count of windows) is 0 then make new window
            set t to make new tab at end of tabs of window 1
            set URL of t to "https://chatgpt.com/"
            delay 3
            tell t
                execute javascript "(function(){const b='\(b64)';const p=new TextDecoder().decode(Uint8Array.from(atob(b),c=>c.charCodeAt(0)));function go(){const el=document.querySelector('#prompt-textarea')||document.querySelector('textarea')||document.querySelector('div[contenteditable=true]');if(!el)return false;el.tagName==='TEXTAREA'?el.value=p:el.innerText=p;el.dispatchEvent(new Event('input',{bubbles:true}));setTimeout(()=>{const b=document.querySelector('[data-testid=send-button]')||document.querySelector('form button');if(b)b.click();},500);return true;}if(!go()){let n=0;const t=setInterval(()=>{n++;if(go()||n>10)clearInterval(t);},500);}})();"
            end tell
        end tell
        """
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                var err: NSDictionary?
                guard let s = NSAppleScript(source: script) else {
                    continuation.resume(throwing: NSError(domain: "AppleScript", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey: "Failed to compile AppleScript."]))
                    return
                }
                s.executeAndReturnError(&err)
                if let e = err {
                    continuation.resume(throwing: NSError(domain: "AppleScript", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: e[NSAppleScript.errorMessage] as? String ?? e.description]))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Paste Back

    func triggerPasteBack() {
        guard !self.aiResponse.isEmpty else { return }
        NotificationCenter.default.post(name: .pasteBackToActiveApp, object: self.aiResponse)
    }

    // MARK: - Markdown

    private func updateMarkdown() {
        if let s = try? AttributedString(
            markdown: self.aiResponse,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) {
            self.formattedMarkdown = s
        } else {
            self.formattedMarkdown = AttributedString(self.aiResponse)
        }
    }

    // MARK: - Reset

    /// Resets UI state only — does NOT wipe conversationHistory.
    private func resetUI() {
        self.aiResponse = ""
        self.formattedMarkdown = nil
        self.isLoading = false
        self.isGenerating = false
        self.errorMessage = nil
        self.selectedAction = nil
        self.showResponse = false
    }

    /// Full reset: clears UI + conversation (used when collapsing or creating new session).
    func resetResponse() {
        resetUI()
        self.conversationHistory = []
    }

    // MARK: - Language Detection

    private func detectLanguage(for text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { detectedLanguage = "--"; languageFlag = "🌐"; return }
        recognizer.reset()
        recognizer.processString(t)
        if let lang = recognizer.dominantLanguage {
            let (a, f) = mapLang(lang.rawValue)
            detectedLanguage = a; languageFlag = f
        } else {
            detectedLanguage = "Unknown"; languageFlag = "❓"
        }
    }

    private func mapLang(_ code: String) -> (String, String) {
        switch code {
        case "en": return ("EN","🇺🇸")
        case "ko": return ("KR","🇰🇷")
        case "ja": return ("JP","🇯🇵")
        case "zh-Hans","zh-Hant","zh": return ("ZH","🇨🇳")
        case "es": return ("ES","🇪🇸")
        case "fr": return ("FR","🇫🇷")
        case "de": return ("DE","🇩🇪")
        case "it": return ("IT","🇮🇹")
        case "ru": return ("RU","🇷🇺")
        case "pt","pt-BR": return ("PT","🇵🇹")
        case "vi": return ("VN","🇻🇳")
        case "th": return ("TH","🇹🇭")
        default: return (code.uppercased(),"🌐")
        }
    }

    func grabClipboard() {
        if let text = NSPasteboard.general.string(forType: .string) {
            self.selectedContextText = text
            self.isExpanded = true
        }
    }

    // MARK: - PII Masking

    private func maskPII(text: String) async -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return await Task.detached(priority: .userInitiated) {
            var result = text
            let emailPat = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
            let phonePat = "\\+?\\b[0-9]{1,4}[-.\\s]?\\(?[0-9]{1,3}?\\)?[-.\\s]?[0-9]{3,4}[-.\\s]?[0-9]{4}\\b"
            for (pat, tag) in [(emailPat, "[EMAIL]"), (phonePat, "[PHONE]")] {
                if let rx = try? NSRegularExpression(pattern: pat, options: .caseInsensitive) {
                    let ns = result as NSString
                    let matches = rx.matches(in: result, options: [], range: NSRange(location: 0, length: ns.length))
                    for m in matches.reversed() {
                        result = (result as NSString).replacingCharacters(in: m.range, with: tag)
                    }
                }
            }
            let tagger = NLTagger(tagSchemes: [.nameType])
            tagger.string = result
            var reps: [(NSRange, String)] = []
            tagger.enumerateTags(in: result.startIndex..<result.endIndex,
                                  unit: .word, scheme: .nameType,
                                  options: [.omitPunctuation, .omitWhitespace, .joinNames]) { tag, range in
                guard let tag = tag else { return true }
                let ns = NSRange(range, in: result)
                switch tag {
                case .personalName:     reps.append((ns, "[NAME]"))
                case .organizationName: reps.append((ns, "[ORGANIZATION]"))
                case .placeName:        reps.append((ns, "[LOCATION]"))
                default: break
                }
                return true
            }
            reps.sort { $0.0.location > $1.0.location }
            for (range, ph) in reps {
                let ns = result as NSString
                if range.location + range.length <= ns.length {
                    result = ns.replacingCharacters(in: range, with: ph)
                }
            }
            return result
        }.value
    }

    // MARK: - Session Management

    func createNewSession() {
        let s = ChatSession(id: UUID(), title: "New Session", messages: [], createdAt: Date(), updatedAt: Date())
        self.chatSessions.insert(s, at: 0)
        self.currentSessionId = s.id
        self.conversationHistory = []
        self.resetResponse()
    }

    func selectSession(id: UUID) {
        guard let session = self.chatSessions.first(where: { $0.id == id }) else { return }
        self.currentSessionId = id
        resetUI()  // reset visual state but NOT history
        self.conversationHistory = session.messages

        // Restore last AI response to the response panel if session has history
        if let lastAI = session.messages.last(where: { $0.role != "user" }) {
            self.aiResponse = lastAI.content
            self.showResponse = !self.aiResponse.isEmpty
            self.updateMarkdown()
        }
        if !session.messages.isEmpty {
            self.isExpanded = true
        }
    }

    func deleteSession(id: UUID) {
        self.chatSessions.removeAll(where: { $0.id == id })
        if self.currentSessionId == id {
            if let first = self.chatSessions.first { selectSession(id: first.id) }
            else { createNewSession() }
        }
    }
}
