import SwiftUI
import ServiceManagement
import AppKit

// Agents — hooks for Claude Code, Gemini CLI, Antigravity and Codex, and the
// Claude plan usage relay.

extension SettingsView {

    // MARK: - Agents section

    @ViewBuilder var agentsSection: some View {
        Section("Claude Code Hooks") {
            if hookNeedsUpdate {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Hooks outdated — update them to answer Claude's questions from the notch")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    #if APPSTORE
                    Button("Update hooks") { installHooksAppStore() }
                    #else
                    Button("Update hooks") { installHooks() }
                    #endif
                }
            }
            #if APPSTORE
            HookPathRow(path: "~/.claude/coucou/nb-hook")
            HStack(spacing: 10) {
                Button("Install hooks") { installHooksAppStore() }
                    .buttonStyle(.borderedProminent)
                Button("Uninstall") { uninstallHooksAppStore() }
                    .buttonStyle(.bordered)
            }
            #else
            HookPathRow(path: HookServer.hookScriptPath)
            HStack(spacing: 10) {
                Button("Install hooks") { installHooks() }
                    .buttonStyle(.borderedProminent)
                Button("Uninstall") { uninstallHooks() }
                    .buttonStyle(.bordered)
            }
            #endif

            #if !APPSTORE
            if showDiff {
                HookDiffPreview(json: pendingHookJSON, height: 140)
                HStack(spacing: 10) {
                    Button("Confirm & write") { confirmInstall() }
                        .buttonStyle(.borderedProminent)
                    Button("Cancel") { showDiff = false; pendingHookJSON = "" }
                        .buttonStyle(.bordered)
                }
            }
            #endif
        }

        #if !APPSTORE
        Section("Gemini CLI Hooks") {
            HookStatusRow(text: geminiHooksInstalled
                          ? "Hooks installed — restart Gemini CLI to activate"
                          : "~/.gemini/settings.json")
            HStack(spacing: 10) {
                Button("Install hooks") { triggerGeminiPreview(install: true) }
                    .buttonStyle(.borderedProminent)
                Button("Uninstall") { triggerGeminiPreview(install: false) }
                    .buttonStyle(.bordered)
            }
            if showGeminiDiff {
                HookDiffPreview(json: pendingGeminiJSON, height: 140)
                HStack(spacing: 10) {
                    Button("Confirm & write") { confirmGeminiOp() }
                        .buttonStyle(.borderedProminent)
                    Button("Cancel") { showGeminiDiff = false; pendingGeminiJSON = "" }
                        .buttonStyle(.bordered)
                }
            }
        }

        Section("Antigravity Hooks") {
            HookStatusRow(text: agyHooksInstalled
                          ? "Hooks installed — restart Antigravity to activate"
                          : "~/.gemini/config/hooks.json")
            HStack(spacing: 10) {
                Button("Install hooks") { triggerAgyPreview(install: true) }
                    .buttonStyle(.borderedProminent)
                Button("Uninstall") { triggerAgyPreview(install: false) }
                    .buttonStyle(.bordered)
            }
            if showAgyDiff {
                HookDiffPreview(json: pendingAgyJSON, height: 140)
                HStack(spacing: 10) {
                    Button("Confirm & write") { confirmAgyOp() }
                        .buttonStyle(.borderedProminent)
                    Button("Cancel") { showAgyDiff = false; pendingAgyJSON = "" }
                        .buttonStyle(.bordered)
                }
            }
        }

        Section("Codex Hooks") {
            HookStatusRow(text: codexHooksInstalled
                          ? "Hooks installed — open Codex and run /hooks or open Hooks in the app's settings to trust them"
                          : "~/.codex/hooks.json")
            HStack(spacing: 10) {
                Button("Install hooks") { triggerCodexPreview(install: true) }
                    .buttonStyle(.borderedProminent)
                Button("Uninstall") { triggerCodexPreview(install: false) }
                    .buttonStyle(.bordered)
            }
            if showCodexDiff {
                HookDiffPreview(json: pendingCodexJSON, height: 140)
                HStack(spacing: 10) {
                    Button("Confirm & write") { confirmCodexOp() }
                        .buttonStyle(.borderedProminent)
                    Button("Cancel") { showCodexDiff = false; pendingCodexJSON = "" }
                        .buttonStyle(.bordered)
                }
            }
        }

        Section {
            Toggle("Show in the notch", isOn: Binding(
                    get: { state.showPlanInNotch || planTogglePending },
                    set: { on in
                        if on {
                            if state.planRelayInstalled {
                                state.showPlanInNotch = true
                            } else {
                                planTogglePending = true
                                installStatusLine()
                            }
                        } else {
                            state.showPlanInNotch = false
                            planTogglePending = false
                        }
                    }
                ))
            LabeledContent(state.planRelayInstalled ? "Relay: installed" : "Relay: not installed") {
                if state.planRelayInstalled {
                    Button("Uninstall relay") { uninstallStatusLine() }
                        .buttonStyle(.bordered)
                } else {
                    Button("Install relay") { installStatusLine() }
                        .buttonStyle(.borderedProminent)
                }
            }
            if showStatusLineDiff {
                HookDiffPreview(json: pendingStatusLineJSON, height: 100)
                HStack(spacing: 10) {
                    Button("Confirm & write") { confirmStatusLine() }
                        .buttonStyle(.borderedProminent)
                    Button("Cancel") {
                        showStatusLineDiff = false
                        pendingStatusLineJSON = ""
                        planTogglePending = false
                    }
                    .buttonStyle(.bordered)
                }
            }
        } header: {
            Text("Plan usage")
        } footer: {
            Text("Shows your Claude plan usage (5-hour and weekly limits) in the notch header. Coucou adds a status line relay to ~/.claude/settings.json. If you already have a status line, it keeps working as before. Pro and Max plans only.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        #endif
    }

    // MARK: - App Store: hooks via NSOpenPanel + security-scoped bookmark

    #if APPSTORE
    private func pickClaudeFolder(prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.message = "Select your .claude folder (press ⇧⌘. to show hidden files)"
        panel.prompt = prompt
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        let realHomePath = getpwuid(getuid()).flatMap { String(cString: $0.pointee.pw_dir, encoding: .utf8) }
            ?? "/Users/\(NSUserName())"
        panel.directoryURL = URL(fileURLWithPath: realHomePath)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard url.lastPathComponent == ".claude" else {
            statusMessage = "❌ Select the .claude folder (hidden, in your Home directory)."
            return nil
        }
        return url
    }

    private func installHooksAppStore() {
        guard let claudeURL = pickClaudeFolder(prompt: "Select") else { return }
        let alert = NSAlert()
        alert.messageText = "Install Coucou hooks in ~/.claude?"
        alert.informativeText = "Will write:\n• ~/.claude/coucou/nb-hook\n• ~/.claude/settings.json (backup created first)"
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .informational
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try HookServer.shared.installAndWriteClaudeHooksAppStore(claudeURL: claudeURL)
            hookNeedsUpdate = false
            statusMessage = "✓ Hooks installed — restart VS Code to activate."
        } catch {
            statusMessage = "❌ \(error.localizedDescription)"
        }
    }

    private func uninstallHooksAppStore() {
        guard let claudeURL = pickClaudeFolder(prompt: "Select") else { return }
        do {
            try HookServer.shared.uninstallClaudeHooksAppStore(claudeURL: claudeURL)
            statusMessage = "✓ Hooks removed."
        } catch {
            statusMessage = "❌ \(error.localizedDescription)"
        }
    }
    #endif

    private func installHooks() {
        do {
            pendingHookJSON = try HookServer.shared.previewClaudeHooks()
            showDiff = true
            statusMessage = "Review the JSON below before confirming."
        } catch {
            statusMessage = "❌ \(error.localizedDescription)"
        }
    }

    private func confirmInstall() {
        do {
            try HookServer.shared.writeClaudeHooks()
            showDiff = false
            statusMessage = "✓ Hooks installed in ~/.claude/settings.json"
            pendingHookJSON = ""
            hookNeedsUpdate = false
        } catch {
            statusMessage = "❌ Write error: \(error.localizedDescription)"
        }
    }

    private func uninstallHooks() {
        do {
            try HookServer.shared.uninstallClaudeHooks()
            statusMessage = "✓ Hooks removed."
        } catch {
            statusMessage = "❌ \(error.localizedDescription)"
        }
    }

    #if !APPSTORE
    private func triggerGeminiPreview(install: Bool) {
        do {
            geminiPendingInstall = install
            pendingGeminiJSON = try HookServer.shared.previewGeminiHooks(install: install)
            showGeminiDiff = true
            statusMessage = "Review the JSON below before confirming."
        } catch let e as NSError where e.domain == "CoucouNoop" {
            statusMessage = e.localizedDescription
        } catch {
            statusMessage = "❌ \(error.localizedDescription)"
        }
    }

    private func confirmGeminiOp() {
        do {
            try HookServer.shared.writeGeminiHooks()
            showGeminiDiff = false
            pendingGeminiJSON = ""
            geminiHooksInstalled = geminiPendingInstall
            statusMessage = geminiPendingInstall
                ? "✓ Gemini CLI hooks installed in ~/.gemini/settings.json"
                : "✓ Gemini CLI hooks removed."
        } catch {
            statusMessage = "❌ \(error.localizedDescription)"
        }
    }

    private func triggerAgyPreview(install: Bool) {
        do {
            agyPendingInstall = install
            pendingAgyJSON = try HookServer.shared.previewAgyHooks(install: install)
            showAgyDiff = true
            statusMessage = "Review the JSON below before confirming."
        } catch let e as NSError where e.domain == "CoucouNoop" {
            statusMessage = e.localizedDescription
        } catch {
            statusMessage = "❌ \(error.localizedDescription)"
        }
    }

    private func confirmAgyOp() {
        do {
            try HookServer.shared.writeAgyHooks()
            showAgyDiff = false
            pendingAgyJSON = ""
            agyHooksInstalled = agyPendingInstall
            statusMessage = agyPendingInstall
                ? "✓ Antigravity hooks installed in ~/.gemini/config/hooks.json"
                : "✓ Antigravity hooks removed."
        } catch {
            statusMessage = "❌ \(error.localizedDescription)"
        }
    }

    private func triggerCodexPreview(install: Bool) {
        do {
            codexPendingInstall = install
            pendingCodexJSON = try HookServer.shared.previewCodexHooks(install: install)
            showCodexDiff = true
            statusMessage = "Review the JSON below before confirming."
        } catch let e as NSError where e.domain == "CoucouNoop" {
            statusMessage = e.localizedDescription
        } catch {
            statusMessage = "❌ \(error.localizedDescription)"
        }
    }

    private func confirmCodexOp() {
        do {
            try HookServer.shared.writeCodexHooks()
            showCodexDiff = false
            pendingCodexJSON = ""
            codexHooksInstalled = codexPendingInstall
            statusMessage = codexPendingInstall
                ? "✓ Codex hooks installed — run /hooks in Codex or open Hooks in the app's settings to trust them."
                : "✓ Codex hooks removed."
        } catch {
            statusMessage = "❌ \(error.localizedDescription)"
        }
    }

    private func installStatusLine() {
        do {
            pendingStatusLineJSON = try HookServer.shared.previewStatusLine(install: true)
            showStatusLineDiff = true
            statusLinePendingInstall = true
            statusMessage = "Review the JSON below before confirming."
        } catch {
            statusMessage = "❌ \(error.localizedDescription)"
        }
    }

    private func uninstallStatusLine() {
        do {
            pendingStatusLineJSON = try HookServer.shared.previewStatusLine(install: false)
            showStatusLineDiff = true
            statusLinePendingInstall = false
            statusMessage = "Review the JSON below before confirming."
        } catch {
            statusMessage = "❌ \(error.localizedDescription)"
        }
    }

    private func confirmStatusLine() {
        do {
            try HookServer.shared.writeStatusLine()
            showStatusLineDiff = false
            pendingStatusLineJSON = ""
            state.refreshPlanRelayState()
            if planTogglePending {
                state.showPlanInNotch = true
                planTogglePending = false
            }
            if !statusLinePendingInstall {
                state.showPlanInNotch = false
            }
            statusMessage = statusLinePendingInstall
                ? "✓ Status line installed."
                : "✓ Status line removed."
        } catch {
            planTogglePending = false
            statusMessage = "❌ \(error.localizedDescription)"
        }
    }
    #endif
}
