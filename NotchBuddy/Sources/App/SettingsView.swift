import SwiftUI
import ServiceManagement
import AppKit

struct SettingsView: View {
    @ObservedObject private var state = AppState.shared
    @State private var apiKey: String = KeychainStore.shared.get("anthropic-api-key") ?? ""

    // Claude model — dynamic list fetched from the API, static fallback if unavailable
    private static let fallbackModels: [(id: String, label: String)] = [
        ("claude-sonnet-4-6",         "Claude Sonnet 4.6"),
        ("claude-sonnet-5-5",         "Claude Sonnet 5.5"),
        ("claude-opus-5-5",           "Claude Opus 5.5"),
        ("claude-haiku-4-5-20251001", "Claude Haiku 4.5"),
    ]
    private static let customModelTag = "__custom__"
    @State private var fetchedModels: [(id: String, label: String)] = []
    @State private var modelChoice: String = {
        let m = AppState.shared.claudeModel
        return SettingsView.fallbackModels.contains { $0.id == m } ? m : SettingsView.customModelTag
    }()
    @State private var customModel: String = {
        let m = AppState.shared.claudeModel
        return SettingsView.fallbackModels.contains { $0.id == m } ? "" : m
    }()
    private var displayModels: [(id: String, label: String)] {
        fetchedModels.isEmpty ? Self.fallbackModels : fetchedModels
    }
    @State private var launchAtStartup: Bool = (SMAppService.mainApp.status == .enabled)
    @State private var statusMessage: String = ""
    @State private var showDiff: Bool = false
    @State private var pendingHookJSON: String = ""
    @State private var hookNeedsUpdate: Bool = HookServer.hooksNeedUpdate()

    #if !APPSTORE
    @State private var showStatusLineDiff: Bool = false
    @State private var pendingStatusLineJSON: String = ""
    @State private var statusLinePendingInstall: Bool = true
    @State private var planTogglePending: Bool = false

    @State private var geminiHooksInstalled: Bool = HookServer.geminiHooksInstalled()
    @State private var showGeminiDiff: Bool = false
    @State private var pendingGeminiJSON: String = ""
    @State private var geminiPendingInstall: Bool = true

    @State private var agyHooksInstalled: Bool = HookServer.agyHooksInstalled()
    @State private var showAgyDiff: Bool = false
    @State private var pendingAgyJSON: String = ""
    @State private var agyPendingInstall: Bool = true

    @State private var codexHooksInstalled: Bool = HookServer.codexHooksInstalled()
    @State private var showCodexDiff: Bool = false
    @State private var pendingCodexJSON: String = ""
    @State private var codexPendingInstall: Bool = true
    #endif

    // Multi-provider chat keys
    @State private var googleKey: String  = KeychainStore.shared.get("google-api-key") ?? ""
    @State private var openAIKey: String  = KeychainStore.shared.get("openai-api-key") ?? ""
    @State private var ollamaURL:    String = AppState.shared.ollamaServerURL
    @State private var lmstudioURL:  String = AppState.shared.lmstudioServerURL
    @State private var connectingOllama:    Bool = false
    @State private var connectingLMStudio:  Bool = false

    // Integration keys
    @State private var resendKey: String    = KeychainStore.shared.get("resend-api-key")  ?? ""
    @State private var resendFrom: String   = KeychainStore.shared.get("resend-from")     ?? ""
    @State private var n8nUrl: String       = KeychainStore.shared.get("n8n-url")         ?? ""
    @State private var n8nKey: String       = KeychainStore.shared.get("n8n-api-key")     ?? ""
    @State private var vercelToken: String  = KeychainStore.shared.get("vercel-token")    ?? ""
    @State private var githubToken: String  = KeychainStore.shared.get("github-token")    ?? ""
    @State private var stripeKey: String    = KeychainStore.shared.get("stripe-api-key")  ?? ""
    @State private var calcomKey: String    = KeychainStore.shared.get("calcom-api-key")  ?? ""
    @State private var notionKey: String    = KeychainStore.shared.get("notion-api-key")  ?? ""

    // Hotkey
    @State private var hotkeyFlags: UInt    = AppState.shared.hotkeyFlags
    @State private var hotkeyCode: UInt16   = AppState.shared.hotkeyCode

    // Vercel project filter
    @State private var vercelProjects: [String] = []
    @State private var loadingVercel: Bool = false

    // n8n workflow filter
    @State private var n8nWorkflows: [String] = []
    @State private var loadingN8n: Bool = false

    // Bindings in minutes for the absence field
    private var absenceMinutes: Binding<Double> {
        Binding(
            get: { state.absenceInterval / 60 },
            set: { state.absenceInterval = max(1, $0) * 60 }
        )
    }

    // Sidebar selection persisted across sessions
    @AppStorage("settingsSection") private var selectedSection: String = "general"

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    // MARK: - Body

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 215)
        } detail: {
            detail
        }
        .onAppear {
            #if !APPSTORE
            state.refreshPlanRelayState()
            #endif
            guard fetchedModels.isEmpty,
                  let key = KeychainStore.shared.get("anthropic-api-key"), !key.isEmpty else { return }
            Task {
                let models = await ClaudeService.fetchModels(apiKey: key)
                guard !models.isEmpty else { return }
                await MainActor.run {
                    fetchedModels = models
                    let m = state.claudeModel
                    if models.contains(where: { $0.id == m }) {
                        modelChoice = m
                        customModel = ""
                    } else if modelChoice != Self.customModelTag {
                        modelChoice = Self.customModelTag
                        customModel = m
                    }
                }
            }
        }
    }

    // MARK: - Chrome

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandHeader
            Divider()
            List(selection: Binding(
                get: { Optional(selectedSection) },
                set: { if let v = $0 { selectedSection = v; statusMessage = "" } }
            )) {
                ForEach(SettingsSectionEntry.all) { entry in
                    SettingsSidebarRow(title: entry.title, icon: entry.icon, color: entry.color)
                        .tag(entry.id)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
    }

    private var brandHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text("Coucou")
                    .font(.system(size: 13, weight: .semibold))
                Text(appVersion)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private var detail: some View {
        VStack(spacing: 0) {
            Form {
                sectionContent
            }
            .formStyle(.grouped)
            statusBanner
        }
        .navigationTitle(currentSection.title)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                SettingsSectionIcon(entry: currentSection)
            }
        }
    }

    @ViewBuilder private var statusBanner: some View {
        if !statusMessage.isEmpty {
            HStack(spacing: 0) {
                Text(statusMessage)
                    .font(.system(size: 12))
                    .foregroundColor(statusMessage.hasPrefix("❌") ? .red : .secondary)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(NSColor.unemphasizedSelectedContentBackgroundColor))
            )
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
        }
    }

    // MARK: - Section routing

    private var currentSection: SettingsSectionEntry {
        SettingsSectionEntry.all.first { $0.id == selectedSection } ?? SettingsSectionEntry.all[0]
    }

    @ViewBuilder private var sectionContent: some View {
        switch selectedSection {
        case "activepills":  activePillsSection
        case "agents":       agentsSection
        case "chat":         chatSection
        case "integrations": integrationsSection
        default:             generalSection
        }
    }

    // MARK: - General section

    @ViewBuilder private var generalSection: some View {
        Section("Sound") {
            Toggle("Enable sounds", isOn: $state.soundEnabled)
            LabeledContent("Volume") {
                HStack(spacing: 10) {
                    Slider(value: $state.soundVolume, in: 0...0.2)
                        .frame(minWidth: 140)
                        .disabled(!state.soundEnabled)
                    Text("\(Int(state.soundVolume / 0.2 * 100)) %")
                        .frame(width: 40, alignment: .trailing)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }

        Section("Behavior") {
            LabeledContent("Close after") {
                HStack(spacing: 6) {
                    TextField("60", value: $state.autoCloseInterval, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 64)
                    Text("s inactive")
                        .foregroundStyle(.secondary)
                }
            }
            LabeledContent("Hide after") {
                HStack(spacing: 6) {
                    TextField("3", value: absenceMinutes, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 64)
                    Text("min without movement")
                        .foregroundStyle(.secondary)
                }
            }
        }

        Section("Hotkey") {
            Toggle("Show island with shortcut", isOn: $state.hotkeyEnabled)
            if state.hotkeyEnabled {
                LabeledContent("Shortcut") {
                    HStack(spacing: 8) {
                        ShortcutRecorderButton(flags: $hotkeyFlags, code: $hotkeyCode)
                            .onChange(of: hotkeyFlags) { _, v in state.hotkeyFlags = v }
                            .onChange(of: hotkeyCode)  { _, v in state.hotkeyCode  = v }
                        Text("presses this → island opens")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }

        Section("Startup") {
            Toggle("Launch at Mac startup", isOn: $launchAtStartup)
                .onChange(of: launchAtStartup) { _, on in toggleStartup(on) }
        }
    }

    // MARK: - Active pills section

    @ViewBuilder private var activePillsSection: some View {
        Section {
            Picker("Main", selection: $state.mainPillId) {
                ForEach(PillCatalog.available.filter { $0.category == .workspace && !$0.comingSoon }, id: \.id) { def in
                    Text(def.name).tag(def.id)
                }
            }
            .onChange(of: state.mainPillId) { _, newId in
                state.activeIntegrations.remove(newId)
                state.loadIntegrationTasks()
                state.setFocus(newId)
            }
        } footer: {
            VStack(alignment: .leading, spacing: 3) {
                Text("Choose the tools you use. Coucou only shows what you declare here.")
                    .foregroundStyle(.secondary)
                Text("\(state.activeIntegrations.count)/4 slots used")
                    .foregroundStyle(state.activeIntegrations.count >= 4 ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
            }
            .font(.system(size: 11))
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        ForEach(PillCategory.allCases, id: \.self) { cat in
            let catPills = PillCatalog.available.filter { $0.category == cat }
            if !catPills.isEmpty {
                Section(cat.title) {
                    ForEach(catPills, id: \.id) { def in
                        pillRow(def)
                    }
                }
            }
        }
    }

    // MARK: - Agents section

    @ViewBuilder private var agentsSection: some View {
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

    // MARK: - Chat section

    @ViewBuilder private var chatSection: some View {
        Section {
            LabeledContent("API key") {
                HStack(spacing: 8) {
                    SecureField("sk-ant-…", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                    Button("Save") {
                        KeychainStore.shared.set("anthropic-api-key", value: apiKey)
                        statusMessage = "✓ Key saved."
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            Picker("Model", selection: $modelChoice) {
                ForEach(displayModels, id: \.id) { preset in
                    Text(preset.label).tag(preset.id)
                }
                Text("Custom…").tag(Self.customModelTag)
            }
            .onChange(of: modelChoice) { _, choice in
                if choice != Self.customModelTag {
                    state.claudeModel = choice
                } else {
                    applyCustomModel(customModel)
                }
            }
            if modelChoice == Self.customModelTag {
                LabeledContent("Model ID") {
                    TextField("claude-sonnet-4-6", text: $customModel)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: customModel) { _, value in applyCustomModel(value) }
                }
            }
        } header: {
            Text("Anthropic API")
        } footer: {
            SectionNote("Used by the chat. The list comes from your Anthropic account.")
        }

        Section {
            ProviderDot(color: "#4285F4", name: "Google AI")
            LabeledContent("API key") {
                HStack(spacing: 8) {
                    SecureField("AI Studio", text: $googleKey)
                        .textFieldStyle(.roundedBorder)
                    Button("Save") {
                        KeychainStore.shared.set("google-api-key", value: googleKey)
                        statusMessage = "✓ Google key saved."
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            ProviderDot(color: "#10A37F", name: "OpenAI")
            LabeledContent("API key") {
                HStack(spacing: 8) {
                    SecureField("sk-…", text: $openAIKey)
                        .textFieldStyle(.roundedBorder)
                    Button("Save") {
                        KeychainStore.shared.set("openai-api-key", value: openAIKey)
                        statusMessage = "✓ OpenAI key saved."
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        } header: {
            Text("Chat — other providers")
        } footer: {
            SectionNote("To use Google Gemini or OpenAI from the chat. Keys are stored in the Keychain.")
        }

        Section {
            ProviderDot(color: "#FACC15", name: "Ollama", connected: !state.ollamaServerURL.isEmpty)
            if state.ollamaServerURL.isEmpty {
                LabeledContent("Server") {
                    HStack(spacing: 8) {
                        TextField("http://127.0.0.1:11434", text: $ollamaURL)
                            .textFieldStyle(.roundedBorder)
                        Button(connectingOllama ? "Connecting…" : "Connect") {
                            Task { await connectLocal(provider: .ollama) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(connectingOllama)
                    }
                }
            } else {
                LabeledContent("Server") {
                    HStack(spacing: 8) {
                        Text(state.ollamaServerURL)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Button("Disconnect") {
                            state.ollamaServerURL = ""
                            ollamaURL = ""
                            state.fetchedProviderModels[.ollama] = nil
                            state.providerModelFetchError[.ollama] = nil
                            if state.chatProvider == .ollama { state.chatProvider = .anthropic }
                            statusMessage = "Ollama disconnected."
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            ProviderDot(color: "#A3E635", name: "LM Studio", connected: !state.lmstudioServerURL.isEmpty)
            if state.lmstudioServerURL.isEmpty {
                LabeledContent("Server") {
                    HStack(spacing: 8) {
                        TextField("http://127.0.0.1:1234", text: $lmstudioURL)
                            .textFieldStyle(.roundedBorder)
                        Button(connectingLMStudio ? "Connecting…" : "Connect") {
                            Task { await connectLocal(provider: .lmstudio) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(connectingLMStudio)
                    }
                }
            } else {
                LabeledContent("Server") {
                    HStack(spacing: 8) {
                        Text(state.lmstudioServerURL)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Button("Disconnect") {
                            state.lmstudioServerURL = ""
                            lmstudioURL = ""
                            state.fetchedProviderModels[.lmstudio] = nil
                            state.providerModelFetchError[.lmstudio] = nil
                            if state.chatProvider == .lmstudio { state.chatProvider = .anthropic }
                            statusMessage = "LM Studio disconnected."
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        } header: {
            Text("Local models")
        } footer: {
            SectionNote("Connect to a local model server. No API key needed.")
        }
    }

    // MARK: - Integrations section

    @ViewBuilder private var integrationsSection: some View {
        Section {
            LabeledContent("API key") {
                SecureField("re_…", text: $resendKey)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("From address") {
                TextField("you@yourdomain.com", text: $resendFrom)
                    .textFieldStyle(.roundedBorder)
            }
        } header: {
            ProviderDot(color: "#22C55E", name: "Resend")
        }

        Section {
            LabeledContent("Instance URL") {
                TextField("https://…", text: $n8nUrl)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("API key") {
                SecureField("", text: $n8nKey)
                    .textFieldStyle(.roundedBorder)
            }
            IntegrationFilterRow(
                label: "Workflows",
                items: n8nWorkflows,
                filter: $state.n8nWorkflowFilter,
                loading: loadingN8n,
                onLoad: loadN8nWorkflows
            )
        } header: {
            ProviderDot(color: "#F29B38", name: "n8n")
        }

        Section {
            LabeledContent("Token") {
                SecureField("", text: $vercelToken)
                    .textFieldStyle(.roundedBorder)
            }
            IntegrationFilterRow(
                label: "Projects",
                items: vercelProjects,
                filter: $state.vercelProjectFilter,
                loading: loadingVercel,
                onLoad: loadVercelProjects
            )
        } header: {
            ProviderDot(color: "#7C5CFF", name: "Vercel")
        }

        Section {
            LabeledContent("Personal Access Token") {
                SecureField("", text: $githubToken)
                    .textFieldStyle(.roundedBorder)
            }
        } header: {
            ProviderDot(color: "#F4505E", name: "GitHub")
        } footer: {
            SectionNote("Classic token with repo scope, or fine-grained with read access to Pull requests, Commit statuses and Actions.")
        }

        Section {
            LabeledContent("Secret key") {
                SecureField("sk_live_… or sk_test_…", text: $stripeKey)
                    .textFieldStyle(.roundedBorder)
            }
        } header: {
            ProviderDot(color: "#0570DE", name: "Stripe")
        }

        Section {
            LabeledContent("API key") {
                SecureField("cal_live_…", text: $calcomKey)
                    .textFieldStyle(.roundedBorder)
            }
        } header: {
            ProviderDot(color: "#C9956A", name: "Cal.com")
        }

        Section {
            LabeledContent("Integration token") {
                SecureField("secret_…", text: $notionKey)
                    .textFieldStyle(.roundedBorder)
            }
        } header: {
            ProviderDot(color: "#E8E8E8", name: "Notion")
        }

        Section {
            HStack {
                Spacer(minLength: 0)
                Button("Save integrations") { saveIntegrations() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Actions

    private func applyCustomModel(_ value: String) {
        let id = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !id.isEmpty { state.claudeModel = id }
    }

    private func toggleStartup(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else  { try SMAppService.mainApp.unregister() }
        } catch {
            statusMessage = "❌ Startup: \(error.localizedDescription)"
            launchAtStartup = !on
        }
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

    private func connectLocal(provider: ChatProvider) async {
        let rawURL = provider == .ollama ? ollamaURL : lmstudioURL
        let candidate = rawURL.isEmpty
            ? (provider == .ollama ? "http://127.0.0.1:11434" : "http://127.0.0.1:1234")
            : rawURL
        let normalised = LocalChat.normaliseURL(candidate)
        guard normalised.hasPrefix("http://") || normalised.hasPrefix("https://") else {
            statusMessage = "Only http:// and https:// URLs are supported."
            return
        }
        if provider == .ollama { connectingOllama = true } else { connectingLMStudio = true }
        statusMessage = ""
        let result = await LocalChat.fetchModelsResult(baseURL: normalised)
        if provider == .ollama { connectingOllama = false } else { connectingLMStudio = false }
        let name = provider == .ollama ? "Ollama" : "LM Studio"
        switch result {
        case .success(let models) where models.isEmpty:
            statusMessage = "No models yet — download one in \(name) first."
        case .success(let models):
            if provider == .ollama {
                state.ollamaServerURL = normalised
                ollamaURL = normalised
                state.fetchedProviderModels[.ollama] = nil
                state.providerModelFetchError[.ollama] = nil
            } else {
                state.lmstudioServerURL = normalised
                lmstudioURL = normalised
                state.fetchedProviderModels[.lmstudio] = nil
                state.providerModelFetchError[.lmstudio] = nil
            }
            statusMessage = "✓ Connected · \(models.count) model\(models.count == 1 ? "" : "s")"
        case .failure:
            statusMessage = "Couldn't reach \(name) at \(normalised). Is it running?"
        }
    }

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

    private func saveIntegrations() {
        saveKey("resend-api-key",  value: resendKey)
        saveKey("resend-from",     value: resendFrom)
        saveKey("n8n-url",         value: n8nUrl)
        saveKey("n8n-api-key",     value: n8nKey)
        saveKey("vercel-token",    value: vercelToken)

        // Detect GitHub token changes before writing
        let prevGithubToken = KeychainStore.shared.get("github-token")
        saveKey("github-token", value: githubToken)
        let nextGithubToken = KeychainStore.shared.get("github-token")
        if nextGithubToken != prevGithubToken {
            AppState.shared.githubPulse = nil
            AppState.shared.githubActivity = nil
            if nextGithubToken == nil { AppState.shared.githubStats = nil }
            if nextGithubToken != nil {
                GithubPoller.shared.triggerPulseNow()
                GithubPoller.shared.refreshActivityIfStale()
            }
        }

        saveKey("stripe-api-key",  value: stripeKey)
        saveKey("calcom-api-key",  value: calcomKey)
        saveKey("notion-api-key",  value: notionKey)
        statusMessage = "✓ Integration keys saved."
    }

    private func saveKey(_ key: String, value: String) {
        if value.isEmpty {
            KeychainStore.shared.remove(key)
        } else {
            KeychainStore.shared.set(key, value: value)
        }
    }

    // MARK: - Vercel project list

    private func loadVercelProjects() {
        guard let token = KeychainStore.shared.get("vercel-token") else {
            statusMessage = "❌ Save Vercel token first."
            return
        }
        loadingVercel = true
        guard let url = URL(string: "https://api.vercel.com/v9/projects?limit=100") else { return }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: req) { data, response, _ in
            let names: [String]
            if let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let projects = json["projects"] as? [[String: Any]] {
                names = projects.compactMap { $0["name"] as? String }.sorted()
            } else {
                names = []
            }
            DispatchQueue.main.async {
                self.vercelProjects = names
                self.loadingVercel = false
                if names.isEmpty { self.statusMessage = "❌ No Vercel projects found." }
            }
        }.resume()
    }

    // MARK: - n8n workflow list

    private func loadN8nWorkflows() {
        guard let apiKey  = KeychainStore.shared.get("n8n-api-key"),
              let rawBase = KeychainStore.shared.get("n8n-url") else {
            statusMessage = "❌ Save n8n URL and API key first."
            return
        }
        loadingN8n = true
        let base = rawBase.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let urls = ["\(base)/api/v1/workflows?limit=100", "\(base)/rest/workflows?limit=100"]
        fetchN8nWorkflows(urls: urls, apiKey: apiKey, idx: 0)
    }

    private func fetchN8nWorkflows(urls: [String], apiKey: String, idx: Int) {
        guard idx < urls.count, let url = URL(string: urls[idx]) else {
            DispatchQueue.main.async { self.loadingN8n = false; self.statusMessage = "❌ No n8n workflows found." }
            return
        }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue(apiKey, forHTTPHeaderField: "X-N8N-API-KEY")
        URLSession.shared.dataTask(with: req) { data, response, _ in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard let data, code == 200 else {
                self.fetchN8nWorkflows(urls: urls, apiKey: apiKey, idx: idx + 1)
                return
            }
            let items: [[String: Any]]
            if let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
               let arr = obj["data"] as? [[String: Any]] { items = arr }
            else if let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] { items = arr }
            else { items = [] }
            let names = items.compactMap { $0["name"] as? String }.sorted()
            DispatchQueue.main.async {
                self.n8nWorkflows = names
                self.loadingN8n = false
                if names.isEmpty { self.statusMessage = "❌ No n8n workflows found." }
            }
        }.resume()
    }

    @ViewBuilder
    private func pillRow(_ def: PillDefinition) -> some View {
        let isMain = def.id == state.mainPillId
        let isOn   = state.activeIntegrations.contains(def.id)
        let atMax  = state.activeIntegrations.count >= 4 && !isOn && !isMain
        let hint: String? = {
            if isMain { return nil }
            if def.comingSoon { return "Coming soon" }
            #if !APPSTORE
            if def.id == "agent_gemini"        && !HookServer.geminiHooksInstalled()  { return "Hooks not installed" }
            if def.id == "agent_antigravity"   && !HookServer.agyHooksInstalled()    { return "Hooks not installed" }
            if def.id == "agent_codex"         && !HookServer.codexHooksInstalled()  { return "Hooks not installed" }
            #endif
            if def.category == .ai {
                if let provider = ChatProvider(pillID: def.id), provider.isLocal {
                    let url = provider == .ollama ? state.ollamaServerURL : state.lmstudioServerURL
                    if url.isEmpty { return "Not connected" }
                } else {
                    let keyId = def.id == "ai_anthropic" ? "anthropic-api-key"
                               : def.id == "ai_google"    ? "google-api-key" : "openai-api-key"
                    if KeychainStore.shared.get(keyId) == nil { return "Key not configured" }
                }
            }
            return nil
        }()
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: def.color))
                .frame(width: 10, height: 10)
            Text(def.name)
                .font(.system(size: 12))
                .foregroundColor(atMax ? .secondary : .primary)
            Spacer()
            if isMain {
                Text("Main")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            } else {
                if let h = hint {
                    Text(h)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Toggle("", isOn: Binding(
                    get: { isOn },
                    set: { _ in state.toggleIntegration(def.id) }
                ))
                .labelsHidden()
                .disabled(atMax)
            }
        }
    }
}

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
