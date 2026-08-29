import SwiftUI

struct SettingsView: View {
    @Environment(\.openURL) private var openURL
    @ObservedObject var preferences: AppPreferences
    @EnvironmentObject private var languageManager: LanguageManager
    @EnvironmentObject private var remoteContent: RemoteContentManager

    var body: some View {
        NavigationStack {
            Form {
                Section("General") {
                    NavigationLink {
                        LanguageSelectionView()
                    } label: {
                        HStack {
                            Text("Language")
                            Spacer()
                            Text(languageManager.mode.titleKey)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Camera") {
                    Toggle("Grid", isOn: $preferences.cameraGridEnabled)

                    Picker("Default Camera", selection: $preferences.defaultCamera) {
                        ForEach(DefaultCameraPreference.allCases) { option in
                            Text(LocalizedStringKey(option.displayName)).tag(option)
                        }
                    }

                    Picker("Default Aspect Ratio", selection: $preferences.defaultAspectRatio) {
                        ForEach(CameraAspectRatio.allCases) { ratio in
                            Text(ratio.rawValue).tag(ratio)
                        }
                    }

                    Toggle("Remember Exposure", isOn: $preferences.rememberExposure)
                }

                Section("Grade") {
                    Toggle("Remember Last Style", isOn: $preferences.rememberLastStyle)
                    Toggle("Auto Accent", isOn: $preferences.autoAccent)
                    Toggle("Reset Edits for New Photo", isOn: $preferences.resetEditsForNewPhoto)
                }

                Section("Export") {
                    Toggle("Preserve Metadata", isOn: $preferences.preserveMetadata)
                    Toggle("Include Location", isOn: $preferences.includeLocation)
                    Toggle("Polaroid Metadata", isOn: $preferences.polaroidMetadata)
                    Toggle("Hibiscus Mark", isOn: $preferences.hibiscusMark)
                }

                Section("More Apps") {
                    Toggle(isOn: $preferences.exploreMoreAfterExport) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show Discovery Pop-up")
                            Text("Occasionally show more projects after exporting.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    NavigationLink {
                        MoreAppsView {
                            preferences.recordExploreMoreEcosystemOpen()
                        }
                        .onAppear {
                            preferences.recordExploreMoreEcosystemOpen()
                        }
                    } label: {
                        SettingsRow(
                            title: "More Apps",
                            subtitle: "Explore more from 1234567890.dev"
                        )
                    }

                    if let discordURL = remoteContent.discordURL {
                        Button {
                            preferences.recordExploreMoreEcosystemOpen()
                            openURL(discordURL)
                        } label: {
                            SettingsRow(
                                title: "Discord",
                                subtitle: "Join the community",
                                showsExternalLinkIndicator: true
                            )
                        }
                        .buttonStyle(.plain)
                        .tint(.primary)
                    }
                }

                Section("About") {
                    HStack(spacing: 14) {
                        if let icon = HibiscusBrand.appIcon() {
                            Image(uiImage: icon)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 58, height: 58)
                                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Hibiscus")
                                .font(.headline)
                            Text("Color by feel.")
                                .foregroundStyle(.secondary)
                            Text(versionText)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 3)

                    Button {
                        preferences.recordExploreMoreEcosystemOpen()
                        openURL(HibiscusLinks.repository)
                    } label: {
                        SettingsRow(
                            title: "Free & Open Source",
                            subtitle: "MPL-2.0 · View Source Code",
                            showsExternalLinkIndicator: true
                        )
                    }
                    .buttonStyle(.plain)
                    .tint(.primary)

                    Button {
                        preferences.recordExploreMoreEcosystemOpen()
                        openURL(HibiscusLinks.openChromaIndex)
                    } label: {
                        SettingsRow(
                            title: "Open Chroma Index",
                            subtitle: "Support open digital color.",
                            showsExternalLinkIndicator: true
                        )
                    }
                    .buttonStyle(.plain)
                    .tint(.primary)

                    NavigationLink {
                        SettingsInformationView(
                            title: "Privacy",
                            message: "Hibiscus processes camera and grading data locally. Photo access is used only when you choose to import or save an image."
                        )
                    } label: {
                        Text("Privacy")
                    }

                    NavigationLink {
                        SettingsInformationView(
                            title: "Terms of Service",
                            message: "Hibiscus is provided subject to the terms that accompany its distribution. The full Terms of Service will appear here when published."
                        )
                    } label: {
                        Text("Terms of Service")
                    }

                    NavigationLink {
                        SettingsInformationView(
                            title: "Licenses",
                            message: "Hibiscus uses Apple system frameworks. Additional open-source acknowledgements will appear here when applicable."
                        )
                    } label: {
                        Text("Licenses")
                    }
                }
            }
            .navigationTitle("Settings")
            .tint(.hibiscusAccent)
            .task { remoteContent.refreshInBackground() }
        }
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return L10n.format("Version %@ (%@)", version, build)
    }
}

private struct LanguageSelectionView: View {
    @EnvironmentObject private var languageManager: LanguageManager

    var body: some View {
        List {
            ForEach(AppLanguageMode.allCases) { mode in
                Button {
                    languageManager.mode = mode
                } label: {
                    HStack {
                        Text(mode.titleKey)
                            .foregroundStyle(.primary)
                        Spacer()
                        if languageManager.mode == mode {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.hibiscusAccent)
                        }
                    }
                    .contentShape(Rectangle())
                }
            }
        }
        .navigationTitle("Language")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SettingsRow: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    var showsExternalLinkIndicator = false

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if showsExternalLinkIndicator {
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.primary.opacity(0.76))
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct SettingsInformationView: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        List {
            Text(message)
                .foregroundStyle(.secondary)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
