import SwiftUI
import Combine

struct ChatBubble: View {
    enum Sender { case me, ai }
    let from: Sender
    var soft: Bool = false
    let text: String

    var body: some View {
        HStack {
            if from == .me { Spacer(minLength: 60) }
            Text(text)
                .font(.custom(T.fontHeader, size: 15).weight(.semibold))
                .lineSpacing(3)
                .foregroundColor(from == .me ? T.bg : T.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(bubbleBg)
                .clipShape(bubbleShape)
                .shadow(
                    color: from == .me ? .clear : Color(red: 40/255, green: 30/255, blue: 20/255).opacity(0.05),
                    radius: 4, x: 0, y: 2
                )
            if from == .ai { Spacer(minLength: 60) }
        }
    }

    private var bubbleBg: Color {
        from == .me ? T.text : (soft ? Cat.personal.bg : T.surface)
    }

    private var bubbleShape: UnevenRoundedRectangle {
        if from == .me {
            UnevenRoundedRectangle(
                topLeadingRadius: 18, bottomLeadingRadius: 18,
                bottomTrailingRadius: 6, topTrailingRadius: 18
            )
        } else {
            UnevenRoundedRectangle(
                topLeadingRadius: 18, bottomLeadingRadius: 6,
                bottomTrailingRadius: 18, topTrailingRadius: 18
            )
        }
    }
}

// MARK: - Chat message model

struct ChatMessage: Identifiable {
    let id = UUID()
    let from: ChatBubble.Sender
    let text: String
}

struct AddTaskAskAIView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var messages: [ChatMessage] = []
    @State private var replyText = ""
    @State private var isLoading = false
    @State private var suggestedTask: String?
    @FocusState private var inputFocused: Bool
    var onTaskCreated: (String) -> Void = { _ in }

    private let apiClient = ClaudeAPIClient()

    private let quickReplies = ["Work stuff", "Home / chores", "My body / health", "People / social"]

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.top, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(messages) { msg in
                            ChatBubble(from: msg.from, soft: msg.from == .ai && msg.id == messages.first?.id, text: msg.text)
                        }

                        if isLoading {
                            HStack {
                                TypingIndicator()
                                Spacer(minLength: 60)
                            }
                        }

                        if messages.count == 1 {
                            quickReplyChips
                                .padding(.top, 10)
                        }

                        if let task = suggestedTask {
                            suggestionCard(task: task)
                                .padding(.top, 8)
                        }

                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                }
                .onChange(of: messages.count) {
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onChange(of: isLoading) {
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }

            composerBar
        }
        .background(T.bg.ignoresSafeArea())
        .onAppear {
            startConversation()
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(T.text)
                    .frame(width: 38, height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(T.surface)
                    )
                    .tempaShadowSm()
            }

            Spacer()

            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(lightHex: "#FFE9E1", darkHex: "#2C1F18"), Color(lightHex: "#D6F0E7", darkHex: "#16302A")],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(T.primary)
                    )

                Text("Ask Tempa")
                    .font(.custom(T.fontHeader, size: 17).weight(.heavy))
                    .foregroundColor(T.text)
            }

            Spacer()
            Color.clear.frame(width: 38, height: 38)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    // MARK: - Quick Reply Chips

    private var quickReplyChips: some View {
        FlowLayout(spacing: 8) {
            ForEach(Array(quickReplies.enumerated()), id: \.offset) { _, reply in
                Button {
                    #if os(iOS)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    sendMessage(reply)
                } label: {
                    Text(reply)
                        .font(.custom(T.fontHeader, size: 13).weight(.bold))
                        .foregroundColor(T.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(T.surface)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.black.opacity(0.05), lineWidth: 1)
                        }
                        .shadow(
                            color: Color(red: 40/255, green: 30/255, blue: 20/255).opacity(0.05),
                            radius: 4, x: 0, y: 2
                        )
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
            }
        }
    }

    // MARK: - Suggestion Card

    private func suggestionCard(task: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TEMPA SUGGESTS")
                .font(.custom(T.fontHeader, size: 11).weight(.heavy))
                .tracking(1.5)
                .foregroundColor(T.primary)

            Text(task)
                .font(.custom(T.fontHeader, size: 19).weight(.heavy))
                .tracking(-0.2)
                .foregroundColor(T.text)
                .lineSpacing(2)

            HStack(spacing: 8) {
                TempaButton(label: "Use this", variant: .primary, size: .sm, showArrow: true) {
                    onTaskCreated(task)
                    dismiss()
                }
                .frame(maxWidth: .infinity)

                TempaButton(label: "Not quite", variant: .ghost, size: .sm) {
                    suggestedTask = nil
                    sendMessage("Not quite — can you suggest something else?")
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 6)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(lightHex: "#FFE9E1", darkHex: "#2C1F18"), T.bg],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color(hex: "#FF7A59").opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Composer Bar

    private var composerBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TextField("Type a reply…", text: $replyText)
                    .font(.custom(T.fontHeader, size: 15).weight(.semibold))
                    .foregroundColor(T.text)
                    .focused($inputFocused)
                    .onSubmit { sendTypedMessage() }

                Button {
                    sendTypedMessage()
                } label: {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(replyText.isEmpty ? T.textTer : T.primary)
                        )
                }
                .disabled(replyText.isEmpty || isLoading)
            }
            .padding(.leading, 18)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(T.surface)
            )
            .tempaShadowSm()
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 38)
        .background(
            LinearGradient(
                colors: [T.bg.opacity(0), T.bg],
                startPoint: .top, endPoint: .init(x: 0.5, y: 0.3)
            )
        )
    }

    // MARK: - Logic

    private func startConversation() {
        let greeting = "Hey — let's untangle this. What feels heaviest right now?"
        messages.append(ChatMessage(from: .ai, text: greeting))
    }

    private func sendTypedMessage() {
        guard !replyText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let text = replyText
        replyText = ""
        sendMessage(text)
    }

    private func sendMessage(_ text: String) {
        messages.append(ChatMessage(from: .me, text: text))
        isLoading = true
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif

        Task {
            do {
                // The API rejects a conversation that OPENS with an assistant
                // turn — our greeting is UI-only, so drop leading AI messages.
                let apiMessages = messages.drop(while: { $0.from == .ai }).map { msg -> (role: String, content: String) in
                    (role: msg.from == .me ? "user" : "assistant", content: msg.text)
                }
                let response = try await apiClient.chat(messages: apiMessages)

                // Check if response contains a task suggestion
                if response.hasPrefix("TASK:") {
                    let lines = response.components(separatedBy: "\n")
                    let taskTitle = lines[0]
                        .replacingOccurrences(of: "TASK:", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    let explanation = lines.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespaces)

                    if !explanation.isEmpty {
                        messages.append(ChatMessage(from: .ai, text: explanation))
                    }
                    suggestedTask = taskTitle
                } else {
                    messages.append(ChatMessage(from: .ai, text: response))
                }
            } catch {
                messages.append(ChatMessage(from: .ai, text: "Sorry, I hit a snag. Try telling me what area feels heaviest — work, home, or body?"))
            }
            isLoading = false
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        }
    }
}

// MARK: - Typing Indicator

private struct TypingIndicator: View {
    @State private var dotIndex = 0
    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(T.textTer)
                    .frame(width: 8, height: 8)
                    .opacity(dotIndex == i ? 1 : 0.4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            UnevenRoundedRectangle(
                topLeadingRadius: 18, bottomLeadingRadius: 6,
                bottomTrailingRadius: 18, topTrailingRadius: 18
            )
            .fill(T.surface)
        )
        .shadow(color: Color(red: 40/255, green: 30/255, blue: 20/255).opacity(0.05), radius: 4, x: 0, y: 2)
        .onReceive(timer) { _ in
            dotIndex = (dotIndex + 1) % 3
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, offset) in result.offsets.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (offsets: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var offsets: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            offsets.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
        }
        return (offsets, CGSize(width: maxX, height: y + rowHeight))
    }
}

#Preview {
    AddTaskAskAIView()
}
