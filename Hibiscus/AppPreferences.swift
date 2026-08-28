import Combine
import Foundation

nonisolated enum DefaultCameraPreference: String, CaseIterable, Identifiable, Sendable {
    case lastUsed = "Last Used"
    case alpha = "Alpha"

    var id: Self { self }
}

@MainActor
final class AppPreferences: ObservableObject {
    static let repositoryURL = URL(string: "https://github.com/T-1234567890/hibiscus-app")!
    static let openChromaIndexURL = URL(string: "https://github.com/T-1234567890/open-chroma-index")!

    @Published var cameraGridEnabled: Bool { didSet { save(cameraGridEnabled, for: .cameraGridEnabled) } }
    @Published var defaultCamera: DefaultCameraPreference { didSet { save(defaultCamera.rawValue, for: .defaultCamera) } }
    @Published var defaultAspectRatio: CameraAspectRatio { didSet { save(defaultAspectRatio.rawValue, for: .defaultAspectRatio) } }
    @Published var rememberExposure: Bool {
        didSet {
            save(rememberExposure, for: .rememberExposure)
            if !rememberExposure { lastExposure = 0 }
        }
    }
    @Published var rememberLastStyle: Bool { didSet { save(rememberLastStyle, for: .rememberLastStyle) } }
    @Published var autoAccent: Bool { didSet { save(autoAccent, for: .autoAccent) } }
    @Published var resetEditsForNewPhoto: Bool { didSet { save(resetEditsForNewPhoto, for: .resetEditsForNewPhoto) } }
    @Published var preserveMetadata: Bool { didSet { save(preserveMetadata, for: .preserveMetadata) } }
    @Published var includeLocation: Bool { didSet { save(includeLocation, for: .includeLocation) } }
    @Published var polaroidMetadata: Bool { didSet { save(polaroidMetadata, for: .polaroidMetadata) } }
    @Published var hibiscusMark: Bool { didSet { save(hibiscusMark, for: .hibiscusMark) } }

    var lastCameraCharacter: CameraCharacter {
        didSet { save(lastCameraCharacter.rawValue, for: .lastCameraCharacter) }
    }
    var lastExposure: Double {
        didSet { save(lastExposure, for: .lastExposure) }
    }
    var lastGradeStyle: GradeStyle {
        didSet { save(lastGradeStyle.rawValue, for: .lastGradeStyle) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        cameraGridEnabled = defaults.object(forKey: Key.cameraGridEnabled.rawValue) as? Bool ?? true
        defaultCamera = DefaultCameraPreference(
            rawValue: defaults.string(forKey: Key.defaultCamera.rawValue) ?? ""
        ) ?? .lastUsed
        defaultAspectRatio = CameraAspectRatio(
            rawValue: defaults.string(forKey: Key.defaultAspectRatio.rawValue) ?? ""
        ) ?? .standard
        rememberExposure = defaults.object(forKey: Key.rememberExposure.rawValue) as? Bool ?? false
        rememberLastStyle = defaults.object(forKey: Key.rememberLastStyle.rawValue) as? Bool ?? true
        autoAccent = defaults.object(forKey: Key.autoAccent.rawValue) as? Bool ?? true
        resetEditsForNewPhoto = defaults.object(forKey: Key.resetEditsForNewPhoto.rawValue) as? Bool ?? true
        preserveMetadata = defaults.object(forKey: Key.preserveMetadata.rawValue) as? Bool ?? true
        includeLocation = defaults.object(forKey: Key.includeLocation.rawValue) as? Bool ?? true
        polaroidMetadata = defaults.object(forKey: Key.polaroidMetadata.rawValue) as? Bool ?? false
        hibiscusMark = defaults.object(forKey: Key.hibiscusMark.rawValue) as? Bool ?? true
        lastCameraCharacter = CameraCharacter(
            rawValue: defaults.string(forKey: Key.lastCameraCharacter.rawValue) ?? ""
        ) ?? .alpha
        lastExposure = defaults.object(forKey: Key.lastExposure.rawValue) as? Double ?? 0
        lastGradeStyle = GradeStyle(
            rawValue: defaults.string(forKey: Key.lastGradeStyle.rawValue) ?? ""
        ) ?? .pure
    }

    private func save(_ value: Any, for key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }

    private enum Key: String {
        case cameraGridEnabled = "settings.camera.grid"
        case defaultCamera = "settings.camera.defaultCharacter"
        case defaultAspectRatio = "settings.camera.defaultAspectRatio"
        case rememberExposure = "settings.camera.rememberExposure"
        case rememberLastStyle = "settings.grade.rememberLastStyle"
        case autoAccent = "settings.grade.autoAccent"
        case resetEditsForNewPhoto = "settings.grade.resetEditsForNewPhoto"
        case preserveMetadata = "settings.export.preserveMetadata"
        case includeLocation = "settings.export.includeLocation"
        case polaroidMetadata = "settings.export.polaroidMetadata"
        case hibiscusMark = "settings.export.hibiscusMark"
        case lastCameraCharacter = "state.camera.lastCharacter"
        case lastExposure = "state.camera.lastExposure"
        case lastGradeStyle = "state.grade.lastStyle"
    }
}
