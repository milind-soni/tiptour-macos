//
//  ProviderSetupView.swift
//  TipTour
//
//  Settings content for local provider keys.
//

import SwiftUI

struct ProviderSetupView: View {
    @ObservedObject var companionManager: CompanionManager

    @State private var devGeminiKeyInput: String = ""
    @State private var devGeminiKeyStatus: String = ""
    @State private var devClaudeKeyInput: String = ""
    @State private var devClaudeKeyStatus: String = ""
    @State private var devOpenRouterKeyInput: String = ""
    @State private var devOpenRouterKeyStatus: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            providerHeader
            apiKeyRows
        }
        .onAppear {
            devGeminiKeyInput = KeychainStore.geminiAPIKey ?? ""
            devClaudeKeyInput = KeychainStore.claudeAPIKey ?? ""
            devOpenRouterKeyInput = KeychainStore.openRouterAPIKey ?? ""
        }
    }

    private var providerHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "waveform.badge.mic")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.Colors.textTertiary)

                Text("Provider keys")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(DS.Colors.textSecondary)
            }

            Text("Keys are stored in macOS Keychain and only used by your local build.")
                .font(.system(size: 11))
                .foregroundColor(DS.Colors.textTertiary)
        }
    }

    private var apiKeyRows: some View {
        VStack(spacing: 2) {
            byokKeyRow(
                title: "Gemini",
                placeholder: "AIzaSy...",
                input: $devGeminiKeyInput,
                save: {
                    KeychainStore.geminiAPIKey = devGeminiKeyInput
                },
                clear: {
                    devGeminiKeyInput = ""
                    KeychainStore.geminiAPIKey = nil
                },
                status: $devGeminiKeyStatus,
                hasSavedKey: hasSavedGeminiKey
            )

            byokKeyRow(
                title: "Claude",
                placeholder: "sk-ant-...",
                input: $devClaudeKeyInput,
                save: {
                    KeychainStore.claudeAPIKey = devClaudeKeyInput
                },
                clear: {
                    devClaudeKeyInput = ""
                    KeychainStore.claudeAPIKey = nil
                },
                status: $devClaudeKeyStatus,
                hasSavedKey: hasSavedClaudeKey
            )

            byokKeyRow(
                title: "OpenRouter",
                placeholder: "sk-or-v1-...",
                input: $devOpenRouterKeyInput,
                save: {
                    KeychainStore.openRouterAPIKey = devOpenRouterKeyInput
                },
                clear: {
                    devOpenRouterKeyInput = ""
                    KeychainStore.openRouterAPIKey = nil
                },
                status: $devOpenRouterKeyStatus,
                hasSavedKey: hasSavedOpenRouterKey
            )
        }
    }

    private var hasSavedGeminiKey: Bool {
        !(KeychainStore.geminiAPIKey ?? "").isEmpty
    }

    private var hasSavedClaudeKey: Bool {
        !(KeychainStore.claudeAPIKey ?? "").isEmpty
    }

    private var hasSavedOpenRouterKey: Bool {
        !(KeychainStore.openRouterAPIKey ?? "").isEmpty
    }

    private func byokKeyRow(
        title: String,
        placeholder: String,
        input: Binding<String>,
        save: @escaping () -> Void,
        clear: @escaping () -> Void,
        status: Binding<String>,
        hasSavedKey: Bool
    ) -> some View {
        let trimmedInput = input.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let saveDisabled = trimmedInput.isEmpty
        return HStack(spacing: 9) {
            Image(systemName: "key")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(hasSavedKey ? DS.Colors.success : DS.Colors.textTertiary)
                .frame(width: 18)

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DS.Colors.textSecondary)
                .frame(width: 82, alignment: .leading)

            SecureField(placeholder, text: input)
                .textFieldStyle(.plain)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(DS.Colors.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(DS.Colors.borderSubtle.opacity(0.7), lineWidth: 0.6)
                )
                .frame(minWidth: 220, maxWidth: 360)

            Button {
                save()
                status.wrappedValue = "Saved"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    if status.wrappedValue == "Saved" { status.wrappedValue = "" }
                }
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(saveDisabled ? DS.Colors.textTertiary : .white)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(saveDisabled ? Color.white.opacity(0.06) : DS.Colors.accent)
                    )
            }
            .buttonStyle(.plain)
            .disabled(saveDisabled)
            .pointerCursor()
            .help("Save")

            Button {
                clear()
                status.wrappedValue = "Cleared"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    if status.wrappedValue == "Cleared" { status.wrappedValue = "" }
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(DS.Colors.textTertiary)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
            .pointerCursor()
            .help("Clear")

            Text(status.wrappedValue)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(DS.Colors.textTertiary)
                .frame(width: 48, alignment: .leading)
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
