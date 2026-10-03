import SwiftUI
import ServiceManagement
import AppKit

// Chat — the Anthropic key and model, the other cloud providers, and the two
// local model servers.

extension SettingsView {

    // MARK: - Chat section

    @ViewBuilder var chatSection: some View {
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

    private func applyCustomModel(_ value: String) {
        let id = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !id.isEmpty { state.claudeModel = id }
    }

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
}
