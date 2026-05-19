import Foundation

struct PromptManager {
    private static let globalFormattingRules = """
    
    CRITICAL RULES FOR CODE AND LAYOUT:
    1. Whenever you generate, display, or write any programming code of ANY language, you MUST wrap it strictly in fenced markdown code blocks with the exact language tag (e.g., ```swift ... ```). NEVER output raw code without fences.
       Correct Example:
       Here is the code:
       ```swift
       for i in 1...5 {
           print(i)
       }
       ```
    2. NEVER merge code blocks into normal text paragraphs. Always separate code blocks using double newlines (\\n\\n).
    3. Ensure clean, beautiful, and highly structured markdown formatting with clear vertical spacing.
    """

    /// Generates a highly refined system prompt + context based on the selected action and user query.
    static func generatePrompt(inputText: String, action: String?) -> String {
        let systemInstruction: String
        
        if let action = action {
            switch action {
            case "Summarize":
                systemInstruction = """
                You are a helpful macOS assistant. 
                Analyze the provided text context and respond with a concise, beautifully structured markdown summary. 
                Use clean headings, bullet points, and bold text to present key themes.
                """
            case "Extract Key Points":
                systemInstruction = """
                You are a helpful macOS assistant. 
                Extract the primary key points from the provided text context and render them as a highly structured, bulleted markdown list.
                """
            case "Draft a Reply":
                systemInstruction = """
                You are a helpful macOS assistant. 
                Draft a professional, clear, and highly contextual reply to the provided message context. 
                Match the tone and level of detail of the input.
                """
            case "General Query":
                systemInstruction = """
                You are a helpful macOS assistant. 
                Respond to the user's query clearly and concisely using standard, beautifully formatted markdown.
                """
            default:
                systemInstruction = "You are a helpful macOS assistant. Answer concisely using markdown formatting."
            }
        } else {
            // Default heuristics based on length
            if inputText.count < 100 {
                systemInstruction = "You are a helpful macOS assistant. Answer concisely using standard markdown formatting."
            } else {
                systemInstruction = """
                You are a helpful macOS assistant. 
                Analyze the following long text context carefully and respond with a well-structured markdown summary.
                """
            }
        }
        
        let finalInstruction = systemInstruction + globalFormattingRules
        return "\(finalInstruction)\n\nText Context:\n\"\"\"\n\(inputText)\n\"\"\""
    }
}
