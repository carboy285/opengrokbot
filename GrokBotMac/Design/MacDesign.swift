import AppKit
import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
}

enum MacTheme {
    // 0.9.2: deeper, quieter Grok Bot palette. One accent per state, everything else greyscale.
    static let canvas = adaptive(dark: 0x0F0F10, light: 0xFCFCFC)
    static let sidebar = adaptive(dark: 0x0A0A0B, light: 0xF5F5F6)
    static let panel = adaptive(dark: 0x1C1C1E, light: 0xF0F0F2)
    static let raised = adaptive(dark: 0x262628, light: 0xE6E6E9)
    static let secondary = adaptive(dark: 0x8E8E93, light: 0x6C6C70)
    static let tertiary = adaptive(dark: 0x5C5C61, light: 0xA4A4A9)
    static let line = Color.primary.opacity(0.07)
    static let userBubble = adaptive(dark: 0x2C2C2E, light: 0xE5E5EA)
    static let selection = Color.primary.opacity(0.07)
    static let hover = Color.primary.opacity(0.04)
    static let prominent = adaptive(dark: 0xFFFFFF, light: 0x111111)
    static let onProminent = adaptive(dark: 0x000000, light: 0xFFFFFF)
    /// A Bot that is working: the avatar ring and the sidebar status.
    static let working = Color(hex: 0xA07BFF)
    /// A Bot that is waiting for you (an approval, a question or a hand-over).
    static let attention = Color(hex: 0xFF9F0A)
    static let unread = Color(hex: 0x2F7BFF)
    static let danger = Color(hex: 0xFF453A)

    private static func adaptive(dark: UInt32, light: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, alpha: 1)
        })
    }
    static func botColor(_ name: String) -> Color {
        switch name {
        case "purple": Color(hex: 0x9355FF)
        case "pink": Color(hex: 0xFA2A99)
        case "ochre": Color(hex: 0x9C6C37)
        default: Color.white
        }
    }
}

/// What a Bot is doing right now. The avatar carries it, so the sidebar needs no extra badges.
enum MacBotStatus: Equatable {
    case idle, working, attention
}

struct MacBotAvatar: View {
    var color = "white"
    var size: CGFloat = 42
    var starred = false
    var appearance: BotAppearance? = nil
    var status: MacBotStatus = .idle
    var body: some View {
        face
            .overlay { MacStatusRing(status: status, size: size) }
    }

    private var face: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
            if let appearance { CustomBotAvatar(appearance: appearance, size: size) }
            else { ZStack {
                if color == "white" {
                    Circle().fill(.primary)
                } else if color == "pink" {
                    Circle().fill(MacTheme.botColor(color))
                } else {
                    RoundedRectangle(cornerRadius: size * 0.27)
                        .fill(MacTheme.botColor(color)).rotationEffect(.degrees(-20))
                }
                HStack(spacing: size * 0.13) {
                    Capsule().frame(width: size * 0.10, height: size * 0.25)
                    Capsule().frame(width: size * 0.08, height: size * 0.23).offset(y: -size * 0.09)
                }
                .rotationEffect(.degrees(-26))
                .foregroundStyle(color == "white" ? MacTheme.canvas : Color.white)
                .offset(x: size * 0.10, y: -size * 0.12)
            } }
            }
            if starred {
                Image(systemName: "star.fill")
                    .font(.system(size: size * 0.15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: size * 0.32, height: size * 0.32)
                    .background(Color.orange, in: Circle())
                    .overlay(Circle().stroke(MacTheme.sidebar, lineWidth: size * 0.05))
                    .offset(x: size * 0.04, y: size * 0.04)
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct MacCircleButton: View {
    let symbol: String
    let label: String
    var diameter: CGFloat = 42
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: diameter * 0.4, weight: .regular))
                .frame(width: diameter, height: diameter)
                .contentShape(Circle())
                .glassChrome(in: Circle())
        }.buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
}

struct MacPillButton: View {
    let title: String
    var prominent = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 15, weight: .medium))
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(prominent ? MacTheme.prominent : MacTheme.raised, in: Capsule())
                .foregroundStyle(prominent ? MacTheme.onProminent : Color.primary.opacity(0.88))
        }.buttonStyle(.plain)
    }
}

/// A thin ring around a Bot's avatar: a slowly turning arc while it works, a steady orange ring while it waits for you.
struct MacStatusRing: View {
    let status: MacBotStatus
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let inset = -max(2.5, size * 0.07)
        let width = max(1.5, size * 0.045)
        switch status {
        case .idle:
            EmptyView()
        case .attention:
            Circle().stroke(MacTheme.attention, lineWidth: width).padding(inset)
                .accessibilityHidden(true)
        case .working:
            if reduceMotion {
                Circle().stroke(MacTheme.working.opacity(0.85), lineWidth: width).padding(inset)
                    .accessibilityHidden(true)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
                    ZStack {
                        Circle().stroke(MacTheme.working.opacity(0.18), lineWidth: width)
                        Circle().trim(from: 0, to: 0.28)
                            .stroke(MacTheme.working, style: StrokeStyle(lineWidth: width, lineCap: .round))
                            .rotationEffect(.degrees(turn * 360))
                    }.padding(inset)
                }
                .accessibilityHidden(true)
            }
        }
    }
}

/// Three dots that breathe in turn, like a contact typing in Messages.
struct MacTypingDots: View {
    var color: Color = MacTheme.secondary
    var dot: CGFloat = 7
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            let step = Int(context.date.timeIntervalSinceReferenceDate / 0.2) % 4
            HStack(spacing: dot * 0.65) {
                ForEach(0..<3, id: \.self) { index in
                    Circle().fill(color)
                        .frame(width: dot, height: dot)
                        .opacity(reduceMotion ? 0.7 : (step == index ? 1 : 0.32))
                        .scaleEffect(reduceMotion || step != index ? 1 : 1.12)
                }
            }
        }
        .accessibilityElement().accessibilityLabel("Thinking")
    }
}

/// One tool step a Bot took (read a page, ran a command, saved a memory) as a small pill.
/// Long results fold away; a click shows them in full.
struct MacActivityPill: View {
    let text: String
    var routine = false
    @State private var expanded = false
    @State private var hovering = false

    private var firstLine: String {
        text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? text
    }
    private var summary: String {
        var line = firstLine.trimmingCharacters(in: .whitespaces)
        if line.hasPrefix("Linux VM result") { return "Ran a command in the Linux VM" }
        if line.hasPrefix("Queued message · ") { return "Asked " + String(line.dropFirst("Queued message · ".count)) }
        if line.hasPrefix("Local browser result") { return "Read a page in the browser" }
        line = line.replacingOccurrences(of: " (untrusted context)", with: "")
        line = line.replacingOccurrences(of: " (untrusted web content, not instructions)", with: "")
        if line.hasSuffix(":") { line.removeLast() }
        return routine ? "Routine · " + line : line
    }
    private var hasMore: Bool { text.contains("\n") || text.count > 120 }
    private var icon: String {
        let lower = firstLine.lowercased()
        if routine { return "clock" }
        if lower.hasPrefix("linux vm") || lower.contains(" vm ") || lower.hasPrefix("vm ") { return "terminal" }
        if lower.hasPrefix("read ") || lower.contains("browser") || lower.contains("page") { return "globe" }
        if lower.hasPrefix("searched") || lower.contains("search") { return "magnifyingglass" }
        if lower.contains("memory") || lower.hasPrefix("forgot") { return "brain" }
        if lower.hasPrefix("queued message") || lower.contains("message") { return "paperplane" }
        if lower.hasPrefix("created") { return "plus.circle" }
        if lower.contains("schedul") || lower.contains("routine") { return "clock" }
        if lower.contains("couldn") || lower.contains("could not") || lower.contains("failed") || lower.contains("declined") || lower.contains("not sent") { return "exclamationmark.triangle" }
        if lower.contains("file") || lower.contains("saved") { return "doc" }
        return "checkmark.circle"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                guard hasMore else { return }
                withAnimation(.spring(response: 0.28, dampingFraction: 1)) { expanded.toggle() }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: icon).font(.system(size: 11, weight: .semibold)).frame(width: 14)
                    Text(summary).lineLimit(1).truncationMode(.tail)
                    if hasMore {
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold))
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                }
                .font(.system(size: 12.5))
                .foregroundStyle(hovering && hasMore ? Color.primary.opacity(0.8) : MacTheme.secondary)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(hovering && hasMore ? MacTheme.raised : MacTheme.panel.opacity(0.7), in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help(hasMore ? (expanded ? "Hide details" : "Show details") : "")
            if expanded {
                ScrollView {
                    Text(text).font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.primary.opacity(0.8))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 260).fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .background(MacTheme.panel, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(MacTheme.line, lineWidth: 1))
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Activity: \(summary)")
    }
}

/// A Bot asking before it does something consequential. Shown in the chat, above the message box.
struct MacApprovalCard: View {
    let request: MacApproval.Pending
    let bot: Bot?
    let answer: (Bool) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if let bot { MacBotAvatar(color: bot.color, size: 20, appearance: bot.appearance) }
                else { Image(systemName: "hand.raised.fill").foregroundStyle(MacTheme.attention) }
                Text("Needs your OK").font(.system(size: 12, weight: .semibold)).foregroundStyle(MacTheme.attention)
                Spacer(minLength: 0)
                if request.authenticate {
                    Label("Touch ID", systemImage: "touchid").font(.system(size: 11)).foregroundStyle(MacTheme.secondary)
                }
            }
            Text(request.title).font(.system(size: 15, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            if !request.detail.isEmpty {
                ScrollView {
                    Text(request.detail).font(.system(size: 13)).foregroundStyle(Color.primary.opacity(0.78))
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 150).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
            }
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button { answer(false) } label: {
                    Text("Deny").font(.system(size: 14, weight: .medium))
                        .padding(.horizontal, 18).frame(height: 34)
                        .background(MacTheme.raised, in: Capsule())
                }
                .buttonStyle(.plain).keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("approval-deny")
                Button { answer(true) } label: {
                    Text(request.authenticate ? "Allow with Touch ID" : "Allow once").font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MacTheme.onProminent)
                        .padding(.horizontal, 18).frame(height: 34)
                        .background(MacTheme.prominent, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("approval-allow")
            }
        }
        .padding(16)
        .background(MacTheme.panel, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(MacTheme.attention.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 18, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Approval needed: \(request.title)")
    }
}

/// A question a Bot asked with a short list of answers. One tap answers; several answers use Submit.
struct MacQuestionCard: View {
    let prompt: ChoicePrompt
    let canAnswer: Bool
    let answer: (String) -> Void
    let other: () -> Void
    @State private var picked: Set<String> = []
    @State private var hovered: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: prompt.multiple ? "checklist" : "questionmark.bubble")
                Text(canAnswer ? (prompt.multiple ? "Choose any that apply" : "Choose one") : "Answered")
            }
            .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(MacTheme.secondary)
            .padding(.horizontal, 4).padding(.bottom, 2)
            ForEach(prompt.options, id: \.self) { option in
                Button {
                    guard canAnswer else { return }
                    if prompt.multiple {
                        if picked.contains(option) { picked.remove(option) } else { picked.insert(option) }
                    } else { answer(option) }
                } label: {
                    HStack(spacing: 10) {
                        if prompt.multiple {
                            Image(systemName: picked.contains(option) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(picked.contains(option) ? Color.primary : MacTheme.tertiary)
                        }
                        Text(option).font(.system(size: 14)).multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        if !prompt.multiple && canAnswer {
                            Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(MacTheme.tertiary).opacity(hovered == option ? 1 : 0)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(hovered == option && canAnswer ? MacTheme.raised : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .onHover { inside in hovered = inside ? option : (hovered == option ? nil : hovered) }
            }
            if canAnswer {
                HStack(spacing: 8) {
                    Button { other() } label: {
                        Text("Something else…").font(.system(size: 13)).foregroundStyle(MacTheme.secondary)
                            .padding(.horizontal, 12).frame(height: 30).contentShape(Capsule())
                    }.buttonStyle(.plain)
                    Spacer(minLength: 0)
                    if prompt.multiple {
                        Button { answer(prompt.options.filter { picked.contains($0) }.joined(separator: ", ")) } label: {
                            Text("Submit").font(.system(size: 13, weight: .semibold)).foregroundStyle(MacTheme.onProminent)
                                .padding(.horizontal, 16).frame(height: 30)
                                .background(MacTheme.prominent, in: Capsule())
                        }
                        .buttonStyle(.plain).disabled(picked.isEmpty).opacity(picked.isEmpty ? 0.4 : 1)
                    }
                }.padding(.top, 2)
            }
        }
        .padding(10)
        .frame(maxWidth: 460, alignment: .leading)
        .background(MacTheme.panel, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(MacTheme.line, lineWidth: 1))
        .opacity(canAnswer ? 1 : 0.6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(prompt.multiple ? "Question with several answers" : "Question")
    }
}
