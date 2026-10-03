import SwiftUI
import ServiceManagement
import AppKit

// General — sound, behaviour, hotkey and startup.
// Stored properties live on SettingsView itself; see SettingsView.swift.

extension SettingsView {

    // MARK: - General section

    @ViewBuilder var generalSection: some View {
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

    private func toggleStartup(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else  { try SMAppService.mainApp.unregister() }
        } catch {
            statusMessage = "❌ Startup: \(error.localizedDescription)"
            launchAtStartup = !on
        }
    }
}
