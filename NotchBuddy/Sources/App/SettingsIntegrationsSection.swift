import SwiftUI
import ServiceManagement
import AppKit

// Integrations — one Section per service, and the Vercel and n8n lists the
// filter rows are built from.

extension SettingsView {

    // MARK: - Integrations section

    @ViewBuilder var integrationsSection: some View {
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
}
