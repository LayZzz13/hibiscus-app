#if DEBUG && targetEnvironment(simulator)
import Combine
import Foundation
import UIKit

nonisolated struct SimulatorDemoPhoto: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let resourceURL: URL

    func loadImage() -> UIImage? {
        guard let data = try? Data(contentsOf: resourceURL, options: .mappedIfSafe) else { return nil }
        return UIImage(data: data)
    }

    func loadGradeImport() -> GradeImportItem? {
        guard let data = try? Data(contentsOf: resourceURL, options: .mappedIfSafe),
              let image = UIImage(data: data) else { return nil }
        let thumbnail = AccentAnalyzer.downsample(data, maxDimension: 384)
            ?? ImageRenderer.resizedImage(image, maxDimension: 384)
            ?? image
        return GradeImportItem(
            image: image,
            thumbnail: thumbnail,
            metadata: PhotoMetadataExtractor.metadata(from: data)
        )
    }
}

nonisolated struct SimulatorDemoGradeImportRequest: Identifiable, Sendable {
    let id = UUID()
    let photos: [SimulatorDemoPhoto]
}

@MainActor
final class SimulatorDemoMode: ObservableObject {
    static let maximumGradePhotos = 10

    @Published var isCameraEnabled: Bool {
        didSet { defaults.set(isCameraEnabled, forKey: Key.cameraEnabled) }
    }
    @Published var selectedPhotoID: String {
        didSet { defaults.set(selectedPhotoID, forKey: Key.selectedPhotoID) }
    }
    @Published private(set) var selectedGradePhotoIDs: Set<String> {
        didSet {
            defaults.set(Array(selectedGradePhotoIDs).sorted(), forKey: Key.selectedGradePhotoIDs)
        }
    }
    @Published private(set) var gradeImportRequest: SimulatorDemoGradeImportRequest?
    @Published private(set) var isPreparingGradeImport = false
    @Published var statusMessage: String?

    let photos: [SimulatorDemoPhoto]

    private let defaults: UserDefaults
    private var thumbnailCache: [String: UIImage] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        photos = Self.discoverPhotos()
        isCameraEnabled = defaults.bool(forKey: Key.cameraEnabled)

        let storedPhotoID = defaults.string(forKey: Key.selectedPhotoID)
        selectedPhotoID = photos.contains(where: { $0.id == storedPhotoID })
            ? storedPhotoID ?? ""
            : photos.first?.id ?? ""

        let storedSelection = Set(defaults.stringArray(forKey: Key.selectedGradePhotoIDs) ?? [])
        let availableIDs = Set(photos.map(\.id))
        selectedGradePhotoIDs = storedSelection.intersection(availableIDs)
    }

    var selectedPhoto: SimulatorDemoPhoto? {
        photos.first(where: { $0.id == selectedPhotoID }) ?? photos.first
    }

    var selectedCameraImage: UIImage? {
        selectedPhoto?.loadImage()
    }

    func thumbnail(for photo: SimulatorDemoPhoto) -> UIImage? {
        if let cached = thumbnailCache[photo.id] { return cached }
        guard let data = try? Data(contentsOf: photo.resourceURL, options: .mappedIfSafe),
              let thumbnail = AccentAnalyzer.downsample(data, maxDimension: 180)
                ?? UIImage(data: data) else { return nil }
        thumbnailCache[photo.id] = thumbnail
        return thumbnail
    }

    func toggleGradeSelection(_ photo: SimulatorDemoPhoto) {
        if selectedGradePhotoIDs.contains(photo.id) {
            selectedGradePhotoIDs.remove(photo.id)
            return
        }
        guard selectedGradePhotoIDs.count < Self.maximumGradePhotos else {
            statusMessage = "You can import up to \(Self.maximumGradePhotos) demo photos."
            return
        }
        selectedGradePhotoIDs.insert(photo.id)
    }

    func selectAllForGrade() {
        selectedGradePhotoIDs = Set(photos.prefix(Self.maximumGradePhotos).map(\.id))
    }

    func clearGradeSelection() {
        selectedGradePhotoIDs = []
    }

    func requestCurrentPhotoForGrade() {
        guard let selectedPhoto else { return }
        requestGradeImport(photos: [selectedPhoto])
    }

    func requestSelectedPhotosForGrade() {
        let selected = photos.filter { selectedGradePhotoIDs.contains($0.id) }
        requestGradeImport(photos: selected)
    }

    func beginPreparingGradeImport(_ requestID: UUID) {
        guard gradeImportRequest?.id == requestID else { return }
        isPreparingGradeImport = true
    }

    func finishGradeImport(_ requestID: UUID) {
        guard gradeImportRequest?.id == requestID else { return }
        gradeImportRequest = nil
        isPreparingGradeImport = false
    }

    private func requestGradeImport(photos: [SimulatorDemoPhoto]) {
        guard !photos.isEmpty, !isPreparingGradeImport else { return }
        gradeImportRequest = SimulatorDemoGradeImportRequest(
            photos: Array(photos.prefix(Self.maximumGradePhotos))
        )
    }

    private static func discoverPhotos() -> [SimulatorDemoPhoto] {
        guard let bundleURL = Bundle.main.url(
            forResource: "HibiscusDemoPhotos",
            withExtension: "bundle"
        ), let resourceBundle = Bundle(url: bundleURL),
        let resourceURL = resourceBundle.resourceURL,
        let contents = try? FileManager.default.contentsOfDirectory(
            at: resourceURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let supportedExtensions = Set(["heic", "heif", "jpg", "jpeg", "png", "tif", "tiff"])
        return contents
            .filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { url in
                let baseName = url.deletingPathExtension().lastPathComponent
                return SimulatorDemoPhoto(
                    id: url.lastPathComponent,
                    displayName: baseName.replacingOccurrences(of: "_", with: " "),
                    resourceURL: url
                )
            }
    }

    private enum Key {
        static let cameraEnabled = "debug.simulatorDemo.cameraEnabled"
        static let selectedPhotoID = "debug.simulatorDemo.selectedPhotoID"
        static let selectedGradePhotoIDs = "debug.simulatorDemo.selectedGradePhotoIDs"
    }
}
#endif
