import SwiftUI
import ServiceManagement
import AppKit

struct SettingsView: View {
    @ObservedObject var state = AppState.shared
    @State var apiKey: String = KeychainStore.shared.get("anthropic-api-key") ?? ""

    // Claude model — dynamic list fetched from the API, static fallback if unavailable
    static let fallbackModels: [(id: String, label: String)] = [
        ("claude-sonnet-4-6",         "Claude Sonnet 4.6"),
        ("claude-sonnet-5-5",         "Claude Sonnet 5.5"),
        ("claude-opus-5-5",           "Claude Opus 5.5"),
        ("claude-haiku-4-5-20251001", "Claude Haiku 4.5"),
    ]
    static let customModelTag = "__custom__"
    @State var fetchedModels: [(id: String, label: String)] = []
    @State var modelChoice: String = {
        let m = AppState.shared.claudeModel
        return SettingsView.fallbackModels.contains { $0.id == m } ? m : SettingsView.customModelTag
    }()
    @State var customModel: String = {
        let m = AppState.shared.claudeModel
        return SettingsView.fallbackModels.contains { $0.id == m } ? "" : m
    }()
    var displayModels: [(id: String, label: String)] {
        fetchedModels.isEmpty ? Self.fallbackModels : fetchedModels
    }
    @State var launchAtStartup: Bool = (SMAppService.mainApp.status == .enabled)
    @State var statusMessage: String = ""
    @State var showDiff: Bool = false
    @State var pendingHookJSON: String = ""
    @State var hookNeedsUpdate: Bool = HookServer.hooksNeedUpdate()

    #if !APPSTORE
    @State var showStatusLineDiff: Bool = false
    @State var pendingStatusLineJSON: String = ""
    @State var statusLinePendingInstall: Bool = true
    @State var planTogglePending: Bool = false

    @State var geminiHooksInstalled: Bool = HookServer.geminiHooksInstalled()
    @State var showGeminiDiff: Bool = false
    @State var pendingGeminiJSON: String = ""
    @State var geminiPendingInstall: Bool = true

    @State var agyHooksInstalled: Bool = HookServer.agyHooksInstalled()
    @State var showAgyDiff: Bool = false
    @State var pendingAgyJSON: String = ""
    @State var agyPendingInstall: Bool = true

    @State var codexHooksInstalled: Bool = HookServer.codexHooksInstalled()
    @State var showCodexDiff: Bool = false
    @State var pendingCodexJSON: String = ""
    @State var codexPendingInstall: Bool = true
    #endif

    // Multi-provider chat keys
    @State var googleKey: String  = KeychainStore.shared.get("google-api-key") ?? ""
    @State var openAIKey: String  = KeychainStore.shared.get("openai-api-key") ?? ""
    @State var ollamaURL:    String = AppState.shared.ollamaServerURL
    @State var lmstudioURL:  String = AppState.shared.lmstudioServerURL
    @State var connectingOllama:    Bool = false
    @State var connectingLMStudio:  Bool = false

    // Integration keys
    @State var resendKey: String    = KeychainStore.shared.get("resend-api-key")  ?? ""
    @State var resendFrom: String   = KeychainStore.shared.get("resend-from")     ?? ""
    @State var n8nUrl: String       = KeychainStore.shared.get("n8n-url")         ?? ""
    @State var n8nKey: String       = KeychainStore.shared.get("n8n-api-key")     ?? ""
    @State var vercelToken: String  = KeychainStore.shared.get("vercel-token")    ?? ""
    @State var githubToken: String  = KeychainStore.shared.get("github-token")    ?? ""
    @State var stripeKey: String    = KeychainStore.shared.get("stripe-api-key")  ?? ""
    @State var calcomKey: String    = KeychainStore.shared.get("calcom-api-key")  ?? ""
    @State var notionKey: String    = KeychainStore.shared.get("notion-api-key")  ?? ""

    // Hotkey
    @State var hotkeyFlags: UInt    = AppState.shared.hotkeyFlags
    @State var hotkeyCode: UInt16   = AppState.shared.hotkeyCode

    // Vercel project filter
    @State var vercelProjects: [String] = []
    @State var loadingVercel: Bool = false

    // n8n workflow filter
    @State var n8nWorkflows: [String] = []
    @State var loadingN8n: Bool = false

    // Bindings in minutes for the absence field
    var absenceMinutes: Binding<Double> {
        Binding(
            get: { state.absenceInterval / 60 },
            set: { state.absenceInterval = max(1, $0) * 60 }
        )
    }

    // Sidebar selection persisted across sessions
    @AppStorage("settingsSection") var selectedSection: String = "general"

    var appVersion: String {
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
}
