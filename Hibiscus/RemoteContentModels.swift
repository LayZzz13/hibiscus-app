import Foundation

nonisolated struct HibiscusRemoteContent: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let lastUpdated: String?
    let moreApps: RemoteMoreAppsSection
    let discord: RemoteDiscordSection?

    var isValid: Bool { schemaVersion > 0 }

    static func validated(from data: Data) -> Self? {
        guard let content = try? JSONDecoder().decode(Self.self, from: data),
              content.isValid else { return nil }
        return content
    }
}

nonisolated struct RemoteDiscordSection: Codable, Equatable, Sendable {
    let enabled: Bool
    private let inviteURLString: String

    var inviteURL: URL? {
        guard let url = URL(string: inviteURLString),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host != nil else { return nil }
        return url
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case inviteURLString = "inviteUrl"
    }
}

nonisolated struct RemoteMoreAppsSection: Codable, Equatable, Sendable {
    let enabled: Bool
    let title: String?
    let apps: [RemoteMoreApp]
}

nonisolated struct RemoteMoreApp: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let subtitle: String?
    let platform: String?
    private let iconURLString: String?
    private let destinationURLString: String
    let enabled: Bool
    let rank: Int?

    var iconURL: URL? { Self.webURL(from: iconURLString) }
    var destinationURL: URL? { Self.webURL(from: destinationURLString) }
    var validRank: Int? { rank.flatMap { $0 > 0 ? $0 : nil } }

    var isDisplayable: Bool {
        enabled && !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && destinationURL != nil
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case subtitle
        case platform
        case iconURLString = "iconUrl"
        case destinationURLString = "destinationUrl"
        case enabled
        case rank
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        subtitle = try? container.decode(String.self, forKey: .subtitle)
        platform = try? container.decode(String.self, forKey: .platform)
        iconURLString = try? container.decode(String.self, forKey: .iconURLString)
        destinationURLString = try container.decode(String.self, forKey: .destinationURLString)
        enabled = try container.decode(Bool.self, forKey: .enabled)
        // Older caches may omit rank, and a malformed rank should behave like
        // an unranked entry instead of invalidating otherwise usable content.
        rank = try? container.decode(Int.self, forKey: .rank)
    }

    private static func webURL(from value: String?) -> URL? {
        guard let value,
              let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host != nil else { return nil }
        return url
    }
}

nonisolated extension RemoteMoreAppsSection {
    var enabledAppsInDisplayOrder: [RemoteMoreApp] {
        guard enabled else { return [] }
        return apps.enumerated()
            .filter { $0.element.isDisplayable }
            .sorted { lhs, rhs in
                switch (lhs.element.validRank, rhs.element.validRank) {
                case let (left?, right?):
                    return left == right ? lhs.offset < rhs.offset : left < right
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.offset < rhs.offset
                }
            }
            .map(\.element)
    }
}

nonisolated enum HibiscusRemoteContentCache {
    static let key = "remoteContent.hibiscus.lastValid.v1"

    static func load(from defaults: UserDefaults) -> HibiscusRemoteContent? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return HibiscusRemoteContent.validated(from: data)
    }

    static func store(_ content: HibiscusRemoteContent, in defaults: UserDefaults) {
        guard content.isValid,
              let data = try? JSONEncoder().encode(content) else { return }
        defaults.set(data, forKey: key)
    }
}
