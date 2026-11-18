import SwiftData
import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Query private var editions: [Edition]
    @AppStorage(ReaderTheme.storageKey) private var theme: ReaderTheme = .system
    @AppStorage(Notifier.enabledKey) private var notificationsEnabled = true
    @AppStorage(SafariView.readerKey) private var openLinksInReader = true
    @State private var notificationsDenied = false
    @State private var bytesUsed: Int64 = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Theme", selection: $theme) {
                        ForEach(ReaderTheme.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle("Open articles in Reader", isOn: $openLinksInReader)
                } header: {
                    Text("Reading")
                } footer: {
                    Text("Shows linked articles as plain text and pictures, without ads, when the site supports it. Tap \u{201C}aA\u{201D} in the address bar to switch back to the full page.")
                }

                Section("App icon") {
                    AppIconPicker()
                }

                Section {
                    Toggle("New edition notifications", isOn: $notificationsEnabled)
                    if notificationsEnabled && notificationsDenied {
                        Button("Notifications are off in iOS Settings") {
                            openURL(URL(string: UIApplication.openNotificationSettingsURLString)!)
                        }
                        .font(.footnote)
                    }
                } header: {
                    Text("Updates")
                } footer: {
                    Text("The app checks for a new edition shortly after 06:50 Berlin time. iOS decides exactly when, so it can be later.")
                }

                Section {
                    Button {
                        Task { await model.refresh(); bytesUsed = EditionStore.bytesUsed() }
                    } label: {
                        HStack {
                            Text("Refresh now")
                            Spacer()
                            if model.sync.isSyncing { ProgressView() }
                        }
                    }
                    .disabled(model.sync.isSyncing)
                    if let error = model.sync.lastError {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    } else if let last = model.sync.lastSuccess {
                        LabeledContent("Last checked", value: last.formatted(.relative(presentation: .named)))
                    }
                    if model.sync.needsAppUpdate { UpdateHint() }
                }

                Section("Storage") {
                    LabeledContent("Editions", value: editions.count.formatted())
                    LabeledContent("Storage used", value: bytesUsed.formatted(.byteCount(style: .file)))
                }

                Section {
                    NavigationLink {
                        ArchiveSourceView()
                    } label: {
                        LabeledContent("Archive", value: AppConfig.isUsingDefaultBaseURL ? "Default" : AppConfig.baseURL.host() ?? "Custom")
                    }
                    Link("Web archive", destination: AppConfig.baseURL)
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                }
            }
            .navigationTitle("Settings")
            .task {
                bytesUsed = EditionStore.bytesUsed()
                await checkAuthorization()
            }
            .onChange(of: notificationsEnabled) { _, enabled in
                guard enabled else { return }
                Task {
                    await Notifier.requestAuthorization()
                    await checkAuthorization()
                }
            }
        }
    }

    private func checkAuthorization() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        notificationsDenied = status == .denied
    }
}
