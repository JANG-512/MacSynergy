import SwiftUI

// Top-level function so both MainLauncherView and AIResponsePanel can call it
func parseMarkdown(_ text: String) -> [MarkdownSegment] {
    var segments: [MarkdownSegment] = []
    let parts = text.components(separatedBy: "```")
    for (index, part) in parts.enumerated() {
        let isCode = (index % 2 == 1)
        if !isCode && part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !part.contains("\n") {
            continue
        }
        if isCode {
            let lines = part.components(separatedBy: "\n")
            if let firstLine = lines.first {
                let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty && !trimmed.contains(" ") && trimmed.count < 15 {
                    let codeContent = lines.dropFirst().joined(separator: "\n")
                    segments.append(MarkdownSegment(isCode: true, language: trimmed, content: codeContent))
                } else {
                    segments.append(MarkdownSegment(isCode: true, language: nil, content: part))
                }
            } else {
                segments.append(MarkdownSegment(isCode: true, language: nil, content: part))
            }
        } else {
            segments.append(MarkdownSegment(isCode: false, language: nil, content: part))
        }
    }
    return segments
}

struct UltimateToastView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 11, weight: .bold))
            Text("Handoff to Chrome Successful!")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.green.opacity(0.12))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.green.opacity(0.24), lineWidth: 0.5)
        )
        .transition(.move(edge: .top).combined(with: .opacity))
        .padding(.top, 4)
    }
}

struct BubbleTriangle: Shape {
    var isPointingDown: Bool = true
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        if isPointingDown {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.closeSubpath()
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
            path.closeSubpath()
        }
        return path
    }
}

struct TypingIndicatorView: View {
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(LinearGradient(colors: [Color.blue, Color.purple], startPoint: .top, endPoint: .bottom))
                    .frame(width: 5, height: 5)
                    .scaleEffect(isAnimating ? 1.0 : 0.4)
                    .opacity(isAnimating ? 1.0 : 0.3)
                    .animation(
                        Animation.easeInOut(duration: 0.6)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.18),
                        value: isAnimating
                    )
            }
        }
        .onAppear {
            isAnimating = true
        }
    }
}

struct MarkdownSegment: Identifiable {
    let id = UUID()
    let isCode: Bool
    let language: String?
    let content: String
}

struct MainLauncherView: View {
    @ObservedObject var controller: WindowController
    @ObservedObject var viewModel: MacSynergyViewModel
    @FocusState private var isTextFieldFocused: Bool
    
    // UI Polish local states
    @State private var tempApiKey: String = ""
    @State private var tempOllamaModel: String = ""
    @State private var tempGeminiModel: String = ""
    @State private var isCopied: Bool = false

    // Unified additive card height math to prevent clipping under all visual combinations
    private var currentCardHeight: CGFloat {
        var height: CGFloat = 80
        if viewModel.showSidebar {
            height = max(height, 360)
        }
        if !viewModel.selectedContextText.isEmpty {
            height += 68
        }
        if viewModel.showSettings {
            var settingsHeight: CGFloat = 160
            if viewModel.selectedHandoffBrowser == .safari {
                settingsHeight += 16
            }
            if viewModel.isDownloadingModel {
                settingsHeight += 110
            } else {
                settingsHeight += 75
            }
            height += settingsHeight
        }
        if viewModel.isExpanded {
            height += 120
        }
        if viewModel.showResponse {
            height += 280  // conversation thread view is taller than a single response
        }
        if viewModel.showUltimateToast {
            height += 38
        }
        return height
    }
    
    var body: some View {
        Group {
            if controller.isContentVisible {
                VStack(spacing: 0) {
                    // Draw bubble triangle pointer at top if window is drawn below cursor coordinates
                    if !controller.isWindowAboveCursor {
                        BubbleTriangle(isPointingDown: false)
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: 20, height: 9)
                            .transition(.opacity)
                    }
                    
                    // Outermost glass card wrapping sidebar and workspace
                    HStack(spacing: 0) {
                        // 🕰️ Sleek Session Sidebar
                        if viewModel.showSidebar {
                            SidebarView(viewModel: viewModel)
                                .transition(.move(edge: .leading).combined(with: .opacity))
                            
                            Divider()
                                .background(Color.primary.opacity(0.08))
                                .frame(maxHeight: .infinity)
                        }
                        
                        // Main Visual Card Panel (Ultra-minimalist, pure glassmorphic)
                        VStack(spacing: 12) {
                        
                        // Dynamic Floating Toast for Ultimate Handoff Success
                        if viewModel.showUltimateToast {
                            UltimateToastView()
                        }
                        
                        // 0. Context Mode Quote Inset Box
                        if !viewModel.selectedContextText.isEmpty {
                            ContextModeBox(viewModel: viewModel, onUpdateHeight: { updateHeight() })
                        }
                        
                        // 1. Spotlight Search Field Row (Large, borderless typography)
                        SearchBarRow(
                            viewModel: viewModel,
                            isTextFieldFocused: $isTextFieldFocused,
                            onUpdateHeight: { updateHeight() }
                        )    .frame(height: 80)
                        
                        // ⚙️ Collapsible Configuration Card
                        if viewModel.showSettings {
                            SettingsView(
                                viewModel: viewModel,
                                tempOllamaModel: $tempOllamaModel,
                                tempGeminiModel: $tempGeminiModel,
                                tempApiKey: $tempApiKey,
                                onHeightChange: { updateHeight() }
                            )
                        }
                        
                        // 2. Expanded HUD Container
                        if viewModel.isExpanded {
                            ExpandedOptionsPanel(viewModel: viewModel, onUpdateHeight: { updateHeight() })
                        }
                        
                        // 3. AI Stream response window
                        if viewModel.showResponse {
                            AIResponsePanel(viewModel: viewModel)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, (viewModel.isExpanded || viewModel.showResponse) ? 14 : 0)
                    .frame(width: 680)
                    }
                    .frame(height: currentCardHeight)
                    .background(
                        VisualEffectView(material: .hudWindow, blendingMode: .behindWindow, state: .active)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(
                                isTextFieldFocused ? 
                                    Color.white.opacity(0.18) :
                                    Color.white.opacity(0.08),
                                lineWidth: 1.0
                            )
                    )
                    .shadow(color: Color.black.opacity(0.3), radius: 20, x: 0, y: 10)
                    
                    // Invisible Hotkey Bindings for active overlay window
                    ZStack {
                        // 1. Cmd + E: Dynamic Engine Mode Cycle Toggle (Auto -> Local -> Cloud -> Auto)
                        Button("") {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                                viewModel.cycleEngineMode()
                            }
                        }
                        .keyboardShortcut("e", modifiers: .command)
                        
                        // 2. Cmd + Enter: Paste AI Answer back to original focus app
                        Button("") {
                            viewModel.triggerPasteBack()
                        }
                        .keyboardShortcut(.return, modifiers: .command)
                        
                        // 3. Cmd + D: Toggle voice dictation
                        Button("") {
                            viewModel.toggleDictation()
                        }
                        .keyboardShortcut("d", modifiers: .command)
                    }
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    
                    // Draw bubble triangle pointer at bottom if window is drawn above cursor coordinates
                    if controller.isWindowAboveCursor {
                        BubbleTriangle(isPointingDown: true)
                            .fill(Color.primary.opacity(0.08))
                            .frame(width: 20, height: 9)
                            .offset(y: -1) // Overlap slightly to visually lock into the panel border
                            .transition(.opacity)
                    }
                }
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.95).combined(with: .opacity),
                        removal: .scale(scale: 0.95).combined(with: .opacity)
                    )
                )
                .onChange(of: viewModel.isExpanded) { oldValue, newValue in
                    updateHeight()
                }
                .onChange(of: viewModel.showResponse) { oldValue, newValue in
                    updateHeight()
                }
                .onChange(of: viewModel.selectedContextText) { oldValue, newValue in
                    updateHeight()
                }
                .onChange(of: viewModel.showUltimateToast) { oldValue, newValue in
                    updateHeight()
                }
                // Fix: post sidebar width notification so WindowController can resize the window
                .onChange(of: viewModel.showSidebar) { oldValue, newValue in
                    NotificationCenter.default.post(
                        name: Notification.Name("showSidebarDidChange"),
                        object: newValue
                    )
                    updateHeight()
                }
                .onAppear {
                    tempApiKey = viewModel.apiKey
                    tempOllamaModel = viewModel.ollamaModel
                    tempGeminiModel = viewModel.geminiModel
                    updateHeight()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
                    if notification.object as? NSWindow == controller.window {
                        isTextFieldFocused = true
                    }
                }
            }
        }
    }
    
    private func getIcon(for action: String) -> String {
        switch action {
        case "Summarize": return "text.alignleft"
        case "Extract Key Points": return "list.bullet.indent"
        case "Draft a Reply": return "arrowshape.turn.up.left"
        case "General Query": return "sparkles"
        default: return "sparkles"
        }
    }
    
    private func updateHeight() {
        // 9px matches the exact height of the single visible BubbleTriangle
        controller.adjustWindowHeight(to: currentCardHeight + 9)
    }
    
    // Parses full markdown responses by isolating ``` fenced blocks for scrollable monospaced styling
    private func parseMarkdown(_ text: String) -> [MarkdownSegment] {
        var segments: [MarkdownSegment] = []
        let parts = text.components(separatedBy: "```")
        
        for (index, part) in parts.enumerated() {
            let isCode = (index % 2 == 1)
            
            // Skip completely empty plain text segments
            if !isCode && part.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !part.contains("\n") {
                continue
            }
            
            if isCode {
                // Find language name (robust to all single-word strings under 15 characters without spaces)
                let lines = part.components(separatedBy: "\n")
                if let firstLine = lines.first {
                    let firstLineTrimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !firstLineTrimmed.isEmpty && !firstLineTrimmed.contains(" ") && firstLineTrimmed.count < 15 {
                        let codeContent = lines.dropFirst().joined(separator: "\n")
                        segments.append(MarkdownSegment(isCode: true, language: firstLineTrimmed, content: codeContent))
                    } else {
                        segments.append(MarkdownSegment(isCode: true, language: nil, content: part))
                    }
                } else {
                    segments.append(MarkdownSegment(isCode: true, language: nil, content: part))
                }
            } else {
                segments.append(MarkdownSegment(isCode: false, language: nil, content: part))
            }
        }
        
        return segments
    }
    
    // Fast inline markdown parser that safely wraps standard text block modifications
    private func parseInlineMarkdown(_ content: String) -> AttributedString {
        if let attString = try? AttributedString(
            markdown: content,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return attString
        } else {
            return AttributedString(content)
        }
    }
}

struct SidebarView: View {
    @ObservedObject var viewModel: MacSynergyViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Sidebar Header
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundColor(.secondary)
                        .font(.system(size: 11, weight: .bold))
                    Text("Sessions")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Add Session Button
                Button(action: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                        viewModel.createNewSession()
                    }
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .help("Create new conversation session")
            }
            .padding(.top, 16)
            .padding(.horizontal, 12)
            
            // Session List
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 6) {
                    ForEach(viewModel.chatSessions) { session in
                        let isSelected = session.id == viewModel.currentSessionId
                        
                        HStack(spacing: 8) {
                            // Active indicator pill
                            if isSelected {
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(LinearGradient(colors: [Color.purple, Color.blue], startPoint: .top, endPoint: .bottom))
                                    .frame(width: 3, height: 16)
                            }
                            
                            // Session Info Button
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    viewModel.selectSession(id: session.id)
                                }
                            }) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.title)
                                        .font(.system(size: 11.5, weight: isSelected ? .bold : .medium, design: .rounded))
                                        .foregroundColor(isSelected ? .primary : .primary.opacity(0.8))
                                        .lineLimit(1)
                                    
                                    // Timestamp
                                    Text(formatDate(session.updatedAt))
                                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            
                            // Delete Button
                            Button(action: {
                                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                                    viewModel.deleteSession(id: session.id)
                                }
                            }) {
                                Image(systemName: "trash")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.secondary.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .background(
                            isSelected ? 
                                AnyView(Color.primary.opacity(0.06)) : 
                                AnyView(Color.clear)
                        )
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isSelected ? Color.primary.opacity(0.1) : Color.clear, lineWidth: 0.5)
                        )
                    }
                }
                .padding(.horizontal, 6)
            }
        }
        .frame(width: 170)
        .background(Color.primary.opacity(0.01))
    }
    
    // Relative format helper (e.g. "10:32 AM" or "Yesterday")
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "h:mm a"
        } else if Calendar.current.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            formatter.dateFormat = "MMM d"
        }
        return formatter.string(from: date)
    }
}

struct MarkdownSegmentView: View {
    let segment: MarkdownSegment
    
    var body: some View {
        if segment.isCode {
            VStack(alignment: .leading, spacing: 0) {
                // Code Block Header strip with single-copy button!
                HStack {
                    Text(segment.language?.uppercased() ?? "CODE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(segment.content, forType: .string)
                    }) {
                        HStack(spacing: 3.5) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 9))
                            Text("Copy Code")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.04))
                
                Divider()
                    .background(Color.primary.opacity(0.05))
                
                // Horizontal Scroll for long code structures
                ScrollView(.horizontal, showsIndicators: true) {
                    Text(segment.content)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.9))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(Color.primary.opacity(0.02))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
            .padding(.vertical, 4)
        } else {
            // Plain paragraph block with full inline styling
            Text(parseInlineMarkdown(segment.content))
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundColor(.primary.opacity(0.95))
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
        }
    }
    
    // Fast inline markdown parser that safely wraps standard text block modifications
    private func parseInlineMarkdown(_ content: String) -> AttributedString {
        if let attString = try? AttributedString(
            markdown: content,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return attString
        } else {
            return AttributedString(content)
        }
    }
}

struct QuickActionButton: View {
    let action: String
    @ObservedObject var viewModel: MacSynergyViewModel
    
    var body: some View {
        Button(action: {
            Task {
                await viewModel.submitPrompt(action: action)
            }
        }) {
            HStack(spacing: 5) {
                Image(systemName: getIcon(for: action))
                    .font(.system(size: 10, weight: .semibold))
                Text(action)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .foregroundColor(viewModel.selectedAction == action ? .white : .primary.opacity(0.85))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                viewModel.selectedAction == action ?
                    AnyView(LinearGradient(colors: [Color.purple, Color.blue], startPoint: .topLeading, endPoint: .bottomTrailing)) :
                    AnyView(Color.primary.opacity(0.05))
            )
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        viewModel.selectedAction == action ? Color.purple.opacity(0.3) : Color.primary.opacity(0.08),
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    private func getIcon(for action: String) -> String {
        switch action {
        case "Summarize": return "text.alignleft"
        case "Extract Key Points": return "list.bullet.indent"
        case "Draft a Reply": return "arrowshape.turn.up.left"
        case "General Query": return "sparkles"
        default: return "sparkles"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var viewModel: MacSynergyViewModel
    @Binding var tempOllamaModel: String
    @Binding var tempGeminiModel: String
    @Binding var tempApiKey: String
    let onHeightChange: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            // Ollama model row
            HStack(spacing: 8) {
                Image(systemName: "cpu")
                    .foregroundColor(.blue)
                    .font(.system(size: 11))
                Text("Ollama Model:")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                TextField("e.g. exaone3.5:7.8b", text: $tempOllamaModel)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(6)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(6)
                    .onSubmit { viewModel.saveOllamaModel(tempOllamaModel) }
                Button("Save") { viewModel.saveOllamaModel(tempOllamaModel) }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.blue)
                    .cornerRadius(6)
                    .buttonStyle(.plain)
            }

            // Gemini model row
            HStack(spacing: 8) {
                Image(systemName: "cloud.fill")
                    .foregroundColor(.purple)
                    .font(.system(size: 11))
                Text("Gemini Model:")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                TextField("e.g. gemini-2.0-flash-lite", text: $tempGeminiModel)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(6)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(6)
                    .onSubmit { viewModel.saveGeminiModel(tempGeminiModel) }
                Button("Save") { viewModel.saveGeminiModel(tempGeminiModel) }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.purple)
                    .cornerRadius(6)
                    .buttonStyle(.plain)
            }

            // Gemini API Key row
            HStack(spacing: 8) {
                Image(systemName: "key")
                    .foregroundColor(.yellow)
                    .font(.system(size: 11))
                Text("Gemini API Key:")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                SecureField("Paste your Gemini API key here...", text: $tempApiKey)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(6)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(6)
                    .onSubmit { viewModel.saveAPIKey(tempApiKey) }
                Button("Save") { viewModel.saveAPIKey(tempApiKey) }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.blue)
                    .cornerRadius(6)
                    .buttonStyle(.plain)
            }

            Divider().background(Color.primary.opacity(0.06))

            // Handoff settings
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "bolt.shield")
                        .foregroundColor(.orange)
                        .font(.system(size: 11))
                    Text("Handoff Browser:")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                    Picker("", selection: $viewModel.selectedHandoffBrowser) {
                        ForEach(HandoffBrowser.allCases) { b in
                            Text(b.rawValue).tag(b)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .controlSize(.small)
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: "safari")
                        .foregroundColor(.blue)
                        .font(.system(size: 11))
                    Text("Handoff Target:")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                    Picker("", selection: $viewModel.selectedHandoffTarget) {
                        ForEach(HandoffTarget.allCases) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .controlSize(.small)
                }
            }

            if viewModel.selectedHandoffBrowser == .safari {
                Text("ℹ️ Safari requires 'Develop → Allow JavaScript from Apple Events' enabled.")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.leading, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider().background(Color.primary.opacity(0.06))

            // Ollama Downloader Section
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Ollama Model Downloader")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                    Spacer()
                    HStack(spacing: 8) {
                        Button("Exaone 3.5") { tempOllamaModel = "exaone3.5:7.8b" }
                            .font(.system(size: 9.5, weight: .medium))
                            .buttonStyle(.plain)
                            .foregroundColor(.blue)
                        Button("Llama 3.2 (3B)") { tempOllamaModel = "llama3.2" }
                            .font(.system(size: 9.5, weight: .medium))
                            .buttonStyle(.plain)
                            .foregroundColor(.blue)
                        Button("Qwen 2.5 (7B)") { tempOllamaModel = "qwen2.5:7b" }
                            .font(.system(size: 9.5, weight: .medium))
                            .buttonStyle(.plain)
                            .foregroundColor(.blue)
                    }
                }
                
                HStack(spacing: 8) {
                    TextField("Enter model name to download...", text: $tempOllamaModel)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(6)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(6)
                    
                    if viewModel.isDownloadingModel {
                        Button("Cancel") {
                            viewModel.cancelModelDownload()
                        }
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.red)
                        .cornerRadius(6)
                        .buttonStyle(.plain)
                    } else {
                        Button("Download") {
                            viewModel.pullOllamaModel(name: tempOllamaModel)
                        }
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.blue)
                        .cornerRadius(6)
                        .buttonStyle(.plain)
                        .disabled(tempOllamaModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                
                if viewModel.isDownloadingModel {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            ProgressView(value: viewModel.downloadProgress)
                                .progressViewStyle(.linear)
                            
                            Text("\(Int(viewModel.downloadProgress * 100))%")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Text(viewModel.downloadStatus)
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                    .transition(.opacity)
                }
            }

            Divider().background(Color.primary.opacity(0.06))

            // Diagnostics Section
            HStack(spacing: 16) {
                Button(action: {
                    Task {
                        await viewModel.testOllamaConnection()
                        await viewModel.testGeminiAPIKey()
                        onHeightChange()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "stethoscope")
                            .font(.system(size: 10))
                        Text("Run Diagnostics")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.blue)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Text("Ollama:")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                        if let connected = viewModel.isOllamaConnected {
                            Image(systemName: connected ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(connected ? .green : .red)
                                .font(.system(size: 11))
                        } else {
                            Text("—").font(.system(size: 10)).foregroundColor(.secondary)
                        }
                    }
                    
                    HStack(spacing: 4) {
                        Text("Gemini API:")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                        if let connected = viewModel.isGeminiConnected {
                            Image(systemName: connected ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(connected ? .green : .red)
                                .font(.system(size: 11))
                        } else {
                            Text("—").font(.system(size: 10)).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(.top, 4)
        }
        .padding(10)
        .background(Color.primary.opacity(0.02))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .transition(.move(edge: .top).combined(with: .opacity))
        .onChange(of: viewModel.showSettings) { oldValue, newValue in
            onHeightChange()
        }
        .onChange(of: viewModel.selectedHandoffBrowser) { oldValue, newValue in
            onHeightChange()
        }
        .onChange(of: viewModel.isDownloadingModel) { oldValue, newValue in
            onHeightChange()
        }
    }
}

struct UltimateResponseView: View {
    @ObservedObject var viewModel: MacSynergyViewModel

    var body: some View {
        VStack(spacing: 8) {
            // Error banner — shown when API key is missing or any Ultimate Mode error occurs
            if let errMsg = viewModel.errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 13))
                    Text(errMsg)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                }
                .padding(10)
                .background(Color.red.opacity(0.07))
                .cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red.opacity(0.2), lineWidth: 0.5))
                .transition(.move(edge: .top).combined(with: .opacity))
            }

        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "cpu.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 13))
                    Text("Local Ollama (\(viewModel.ollamaModel))")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Spacer()
                    if viewModel.ultimateLocalResponse.isEmpty {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 12))
                    }
                }
                .padding(.bottom, 4)
                
                ScrollView(.vertical) {
                    if viewModel.ultimateLocalResponse.isEmpty {
                        Text("Warming up local engine...")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    } else {
                        Text(viewModel.ultimateLocalResponse)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(.primary.opacity(0.85))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.primary.opacity(0.02))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
            
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "cloud.fill")
                        .foregroundColor(.blue)
                        .font(.system(size: 13))
                    Text("Cloud Gemini (\(viewModel.geminiModel))")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Spacer()
                    if viewModel.ultimateCloudResponse.isEmpty {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 12))
                    }
                }
                .padding(.bottom, 4)
                
                ScrollView(.vertical) {
                    if viewModel.ultimateCloudResponse.isEmpty {
                        Text("Querying cloud reasoning models...")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    } else {
                        Text(viewModel.ultimateCloudResponse)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(.primary.opacity(0.85))
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.primary.opacity(0.02))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
        }
        .frame(height: 220)
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .transition(.opacity)
        }
    }
}

struct SearchBarRow: View {
    @ObservedObject var viewModel: MacSynergyViewModel
    @FocusState.Binding var isTextFieldFocused: Bool
    let onUpdateHeight: () -> Void
    
    var body: some View {
        HStack(spacing: 14) {
            // Sleek Gradient Icon
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color.purple, Color.blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 38, height: 38)
                    .shadow(color: Color.purple.opacity(0.2), radius: 5, x: 0, y: 2)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }
            .scaleEffect(isTextFieldFocused ? 1.04 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isTextFieldFocused)
            
            // Dynamic search placeholder depending on Context Mode
            let placeholderText = viewModel.selectedContextText.isEmpty ? 
                "Search, ask, or enter custom command..." : 
                "What do you want to do with this text? (e.g., Translate, Summarize)"
            
            // Input Field
            TextField(placeholderText, text: $viewModel.inputText)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .textFieldStyle(.plain)
                .foregroundColor(.primary)
                .focused($isTextFieldFocused)
                .padding(.vertical, 8)
                .onSubmit {
                    Task {
                        await viewModel.submitCustomInstruction()
                    }
                }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        isTextFieldFocused = true
                    }
                }
            
            // Microphone Dictation Toggle Button
            Button(action: {
                viewModel.toggleDictation()
            }) {
                ZStack {
                    if viewModel.isRecording {
                        Circle()
                            .stroke(LinearGradient(colors: [Color.purple, Color.blue], startPoint: .top, endPoint: .bottom), lineWidth: 1.5)
                            .scaleEffect(1.0 + CGFloat(viewModel.soundLevel) * 0.4)
                            .opacity(0.8 - Double(viewModel.soundLevel) * 0.3)
                            .animation(.linear(duration: 0.15), value: viewModel.soundLevel)
                    }
                    Image(systemName: viewModel.isRecording ? "mic.fill" : "mic")
                        .foregroundColor(viewModel.isRecording ? .red : .secondary.opacity(0.8))
                        .font(.system(size: 14, weight: viewModel.isRecording ? .bold : .regular))
                }
                .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("Toggle voice input (Cmd+D)")
            
            // Clipboard Context Grabber Button
            Button(action: {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                    viewModel.grabClipboard()
                    onUpdateHeight()
                }
            }) {
                Image(systemName: "doc.on.clipboard")
                    .foregroundColor(.secondary.opacity(0.8))
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .help("Grab context from clipboard")
            
            // Clear Text Input Button
            if !viewModel.inputText.isEmpty {
                Button(action: { 
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                        viewModel.inputText = ""
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary.opacity(0.8))
                        .font(.system(size: 15))
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
            
            // 🤖 Dynamic Engine Status Tag Pill (cycles via Cmd+E)
            let engineTagText: String = {
                switch viewModel.selectedEngineMode {
                case .auto:
                    return viewModel.selectedEngine == .local ? "Auto (Local)" : "Auto (Cloud)"
                case .local:
                    return "Local"
                case .cloud:
                    return "Cloud"
                }
            }()
            
            let isLocalActive = viewModel.selectedEngine == .local
            
            HStack(spacing: 4) {
                Image(systemName: viewModel.selectedEngineMode == .auto ? "sparkles" : (isLocalActive ? "cpu" : "cloud.fill"))
                    .font(.system(size: 9))
                Text(engineTagText)
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
            }
            .foregroundColor(isLocalActive ? .blue : .purple)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(isLocalActive ? Color.blue.opacity(0.12) : Color.purple.opacity(0.12))
            .cornerRadius(8)
            .help("Engine mode. Press Cmd+E to cycle.")
            .transition(.scale.combined(with: .opacity))
            
            // 🛡️ PII Masked Status Pill (Draws dynamically next to language pill)
            if viewModel.hasMaskedPII {
                HStack(spacing: 4) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 10))
                    Text("PII Masked")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                }
                .foregroundColor(.green)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.green.opacity(0.12))
                .cornerRadius(8)
                .transition(.scale.combined(with: .opacity))
            }
            
            // Local Language Recognition Pill
            HStack(spacing: 5) {
                Text(viewModel.languageFlag)
                    .font(.system(size: 15))
                Text(viewModel.detectedLanguage)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                    )
            )
            .opacity(viewModel.inputText.isEmpty ? 0.35 : 1.0)
            .scaleEffect(viewModel.inputText.isEmpty ? 0.96 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: viewModel.inputText.isEmpty)
            .transition(.scale.combined(with: .opacity))
            
            // 🕰️ History Session Sidebar Button
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    viewModel.showSidebar.toggle()
                    onUpdateHeight()
                }
            }) {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(viewModel.showSidebar ? .blue : .secondary.opacity(0.8))
                    .font(.system(size: 15, weight: .medium))
            }
            .buttonStyle(.plain)
            .help("Toggle chat sessions history")
            
            // ⚙️ Progressive Settings Gear Button
            Button(action: {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    viewModel.showSettings.toggle()
                }
            }) {
                Image(systemName: "gearshape")
                    .foregroundColor(viewModel.showSettings ? .blue : .secondary.opacity(0.8))
                    .font(.system(size: 15, weight: .medium))
            }
            .buttonStyle(.plain)
            .help("Toggle settings panel")
        }
    }
}

struct ContextModeBox: View {
    @ObservedObject var viewModel: MacSynergyViewModel
    let onUpdateHeight: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "quote.bubble.fill")
                .font(.system(size: 11))
                .foregroundColor(.blue.opacity(0.8))
                .padding(.top, 2)
            
            ScrollView(.vertical, showsIndicators: true) {
                Text(viewModel.selectedContextText)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.primary.opacity(0.75))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxHeight: 52)
            
            Button(action: {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    viewModel.selectedContextText = ""
                    onUpdateHeight()
                }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

struct ResponseControlBar: View {
    @ObservedObject var viewModel: MacSynergyViewModel
    
    var body: some View {
        HStack(spacing: 8) {
            // Dynamic Generating dots or status tag
            if viewModel.isGenerating {
                TypingIndicatorView()
                    .padding(.trailing, 4)
            }

            // ── Stop generation button (shown while generating) ──
            if viewModel.isGenerating || viewModel.isLoading {
                Button(action: { viewModel.cancelGeneration() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text("Stop")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.red.opacity(0.85))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .help("Stop generation")
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }

            // Reset/Regenerate Button
            Button(action: {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    viewModel.resetResponse()
                }
            }) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(6)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Reset")
            
            // Paste Back to active app (Cmd+Enter helper)
            Button(action: {
                viewModel.triggerPasteBack()
            }) {
                HStack(spacing: 3) {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                    Text("Paste Back")
                }
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    LinearGradient(colors: [Color.blue, Color.purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .cornerRadius(10)
                .shadow(color: Color.blue.opacity(0.15), radius: 3)
            }
            .buttonStyle(.plain)
            .help("Paste response back into your original app (Cmd+Enter)")
        }
        .padding(8)
    }
}

struct ExpandedOptionsPanel: View {
    @ObservedObject var viewModel: MacSynergyViewModel
    let onUpdateHeight: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .background(Color.primary.opacity(0.08))
            
            // Segmented three-state engine mode switcher & Ultimate Mode Toggle
            HStack(spacing: 12) {
                Picker("", selection: $viewModel.selectedEngineMode) {
                    ForEach(AIEngineMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                
                Toggle(isOn: $viewModel.isUltimateMode) {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.shield.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                        Text("Ultimate Mode")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.orange)
                    }
                }
                .toggleStyle(.checkbox)
            }
            .padding(.horizontal, 4)
            .onChange(of: viewModel.selectedEngineMode) { oldValue, newValue in
                onUpdateHeight()
            }
            
            // Local Quick Action pills row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(["Summarize", "Extract Key Points", "Draft a Reply", "General Query"], id: \.self) { action in
                        QuickActionButton(action: action, viewModel: viewModel)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .transition(.opacity)
    }
}

// MARK: - Conversation History Thread

struct ConversationThreadView: View {
    @ObservedObject var viewModel: MacSynergyViewModel

    /// Messages that are fully committed (not the currently streaming response)
    private var committedMessages: [ChatMessage] {
        // When generating, the last assistant message is still in aiResponse — exclude it from history
        let history = viewModel.conversationHistory
        if viewModel.isGenerating, let last = history.last, last.role != "user" {
            return Array(history.dropLast())
        }
        return history
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(committedMessages) { message in
                        MessageBubbleView(message: message)
                    }

                    // Streaming bubble — shows the AI response as it arrives
                    if viewModel.isLoading && !viewModel.isGenerating {
                        // Spinner waiting for first token
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(viewModel.selectedEngine == .local
                                 ? "Warming up '\(viewModel.ollamaModel)'..."
                                 : "Querying \(viewModel.geminiModel)...")
                                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 6)
                        .id("bottom")
                    } else if viewModel.isGenerating && !viewModel.aiResponse.isEmpty {
                        // Streaming in progress
                        AIMessageBubble(
                            text: viewModel.aiResponse,
                            isStreaming: true,
                            engine: viewModel.selectedEngine
                        )
                        .id("bottom")
                    } else if let err = viewModel.errorMessage {
                        // Error state
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                                .font(.system(size: 13))
                            Text(err)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(10)
                        .background(Color.red.opacity(0.06))
                        .cornerRadius(10)
                        .id("bottom")
                    }

                    // Scroll anchor
                    Color.clear.frame(height: 36).id("end")
                }
                .padding(10)
                .onChange(of: viewModel.aiResponse) { _, _ in
                    withAnimation(.easeInOut(duration: 0.1)) { proxy.scrollTo("end", anchor: .bottom) }
                }
                .onChange(of: viewModel.conversationHistory.count) { _, _ in
                    withAnimation(.easeInOut(duration: 0.15)) { proxy.scrollTo("end", anchor: .bottom) }
                }
                .onChange(of: viewModel.errorMessage) { _, _ in
                    withAnimation { proxy.scrollTo("end", anchor: .bottom) }
                }
                .onAppear {
                    proxy.scrollTo("end", anchor: .bottom)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}

struct MessageBubbleView: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == "user" }
    private var engine: AIEngine { .local }  // only used for styling

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if isUser { Spacer(minLength: 40) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 3) {
                Text(isUser ? "You" : "AI")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)

                if isUser {
                    // User bubble — gradient right-aligned
                    Text(message.visibleContent)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            LinearGradient(colors: [Color.purple, Color.blue],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .cornerRadius(14)
                        .cornerRadius(4, corners: .topRight)
                } else {
                    // AI bubble — glass left-aligned with markdown
                    AIMessageBubble(text: message.content, isStreaming: false, engine: message.engine)
                }
            }

            if !isUser { Spacer(minLength: 40) }
        }
    }
}

struct AIMessageBubble: View {
    let text: String
    let isStreaming: Bool
    let engine: AIEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Engine label strip
            HStack(spacing: 4) {
                Image(systemName: engine == .local ? "cpu.fill" : "cloud.fill")
                    .font(.system(size: 8))
                    .foregroundColor(engine == .local ? .orange : .blue)
                Text(engine == .local ? "Local" : "Cloud")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                Spacer()
                if isStreaming {
                    TypingIndicatorView()
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 4)

            Divider().opacity(0.5)

            // Markdown content
            VStack(alignment: .leading, spacing: 8) {
                ForEach(parseMarkdown(text)) { segment in
                    MarkdownSegmentView(segment: segment)
                }
            }
            .padding(10)
        }
        .background(Color.primary.opacity(0.03))
        .cornerRadius(14)
        .cornerRadius(4, corners: .topLeft)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.07), lineWidth: 0.5)
        )
    }
}

// Corner radius helper for individual corners
extension View {
    func cornerRadius(_ radius: CGFloat, corners: RectCorner) -> some View {
        clipShape(RoundedCornerShape(radius: radius, corners: corners))
    }
}

enum RectCorner { case topLeft, topRight, bottomLeft, bottomRight }

struct RoundedCornerShape: Shape {
    var radius: CGFloat
    var corners: RectCorner

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(radius, min(rect.width, rect.height) / 2)
        let tl = corners == .topLeft ? r : 0
        let tr = corners == .topRight ? r : 0
        let br = corners == .bottomRight ? r : 0
        let bl = corners == .bottomLeft ? r : 0

        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        if tr > 0 { path.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr), radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false) }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        if br > 0 { path.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br), radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false) }
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        if bl > 0 { path.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl), radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false) }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        if tl > 0 { path.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl), radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false) }
        path.closeSubpath()
        return path
    }
}

// MARK: - AI Response Panel

struct AIResponsePanel: View {
    @ObservedObject var viewModel: MacSynergyViewModel

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.primary.opacity(0.08))

            if viewModel.isUltimateMode {
                UltimateResponseView(viewModel: viewModel)
            } else {
                // Conversation thread: shows all turns + live streaming bubble
                ZStack(alignment: .bottomTrailing) {
                    ConversationThreadView(viewModel: viewModel)
                        .frame(height: 260)
                        .background(Color.primary.opacity(0.01))
                        .cornerRadius(8)

                    // Floating action bar (only when not actively generating)
                    if !viewModel.isGenerating && !viewModel.isLoading {
                        ResponseControlBar(viewModel: viewModel)
                            .padding(6)
                    }
                }
                .transition(.opacity)
            }
        }
    }
}
