import SwiftUI

/// Lets the app read another Morgenlinie archive, e.g. a second person's own edition.
struct ArchiveSourceView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text = AppConfig.isUsingDefaultBaseURL ? "" : AppConfig.baseURL.absoluteString
    @State private var isChecking = false
    @State private var error: String?
    @State private var confirming: URL??

    private var entered: URL? { AppConfig.normalizedBaseURL(text) }

    var body: some View {
        Form {
            Section {
                TextField(AppConfig.defaultBaseURL.absoluteString, text: $text)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(check)
                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            } header: {
                Text("Archive address")
            } footer: {
                Text("The address that serves editions.json. Leave it empty for the default archive. Switching removes the editions on this device and downloads the new archive's.")
            }

            Section {
                Button {
                    check()
                } label: {
                    HStack {
                        Text("Use this archive")
                        Spacer()
                        if isChecking { ProgressView() }
                    }
                }
                .disabled(isChecking || (!text.isEmpty && entered == nil) || entered == current)

                if !AppConfig.isUsingDefaultBaseURL {
                    Button("Reset to default") { confirming = .some(nil) }
                        .disabled(isChecking)
                }
            }
        }
        .navigationTitle("Archive")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Switch archive?", isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
                            titleVisibility: .visible) {
            Button("Switch and replace editions", role: .destructive) {
                let target = confirming ?? nil
                confirming = nil
                Task {
                    await model.switchArchive(to: target)
                    dismiss()
                }
            }
        } message: {
            Text("The editions downloaded on this device are removed, then the app downloads them from \((confirming ?? nil)?.host() ?? "the default archive").")
        }
    }

    /// The address in use, or nil for the default.
    private var current: URL? { AppConfig.isUsingDefaultBaseURL ? nil : AppConfig.baseURL }

    private func check() {
        error = nil
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            if current != nil { confirming = .some(nil) }
            return
        }
        guard let url = entered else {
            error = "That doesn't look like a web address."
            return
        }
        isChecking = true
        Task {
            defer { isChecking = false }
            do {
                try await model.sync.probe(base: url)
                confirming = .some(url == AppConfig.defaultBaseURL ? nil : url)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
