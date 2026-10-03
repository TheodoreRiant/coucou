import SwiftUI
import ServiceManagement
import AppKit

// Active pills — one Section per PillCategory, plus the main-pill picker.

extension SettingsView {

    // MARK: - Active pills section

    @ViewBuilder var activePillsSection: some View {
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
