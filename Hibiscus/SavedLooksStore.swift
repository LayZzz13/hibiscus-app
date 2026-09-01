import Combine
import CoreGraphics
import Foundation

nonisolated enum SavedLookAccentMode: String, Codable, Sendable {
    case automatic
    case manual
}

nonisolated struct SavedLookAccent: Codable, Equatable, Sendable {
    var mode: SavedLookAccentMode
    var pointX: Double
    var pointY: Double
    var strength: Double
    var manualRed: Double?
    var manualGreen: Double?
    var manualBlue: Double?

    var point: CGPoint {
        CGPoint(x: pointX.clampedToUnit, y: pointY.clampedToUnit)
    }

    var manualColor: AccentColor? {
        guard mode == .manual,
              let manualRed, let manualGreen, let manualBlue else { return nil }
        return AccentColor(
            red: manualRed.clampedToUnit,
            green: manualGreen.clampedToUnit,
            blue: manualBlue.clampedToUnit
        )
    }
}

nonisolated struct SavedLook: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var style: GradeStyle
    var stylePointX: Double
    var stylePointY: Double
    var styleStrength: Double
    var accent: SavedLookAccent?

    var stylePoint: CGPoint {
        CGPoint(x: stylePointX.clampedToUnit, y: stylePointY.clampedToUnit)
    }
}

private nonisolated struct SavedLooksArchive: Codable, Sendable {
    var schemaVersion: Int
    var looks: [SavedLook]
}

@MainActor
final class SavedLooksStore: ObservableObject {
    @Published private(set) var looks: [SavedLook]

    private static let archiveKey = "grade.savedLooks.archive"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.archiveKey),
           let archive = try? JSONDecoder().decode(SavedLooksArchive.self, from: data),
           archive.schemaVersion > 0 {
            looks = archive.looks.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        } else {
            looks = []
        }
    }

    @discardableResult
    func saveCurrent(
        name: String,
        settings: GradeSettings,
        isAccentCustomized: Bool,
        includeAccent: Bool
    ) -> SavedLook? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }

        let accent: SavedLookAccent?
        if includeAccent {
            accent = SavedLookAccent(
                mode: isAccentCustomized ? .manual : .automatic,
                pointX: settings.accentPoint.x,
                pointY: settings.accentPoint.y,
                strength: settings.accentStrength,
                manualRed: isAccentCustomized ? settings.accent.red : nil,
                manualGreen: isAccentCustomized ? settings.accent.green : nil,
                manualBlue: isAccentCustomized ? settings.accent.blue : nil
            )
        } else {
            accent = nil
        }

        let look = SavedLook(
            id: UUID(),
            name: trimmedName,
            style: settings.style,
            stylePointX: settings.stylePoint.x,
            stylePointY: settings.stylePoint.y,
            styleStrength: settings.styleStrength,
            accent: accent
        )
        looks.append(look)
        persist()
        return look
    }

    func rename(_ look: SavedLook, to name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              let index = looks.firstIndex(where: { $0.id == look.id }) else { return }
        looks[index].name = trimmedName
        persist()
    }

    func delete(_ look: SavedLook) {
        looks.removeAll { $0.id == look.id }
        persist()
    }

    private func persist() {
        let archive = SavedLooksArchive(schemaVersion: 1, looks: looks)
        guard let data = try? JSONEncoder().encode(archive) else { return }
        defaults.set(data, forKey: Self.archiveKey)
    }
}

private nonisolated extension Double {
    var clampedToUnit: Double { min(1, max(0, self)) }
}
