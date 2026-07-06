import SwiftUI

struct AISettingsView: View {
    @Environment(AppState.self) private var appState

    // Track which providers have stored keys
    @State private var keyStatus: [LLMService.Provider: Bool] = [:]

    // Editing state — only one provider editable at a time
    @State private var editingProvider: LLMService.Provider?
    @State private var keyInput: String = ""
    @State private var isKeyVisible: Bool = false

    var body: some View {
        Form {
            featureSummarySection
            providerSection
            apiKeysSection
        }
        .formStyle(.grouped)
        .onAppear {
            loadKeyStatus()
        }
    }

    // MARK: - Feature Summary Section

    private var featureSummarySection: some View {
        Section {
            Label {
                Text("Select text and record a voice command to transform it")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "sparkles")
                    .foregroundStyle(.purple)
            }

            Label {
                Text("Say \"Hey Yapper\" followed by a question for instant answers")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "waveform")
                    .foregroundStyle(.purple)
            }
        }
    }

    // MARK: - Provider Selection Section

    private var providerSection: some View {
        Section {
            @Bindable var state = appState

            Picker("Provider", selection: $state.selectedLLMProvider) {
                ForEach(LLMService.Provider.allCases, id: \.self) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .onChange(of: appState.selectedLLMProvider) { _, newValue in
                appState.setSelectedLLMProvider(newValue)
            }

            Picker("Model", selection: $state.selectedLLMModel) {
                ForEach(LLMModel.models(for: appState.selectedLLMProvider), id: \.self) { model in
                    Text(model.displayName).tag(model)
                }
            }
            .onChange(of: appState.selectedLLMModel) { _, newValue in
                appState.setSelectedLLMModel(newValue)
            }
        } header: {
            Text("Provider")
        }
    }

    // MARK: - API Keys Section

    private var apiKeysSection: some View {
        Section {
            ForEach(LLMService.Provider.allCases, id: \.self) { provider in
                apiKeyRow(for: provider)
            }
        } header: {
            Text("API Keys")
        } footer: {
            Text("Keys are stored locally on this device.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func apiKeyRow(for provider: LLMService.Provider) -> some View {
        let hasKey = keyStatus[provider] ?? false
        let isEditing = editingProvider == provider
        let isSelected = provider == appState.selectedLLMProvider

        VStack(alignment: .leading, spacing: 8) {
            // Provider header row
            HStack {
                Text(provider.displayName)
                    .fontWeight(isSelected ? .semibold : .regular)

                if isSelected {
                    Text("Active")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.purple.opacity(0.15))
                        .foregroundStyle(.purple)
                        .clipShape(Capsule())
                }

                Spacer()

                if hasKey && !isEditing {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.body)
                }
            }

            if isEditing {
                // Inline key editor
                keyEditor(for: provider, hasExistingKey: hasKey)
            } else if !hasKey {
                // No key — show prompt to add
                Button {
                    startEditing(provider)
                } label: {
                    Label("Add API key", systemImage: "plus.circle")
                        .font(.callout)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.blue)
            } else {
                // Has key — show actions
                HStack(spacing: 12) {
                    Button("Replace key") {
                        startEditing(provider)
                    }
                    .buttonStyle(.borderless)
                    .font(.callout)

                    Button("Remove", role: .destructive) {
                        deleteAPIKey(for: provider)
                    }
                    .buttonStyle(.borderless)
                    .font(.callout)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func keyEditor(for provider: LLMService.Provider, hasExistingKey: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Input field with visibility toggle
            HStack(spacing: 6) {
                Group {
                    if isKeyVisible {
                        TextField("Paste API key", text: $keyInput)
                    } else {
                        SecureField("Paste API key", text: $keyInput)
                    }
                }
                .textFieldStyle(.plain)

                Button {
                    isKeyVisible.toggle()
                } label: {
                    Image(systemName: isKeyVisible ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderless)
                .help(isKeyVisible ? "Hide key" : "Show key")
            }
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )

            // Action row
            HStack {
                Link("Get API key", destination: provider.apiKeyURL)
                    .font(.callout)

                Spacer()

                Button("Cancel") {
                    cancelEditing()
                }
                .buttonStyle(.borderless)
                .font(.callout)

                Button("Save") {
                    saveAPIKey(keyInput, for: provider)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    // MARK: - Actions

    private func startEditing(_ provider: LLMService.Provider) {
        editingProvider = provider
        keyInput = ""
        isKeyVisible = false
    }

    private func cancelEditing() {
        editingProvider = nil
        keyInput = ""
        isKeyVisible = false
    }

    private func loadKeyStatus() {
        for provider in LLMService.Provider.allCases {
            keyStatus[provider] = APIKeyStorage.shared.exists(forAccount: provider.storageAccount)
        }
    }

    private func saveAPIKey(_ apiKey: String, for provider: LLMService.Provider) {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        APIKeyStorage.shared.save(key: trimmed, forAccount: provider.storageAccount)
        keyStatus[provider] = true
        cancelEditing()
        NotificationCenter.default.post(name: .apiKeyChanged, object: nil)
    }

    private func deleteAPIKey(for provider: LLMService.Provider) {
        APIKeyStorage.shared.delete(forAccount: provider.storageAccount)
        keyStatus[provider] = false
        NotificationCenter.default.post(name: .apiKeyChanged, object: nil)
    }
}

// MARK: - Preview

#Preview {
    AISettingsView()
        .environment(AppState())
        .frame(width: 500, height: 520)
}
