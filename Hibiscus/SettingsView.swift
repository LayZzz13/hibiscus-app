import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: AppPreferences

    var body: some View {
        NavigationStack {
            Form {
                Section("Camera") {
                    Toggle("Grid", isOn: $preferences.cameraGridEnabled)

                    Picker("Default Camera", selection: $preferences.defaultCamera) {
                        ForEach(DefaultCameraPreference.allCases) { option in
                            Text(option.rawValue).tag(option)
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

                    Link(destination: AppPreferences.repositoryURL) {
                        SettingsRow(
                            title: "Free & Open Source",
                            subtitle: "MPL-2.0 · View Source Code"
                        )
                    }

                    Link(destination: AppPreferences.openChromaIndexURL) {
                        SettingsRow(
                            title: "Open Chroma Index",
                            subtitle: "Support open digital color."
                        )
                    }

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
        }
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "Version \(version) (\(build))"
    }
}

private struct SettingsRow: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SettingsInformationView: View {
    let title: String
    let message: String

    var body: some View {
        List {
            Text(message)
                .foregroundStyle(.secondary)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
