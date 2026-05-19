import SwiftUI

private let menuWidth:  CGFloat = 220
private let menuHeight: CGFloat = 300

enum QuickAction: String, CaseIterable, Identifiable {
    case summarize = "요약하기"
    case translate = "번역하기"
    case rewrite   = "다시쓰기"
    case write     = "글쓰기"
    case analyze   = "분석하기"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .summarize: return "text.quote"
        case .translate: return "globe"
        case .rewrite:   return "arrow.triangle.2.circlepath"
        case .write:     return "pencil.and.sparkles"
        case .analyze:   return "magnifyingglass"
        }
    }

    var color: Color {
        switch self {
        case .summarize: return .blue
        case .translate: return .green
        case .rewrite:   return .orange
        case .write:     return .purple
        case .analyze:   return .teal
        }
    }

    var promptPrefix: String {
        switch self {
        case .summarize: return "다음 텍스트를 핵심만 담아 간결하게 요약해주세요:\n\n"
        case .translate: return "다음 텍스트를 자연스럽게 번역해주세요 (한국어↔영어 자동 감지):\n\n"
        case .rewrite:   return "다음 텍스트를 더 명확하고 자연스럽게 다시 써주세요:\n\n"
        case .write:     return ""
        case .analyze:   return "다음 텍스트를 깊이 있게 분석해주세요:\n\n"
        }
    }
}

// MARK: - Floating + Button

struct SelectionPlusButtonView: View {
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Circle().stroke(
                            LinearGradient(
                                colors: [.purple.opacity(0.55), .blue.opacity(0.45)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                    )
                    .shadow(color: .black.opacity(0.22), radius: 6, x: 0, y: 3)

                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(colors: [.purple, .blue],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            }
        }
        .buttonStyle(.plain)
        .frame(width: 32, height: 32)
        .scaleEffect(isHovered ? 1.14 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isHovered)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Single action row

struct QuickActionRow: View {
    let action: QuickAction
    let showChevron: Bool
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(action.color.opacity(isHovered ? 0.22 : 0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: action.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(action.color)
                        .scaleEffect(isHovered ? 1.08 : 1.0)
                        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
                }

                Text(action.rawValue)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()

                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isHovered ? action.color.opacity(0.07) : Color.clear)
                    .padding(.horizontal, 4)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.72)) { isHovered = hovering }
        }
    }
}

// MARK: - Write Prompt Sub-view

struct WritePromptView: View {
    let selectedText: String
    let onSubmit: (String) -> Void
    let onExpand: () -> Void
    let onBack: () -> Void

    @State private var prompt = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Nav row
            HStack(spacing: 6) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Text("글쓰기")
                    .font(.system(size: 12, weight: .bold, design: .rounded))

                Spacer()

                Button(action: onExpand) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10, weight: .semibold))
                        Text("확장")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.purple)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Selected text preview (only when text is present)
            if !selectedText.isEmpty {
                Text("\"\(selectedText.prefix(60))\(selectedText.count > 60 ? "…" : "")\"")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundColor(.secondary.opacity(0.7))
                    .lineLimit(2)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }

            // Prompt field
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isFocused ? Color.purple.opacity(0.35) : Color.primary.opacity(0.1),
                                    lineWidth: 1)
                    )

                if prompt.isEmpty {
                    Text("어떤 글을 쓸까요?")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.secondary.opacity(0.5))
                        .padding(8)
                        .allowsHitTesting(false)
                }

                TextField("", text: $prompt, axis: .vertical)
                    .font(.system(size: 11, design: .rounded))
                    .textFieldStyle(.plain)
                    .lineLimit(3...)
                    .padding(8)
                    .focused($isFocused)
                    .onSubmit {
                        let p = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !p.isEmpty { onSubmit(p) }
                    }
            }
            .frame(height: 70)
            .padding(.horizontal, 12)
            .padding(.bottom, 10)

            // Generate button
            Button(action: {
                let p = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                if !p.isEmpty { onSubmit(p) }
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                    Text("생성하기")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? AnyShapeStyle(Color.secondary.opacity(0.35))
                        : AnyShapeStyle(LinearGradient(colors: [.purple, .blue],
                                                        startPoint: .leading, endPoint: .trailing))
                )
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(width: menuWidth)
        .onAppear {
            // Slight delay avoids focus fight with the panel becoming key
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isFocused = true }
        }
    }
}

// MARK: - Quick Action Menu (root view for the action panel)

struct QuickActionMenuView: View {
    let selectedText: String
    let onAction: (QuickAction, String?) -> Void
    let onExpand:  () -> Void
    let onDismiss: () -> Void

    @State private var showWrite = false

    var body: some View {
        ZStack {
            if showWrite {
                WritePromptView(
                    selectedText: selectedText,
                    onSubmit: { prompt in onAction(.write, prompt) },
                    onExpand: onExpand,
                    onBack: {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                            showWrite = false
                        }
                    }
                )
                .transition(.asymmetric(
                    insertion:  .move(edge: .trailing).combined(with: .opacity),
                    removal:    .move(edge: .trailing).combined(with: .opacity)
                ))
            } else {
                actionListView
                    .transition(.asymmetric(
                        insertion:  .move(edge: .leading).combined(with: .opacity),
                        removal:    .move(edge: .leading).combined(with: .opacity)
                    ))
            }
        }
        .frame(width: menuWidth)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        )
        .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 8)
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: showWrite)
    }

    private var actionListView: some View {
        VStack(spacing: 2) {
            HStack {
                Text(selectedText.isEmpty ? "텍스트를 붙여넣기 하세요" : "\(selectedText.count)자 선택됨")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary.opacity(0.75))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 2)

            ForEach(QuickAction.allCases) { action in
                QuickActionRow(action: action, showChevron: action == .write) {
                    if action == .write {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                            showWrite = true
                        }
                    } else {
                        onAction(action, nil)
                    }
                }
            }

            Spacer().frame(height: 6)
        }
        .frame(width: menuWidth)
    }
}
