import SwiftUI
import ServiceManagement
import AppKit

// MARK: - Settings sections (sidebar order, titles and icon tiles)

/// `id` values are persisted in the `settingsSection` user default and sent by
/// `AppDelegate.openSettingsFromNotification` — they are contract values, never rename them.
struct SettingsSectionEntry: Identifiable {
    let id:    String
    let title: String
    let icon:  String
    let color: String

    static let all: [SettingsSectionEntry] = [
        .init(id: "general",      title: "General",      icon: "gearshape.fill",                    color: "#8E939C"),
        .init(id: "activepills",  title: "Active pills", icon: "square.grid.2x2.fill",              color: "#F5A524"),
        .init(id: "agents",       title: "Agents",       icon: "terminal.fill",                     color: "#3B9EFF"),
        .init(id: "chat",         title: "Chat",         icon: "bubble.left.and.bubble.right.fill", color: "#E07950"),
        .init(id: "integrations", title: "Integrations", icon: "puzzlepiece.extension.fill",        color: "#7C5CFF"),
    ]
}

/// The coloured icon tile of the selected section, shown in the window toolbar.
struct SettingsSectionIcon: View {
    let entry: SettingsSectionEntry

    var body: some View {
        Image(systemName: entry.icon)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 20, height: 20)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color(hex: entry.color)))
            .accessibilityHidden(true)
    }
}

// MARK: - Sidebar row (System Settings style icon)

struct SettingsSidebarRow: View {
    let title: String
    let icon: String
    let color: String

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color(hex: color)))
        }
    }
}

// MARK: - Form rows shared by several sections

/// A provider name preceded by its brand dot, used as a Section header or an in-section row.
struct ProviderDot: View {
    let color: String
    let name: String
    var connected: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Color(hex: color)).frame(width: 8, height: 8)
            Text(name)
            if connected {
                Text("Connected")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#22C55E"))
            }
        }
    }
}

/// The explanatory line under a Section. A Form footer is already dimmed and
/// small; this only pins the alignment and lets it wrap.
struct SectionNote: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The path of a hook script. Truncated in the middle rather than wrapped, so a
/// deep path stays readable at the minimum window width, and selectable so it
/// can be copied.
struct HookPathRow: View {
    let path: String

    var body: some View {
        LabeledContent("nb-hook") {
            Text(path)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

/// The one-line state of an agent's hooks: either where they would be written,
/// or what the user has to do next.
struct HookStatusRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The JSON Coucou is about to write, shown before the user confirms.
struct HookDiffPreview: View {
    let json: String
    let height: CGFloat

    var body: some View {
        ScrollView {
            Text(json)
                .font(.system(size: 10, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(6)
        }
        .frame(height: height)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(NSColor.textBackgroundColor))
        )
    }
}

// MARK: - Integration filter row (reusable for Vercel / n8n)

struct IntegrationFilterRow: View {
    let label: String
    let items: [String]
    @Binding var filter: Set<String>
    let loading: Bool
    let onLoad: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent(label) {
                HStack(spacing: 8) {
                    if loading {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(items.isEmpty ? "Load list" : "Refresh") { onLoad() }
                            .buttonStyle(.bordered)
                    }
                    if !filter.isEmpty {
                        Button("Clear") { filter = [] }
                            .buttonStyle(.bordered)
                    }
                }
            }
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(items, id: \.self) { item in
                        Toggle(item, isOn: Binding(
                            get: { filter.isEmpty || filter.contains(item) },
                            set: { on in
                                if on { filter.insert(item) }
                                else  {
                                    if filter.isEmpty { filter = Set(items).subtracting([item]) }
                                    else { filter.remove(item) }
                                    if filter.count == items.count { filter = [] }
                                }
                            }
                        ))
                        .font(.system(size: 11))
                        .toggleStyle(.checkbox)
                    }
                }
                if !filter.isEmpty {
                    Text("Watching \(filter.count) of \(items.count)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Shortcut recorder button

struct ShortcutRecorderButton: View {
    @Binding var flags: UInt
    @Binding var code: UInt16
    @State private var isRecording = false

    var body: some View {
        Button {
            guard !isRecording else { return }
            isRecording = true
            var token: Any?
            token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
                guard !mods.isEmpty else { return event }
                DispatchQueue.main.async {
                    self.flags = mods.rawValue
                    self.code = event.keyCode
                    self.isRecording = false
                    if let t = token { NSEvent.removeMonitor(t) }
                }
                return nil
            }
        } label: {
            Text(isRecording ? "Press keys…" : shortcutLabel)
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(isRecording ? Color.accentColor.opacity(0.12) : Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var shortcutLabel: String {
        let f = NSEvent.ModifierFlags(rawValue: flags)
        var s = ""
        if f.contains(.control) { s += "⌃" }
        if f.contains(.option)  { s += "⌥" }
        if f.contains(.shift)   { s += "⇧" }
        if f.contains(.command) { s += "⌘" }
        s += keyChar(code)
        return s.isEmpty ? "None" : s
    }

    private func keyChar(_ c: UInt16) -> String {
        let map: [UInt16: String] = [
            0:"A", 1:"S", 2:"D", 3:"F", 4:"H", 5:"G", 6:"Z", 7:"X", 8:"C", 9:"V",
            11:"B", 12:"Q", 13:"W", 14:"E", 15:"R", 16:"Y", 17:"T", 31:"O", 32:"U",
            34:"I", 37:"L", 38:"J", 40:"K", 45:"N", 46:"M", 49:"Space", 50:"`", 27:"-"
        ]
        return map[c] ?? "·"
    }
}
