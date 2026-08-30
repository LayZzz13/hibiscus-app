import SwiftUI

struct MoreAppsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var remoteContent: RemoteContentManager
    let showsDismissButton: Bool
    let onOpenEcosystemLink: () -> Void

    init(
        showsDismissButton: Bool = false,
        onOpenEcosystemLink: @escaping () -> Void = { }
    ) {
        self.showsDismissButton = showsDismissButton
        self.onOpenEcosystemLink = onOpenEcosystemLink
    }

    var body: some View {
        List {
            if remoteContent.enabledMoreApps.isEmpty {
                Section {
                    Button {
                        onOpenEcosystemLink()
                        openURL(HibiscusLinks.developerWebsite)
                    } label: {
                        DiscoveryRow(
                            title: "1234567890.dev",
                            subtitle: "Visit 1234567890.dev",
                            systemImage: "safari"
                        )
                    }
                }
            } else {
                Section {
                    ForEach(remoteContent.enabledMoreApps) { app in
                        if let destination = app.destinationURL {
                            Button {
                                onOpenEcosystemLink()
                                openURL(destination)
                            } label: {
                                MoreAppRow(app: app)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .navigationTitle(remoteContent.moreAppsTitle)
        .navigationBarTitleDisplayMode(.inline)
        .tint(.primary)
        .toolbar {
            if showsDismissButton {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { remoteContent.refreshInBackground() }
    }
}

struct PostExportDiscoveryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var remoteContent: RemoteContentManager
    @State private var showsMoreApps = false
    let onOpenEcosystemLink: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear

                VStack(spacing: 20) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Explore More")
                                .font(.title2.weight(.semibold))
                            Text(verbatim: "1234567890.dev")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.footnote.weight(.bold))
                                .frame(width: 34, height: 34)
                        }
                        .foregroundStyle(.secondary)
                        .hibiscusGlassButtonStyle(.clear)
                        .accessibilityLabel("Done")
                    }

                    VStack(spacing: 10) {
                        Button {
                            onOpenEcosystemLink()
                            openURL(HibiscusLinks.repository)
                        } label: {
                            discoveryAction(
                                title: "Free & Open Source",
                                subtitle: "View Hibiscus on GitHub",
                                systemImage: "chevron.left.forwardslash.chevron.right",
                                color: .primary,
                                opensExternally: true
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            onOpenEcosystemLink()
                            showsMoreApps = true
                        } label: {
                            discoveryAction(
                                title: "More Apps",
                                subtitle: "Explore more apps",
                                systemImage: "square.grid.2x2",
                                color: .hibiscusAccent,
                                opensExternally: false
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            onOpenEcosystemLink()
                            openURL(remoteContent.discordURL ?? HibiscusLinks.discord)
                        } label: {
                            discoveryAction(
                                title: "Discord",
                                subtitle: "Join the community",
                                systemImage: "person.2.fill",
                                color: Color(red: 0.35, green: 0.40, blue: 0.95),
                                opensExternally: true
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(22)
                .frame(maxWidth: 342)
                .hibiscusGlass(
                    tint: Color(uiColor: .systemBackground).opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 28, style: .continuous)
                )
                .padding(.horizontal, 24)
                .padding(.vertical, 22)
            }
            .tint(.hibiscusAccent)
        }
        .presentationDetents([.height(430)])
        .presentationDragIndicator(.hidden)
        .presentationBackground(.clear)
        .fullScreenCover(isPresented: $showsMoreApps) {
            NavigationStack {
                MoreAppsView(
                    showsDismissButton: true,
                    onOpenEcosystemLink: onOpenEcosystemLink
                )
            }
        }
        .task { remoteContent.refreshInBackground() }
    }

    private func discoveryAction(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        systemImage: String,
        color: Color,
        opensExternally: Bool
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 38, height: 38)
                .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Image(systemName: opensExternally ? "arrow.up.right" : "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.primary.opacity(0.76))
        }
        .padding(.horizontal, 14)
        .frame(height: 68)
        .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .hibiscusGlass(
            interactive: true,
            in: RoundedRectangle(cornerRadius: 17, style: .continuous)
        )
    }
}

struct DiscoveryRow: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let systemImage: String
    let showsExternalArrow: Bool

    init(
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        systemImage: String,
        showsExternalArrow: Bool = true
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.showsExternalArrow = showsExternalArrow
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.hibiscusAccent)
                .frame(width: 34, height: 34)
                .background(Color.hibiscusAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if showsExternalArrow {
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.primary.opacity(0.76))
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

private struct MoreAppRow: View {
    let app: RemoteMoreApp

    var body: some View {
        HStack(spacing: 13) {
            RemoteAppIcon(url: app.iconURL)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(app.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let platform = app.platform, !platform.isEmpty {
                        Text(platform)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                if let subtitle = app.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "arrow.up.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.primary.opacity(0.76))
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}

private struct RemoteAppIcon: View {
    let url: URL?

    @ViewBuilder
    var body: some View {
        if let url {
            AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.18))) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(width: 50, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(.white.opacity(0.10), lineWidth: 0.5)
                        }
                case .empty, .failure:
                    loadingIndicator
                @unknown default:
                    loadingIndicator
                }
            }
        } else {
            loadingIndicator
        }
    }

    private var loadingIndicator: some View {
        ProgressView()
            .controlSize(.small)
            .tint(.secondary)
            .frame(width: 50, height: 50)
    }
}
