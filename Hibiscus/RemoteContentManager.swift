import Combine
import Foundation

@MainActor
final class RemoteContentManager: ObservableObject {
    @Published private(set) var content: HibiscusRemoteContent?

    var enabledMoreApps: [RemoteMoreApp] {
        content?.moreApps.enabledAppsInDisplayOrder ?? []
    }

    var moreAppsTitle: String {
        guard content?.moreApps.enabled == true,
              let title = content?.moreApps.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return L10n.string("More from 1234567890.dev")
        }
        return title
    }

    var discordURL: URL? {
        guard let discord = content?.discord else { return HibiscusLinks.discord }
        return discord.enabled ? discord.inviteURL : nil
    }

    private let defaults: UserDefaults
    private let endpoint: URL
    private var refreshTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        endpoint: URL = HibiscusLinks.remoteContent
    ) {
        self.defaults = defaults
        self.endpoint = endpoint
        content = HibiscusRemoteContentCache.load(from: defaults)
    }

    func refreshInBackground() {
        guard refreshTask == nil else { return }
        let endpoint = endpoint
        refreshTask = Task(priority: .utility) { [weak self] in
            let refreshedContent = await Self.fetchContent(from: endpoint)
            guard let self else { return }
            if let refreshedContent {
                self.content = refreshedContent
                HibiscusRemoteContentCache.store(refreshedContent, in: self.defaults)
            }
            self.refreshTask = nil
        }
    }

    nonisolated private static func fetchContent(from endpoint: URL) async -> HibiscusRemoteContent? {
        var request = URLRequest(url: endpoint)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let response = response as? HTTPURLResponse,
                  (200...299).contains(response.statusCode) else { return nil }
            return HibiscusRemoteContent.validated(from: data)
        } catch {
            return nil
        }
    }
}
