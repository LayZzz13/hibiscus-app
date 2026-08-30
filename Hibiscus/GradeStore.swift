import Combine
import Photos
import SwiftUI
import UIKit

nonisolated struct PhotoMetadata: Equatable, Sendable {
    var date: Date?
    var location: String?
    var cameraCharacter: CameraCharacter?
    var latitude: Double?
    var longitude: Double?
    var cameraMake: String?
    var cameraModel: String?
    var lensModel: String?

    init(
        date: Date? = nil,
        location: String? = nil,
        cameraCharacter: CameraCharacter? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        cameraMake: String? = nil,
        cameraModel: String? = nil,
        lensModel: String? = nil
    ) {
        self.date = date
        self.location = location
        self.cameraCharacter = cameraCharacter
        self.latitude = latitude
        self.longitude = longitude
        self.cameraMake = cameraMake
        self.cameraModel = cameraModel
        self.lensModel = lensModel
    }
}

struct GradeImportItem: @unchecked Sendable {
    let image: UIImage
    let thumbnail: UIImage
    let metadata: PhotoMetadata
}

nonisolated struct GradeStyleSession: Equatable, Sendable {
    var settings: GradeSettings
    var isAccentCustomized: Bool
}

struct GradeSessionPhoto: Identifiable {
    let id: UUID
    let image: UIImage
    let thumbnail: UIImage
    var settings: GradeSettings
    var automaticAccent: AccentColor
    var isAccentCustomized: Bool
    var styleSessions: [GradeStyle: GradeStyleSession]
    let metadata: PhotoMetadata
}

private struct GradeEditState: Equatable {
    var settings: GradeSettings
    var isAccentCustomized: Bool
    var activeSurface: ActiveGradeSurface
}

@MainActor
final class GradeStore: ObservableObject {
    @Published private(set) var photos: [GradeSessionPhoto] = []
    @Published private(set) var currentIndex = 0
    @Published private(set) var thumbnails: [GradeStyle: UIImage] = [:]
    @Published var settings = GradeSettings()
    @Published var activeSurface: ActiveGradeSurface = .style
    @Published var isStyleRailExpanded = true
    @Published private(set) var automaticAccent = AccentColor.warmGray
    @Published private(set) var isAccentCustomized = false
    @Published var isShowingOriginal = false
    @Published var statusMessage: String?
    @Published private(set) var isExporting = false
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    nonisolated let previewRenderer = GradePreviewRenderer()
    private let thumbnailQueue = DispatchQueue(label: "dev.hibiscus.grade-thumbnails", qos: .utility)
    private let analysisQueue = DispatchQueue(label: "dev.hibiscus.grade-analysis", qos: .userInitiated)
    private var thumbnailGeneration = 0
    private var analysisGeneration = 0
    private var thumbnailToken: RenderToken?
    private let preferences: AppPreferences
    private var undoStacks: [UUID: [GradeEditState]] = [:]
    private var redoStacks: [UUID: [GradeEditState]] = [:]
    private var lastCoalescingKey: String?
    private var lastCoalescingPhotoID: UUID?
    private var lastCoalescingTime = Date.distantPast

    init(preferences: AppPreferences) {
        self.preferences = preferences
        settings = Self.defaultSettings(preferredStyle: nil, preferences: preferences)
    }

    var sourceImage: UIImage? {
        guard photos.indices.contains(currentIndex) else { return nil }
        return photos[currentIndex].image
    }

    var currentPhoto: GradeSessionPhoto? {
        guard photos.indices.contains(currentIndex) else { return nil }
        return photos[currentIndex]
    }

    var batchCount: Int { photos.count }

    func load(
        _ image: UIImage,
        preferredStyle: GradeStyle? = nil,
        thumbnailSource: UIImage? = nil,
        metadata: PhotoMetadata = PhotoMetadata()
    ) {
        let thumbnail = thumbnailSource ?? ImageRenderer.resizedImage(image, maxDimension: 320) ?? image
        loadBatch(
            [GradeImportItem(image: image, thumbnail: thumbnail, metadata: metadata)],
            preferredStyle: preferredStyle,
            replacing: true
        )
    }

    func loadBatch(
        _ imports: [GradeImportItem],
        preferredStyle: GradeStyle? = nil,
        replacing: Bool
    ) {
        let accepted = Array(imports.prefix(max(0, 10 - (replacing ? 0 : photos.count))))
        guard !accepted.isEmpty else {
            statusMessage = photos.count >= 10
                ? L10n.string("You can edit up to 10 photos at once.")
                : L10n.string("No photos were imported.")
            return
        }

        let carriesCurrentEdits = !preferences.resetEditsForNewPhoto && sourceImage != nil
        let newPhotoSettings = carriesCurrentEdits
            ? settings
            : Self.defaultSettings(preferredStyle: preferredStyle, preferences: preferences)

        if replacing {
            cancelBackgroundWork()
            photos = []
            currentIndex = 0
            undoStacks = [:]
            redoStacks = [:]
        } else {
            syncCurrentPhoto()
        }

        let newPhotos = accepted.map { item in
            GradeSessionPhoto(
                id: UUID(),
                image: item.image,
                thumbnail: item.thumbnail,
                settings: newPhotoSettings,
                automaticAccent: .warmGray,
                isAccentCustomized: carriesCurrentEdits && isAccentCustomized,
                styleSessions: [
                    newPhotoSettings.style: GradeStyleSession(
                        settings: newPhotoSettings,
                        isAccentCustomized: carriesCurrentEdits && isAccentCustomized
                    )
                ],
                metadata: item.metadata
            )
        }
        let firstNewIndex = photos.count
        photos.append(contentsOf: newPhotos)
        currentIndex = replacing ? 0 : firstNewIndex
        loadCurrentPhoto(expandStyleRail: preferredStyle == nil)
        if let preferredStyle { preferences.lastGradeStyle = preferredStyle }
        if preferences.autoAccent {
            analyzeAccents(for: photos.map { ($0.id, $0.thumbnail) })
        }
        statusMessage = nil
    }

    func selectPhoto(at index: Int) {
        guard photos.indices.contains(index), index != currentIndex else { return }
        syncCurrentPhoto()
        currentIndex = index
        loadCurrentPhoto(expandStyleRail: false)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func selectStyle(_ style: GradeStyle) {
        guard photos.indices.contains(currentIndex) else { return }
        guard style != settings.style else {
            if sourceImage != nil { isStyleRailExpanded = false }
            return
        }
        recordUndo()
        let preservedAccent = settings.accent
        let preservedAccentPoint = settings.accentPoint
        let preservedAccentStrength = settings.accentStrength
        let preservedAccentCustomization = isAccentCustomized
        syncCurrentPhoto()
        let session = photos[currentIndex].styleSessions[style]
            ?? Self.defaultStyleSession(style: style, automaticAccent: automaticAccent)
        var nextSettings = session.settings
        nextSettings.accent = preservedAccent
        nextSettings.accentPoint = preservedAccentPoint
        nextSettings.accentStrength = preservedAccentStrength
        settings = nextSettings
        isAccentCustomized = preservedAccentCustomization
        if sourceImage != nil { isStyleRailExpanded = false }
        activeSurface = .style
        preferences.lastGradeStyle = style
        syncCurrentPhoto()
        UISelectionFeedbackGenerator().selectionChanged()
        render()
    }

    func applyStyleToAll() {
        guard photos.count > 1 else { return }
        syncCurrentPhoto()
        for index in photos.indices where index != currentIndex {
            var targetSettings = photos[index].settings
            targetSettings.style = settings.style
            targetSettings.stylePoint = settings.stylePoint
            targetSettings.styleStrength = settings.styleStrength
            photos[index].settings = targetSettings
            photos[index].styleSessions[settings.style] = GradeStyleSession(
                settings: targetSettings,
                isAccentCustomized: photos[index].isAccentCustomized
            )
        }
        statusMessage = L10n.format("Applied %@ to all photos", settings.style.rawValue)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func removePhoto() {
        guard photos.indices.contains(currentIndex) else { return }
        let removedID = photos[currentIndex].id
        photos.remove(at: currentIndex)
        undoStacks[removedID] = nil
        redoStacks[removedID] = nil
        if photos.isEmpty {
            clearSessionState()
        } else {
            currentIndex = min(currentIndex, photos.count - 1)
            loadCurrentPhoto(expandStyleRail: false)
        }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    func removeAllPhotos() {
        cancelBackgroundWork()
        photos = []
        undoStacks = [:]
        redoStacks = [:]
        clearSessionState()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    func updateStylePoint(_ point: CGPoint) {
        guard settings.stylePoint != point else { return }
        recordUndo(coalescingKey: "style-point")
        activeSurface = .style
        settings.stylePoint = point
        syncCurrentPhoto()
        render()
    }

    func updateAccentPoint(_ point: CGPoint) {
        guard settings.accentPoint != point else { return }
        recordUndo(coalescingKey: "accent-point")
        activeSurface = .accent
        settings.accentPoint = point
        syncCurrentPhoto()
        render()
    }

    func setCustomAccent(_ color: Color) {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return }
        let accent = AccentColor(red: Double(red), green: Double(green), blue: Double(blue))
        guard settings.accent != accent || !isAccentCustomized else { return }
        recordUndo(coalescingKey: "custom-accent")
        settings.accent = accent
        isAccentCustomized = true
        activeSurface = .accent
        syncCurrentPhoto()
        render()
    }

    func useAutomaticAccent() {
        guard isAccentCustomized || settings.accent != automaticAccent else { return }
        recordUndo()
        settings.accent = automaticAccent
        isAccentCustomized = false
        activeSurface = .accent
        syncCurrentPhoto()
        render()
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func updateStrength(_ value: Double) {
        let currentValue = activeSurface == .style ? settings.styleStrength : settings.accentStrength
        guard currentValue != value else { return }
        recordUndo(coalescingKey: activeSurface == .style ? "style-strength" : "accent-strength")
        switch activeSurface {
        case .style: settings.styleStrength = value
        case .accent: settings.accentStrength = value
        }
        syncCurrentPhoto()
        render()
    }

    func activate(_ surface: ActiveGradeSurface) {
        guard activeSurface != surface else { return }
        activeSurface = surface
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func undo() {
        guard let photoID = currentPhoto?.id,
              var stack = undoStacks[photoID],
              let previous = stack.popLast() else { return }
        var redo = redoStacks[photoID] ?? []
        redo.append(currentEditState)
        redoStacks[photoID] = Array(redo.suffix(50))
        undoStacks[photoID] = stack
        applyEditState(previous)
        resetHistoryCoalescing()
        refreshHistoryAvailability()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    func redo() {
        guard let photoID = currentPhoto?.id,
              var stack = redoStacks[photoID],
              let next = stack.popLast() else { return }
        var undo = undoStacks[photoID] ?? []
        undo.append(currentEditState)
        undoStacks[photoID] = Array(undo.suffix(50))
        redoStacks[photoID] = stack
        applyEditState(next)
        resetHistoryCoalescing()
        refreshHistoryAvailability()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    func exportImage() async -> UIImage? {
        guard let sourceImage, !isExporting else { return nil }
        syncCurrentPhoto()
        let currentSettings = settings
        isExporting = true
        let image = await Task.detached(priority: .userInitiated) {
            autoreleasepool {
                ImageRenderer.gradeImage(sourceImage, settings: currentSettings, maxDimension: 4800)
            }
        }.value
        isExporting = false
        return image
    }

    func export(
        format: HibiscusExportFormat,
        batch: Bool,
        polaroidComposition: PolaroidComposition = .empty,
        paletteComposition: PaletteComposition = .standard
    ) async -> [UIImage] {
        guard !isExporting else { return [] }
        syncCurrentPhoto()
        let selectedPhotos: [GradeSessionPhoto]
        if batch {
            selectedPhotos = photos
        } else if let currentPhoto {
            selectedPhotos = [currentPhoto]
        } else {
            selectedPhotos = []
        }
        guard !selectedPhotos.isEmpty else { return [] }

        isExporting = true
        let images: [UIImage] = await Task.detached(priority: .userInitiated) {
            var rendered: [UIImage] = []
            for photo in selectedPhotos {
                if let image = autoreleasepool(invoking: { () -> UIImage? in
                    guard let edited = ImageRenderer.gradeImage(
                        photo.image,
                        settings: photo.settings,
                        maxDimension: 4800
                    ) else { return nil }
                    return HibiscusExportRenderer.render(
                        editedImage: edited,
                        format: format,
                        settings: photo.settings,
                        metadata: photo.metadata,
                        polaroidComposition: polaroidComposition,
                        paletteComposition: paletteComposition
                    )
                }) {
                    rendered.append(image)
                }
            }
            return rendered
        }.value
        isExporting = false
        return images
    }

    func exportFiles(
        format: HibiscusExportFormat,
        batch: Bool,
        polaroidComposition: PolaroidComposition = .empty,
        paletteComposition: PaletteComposition = .standard
    ) async -> [URL] {
        guard !isExporting else { return [] }
        syncCurrentPhoto()
        let selectedPhotos: [GradeSessionPhoto]
        if batch {
            selectedPhotos = photos
        } else if let currentPhoto {
            selectedPhotos = [currentPhoto]
        } else {
            selectedPhotos = []
        }
        guard !selectedPhotos.isEmpty else { return [] }

        isExporting = true
        let preservesMetadata = preferences.preserveMetadata
        let includesLocation = preferences.includeLocation
        let urls: [URL] = await Task.detached(priority: .userInitiated) {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("HibiscusExports", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                return []
            }

            var files: [URL] = []
            for (index, photo) in selectedPhotos.enumerated() {
                autoreleasepool {
                    guard let edited = ImageRenderer.gradeImage(
                        photo.image,
                        settings: photo.settings,
                        maxDimension: 4800
                    ) else { return }
                    let rendered = HibiscusExportRenderer.render(
                        editedImage: edited,
                        format: format,
                        settings: photo.settings,
                        metadata: photo.metadata,
                        polaroidComposition: polaroidComposition,
                        paletteComposition: paletteComposition
                    )
                    guard let data = HibiscusExportRenderer.jpegData(
                        for: rendered,
                        metadata: photo.metadata,
                        preservesMetadata: format == .photo && preservesMetadata,
                        includesLocation: includesLocation
                    ) else { return }
                    let url = directory.appendingPathComponent(
                        String(format: "Hibiscus-%02d-%@.jpg", index + 1, format.rawValue)
                    )
                    do {
                        try data.write(to: url, options: .atomic)
                        files.append(url)
                    } catch { }
                }
            }
            if files.isEmpty { try? FileManager.default.removeItem(at: directory) }
            return files
        }.value
        isExporting = false
        return urls
    }

    func save(
        format: HibiscusExportFormat,
        batch: Bool,
        polaroidComposition: PolaroidComposition = .empty,
        paletteComposition: PaletteComposition = .standard
    ) {
        Task {
            let images = await export(
                format: format,
                batch: batch,
                polaroidComposition: polaroidComposition,
                paletteComposition: paletteComposition
            )
            guard !images.isEmpty else {
                statusMessage = L10n.string("Couldn’t render this export.")
                return
            }
            saveToPhotos(images)
        }
    }

    func save() {
        Task {
            guard let image = await exportImage() else {
                statusMessage = L10n.string("Couldn’t render this photo.")
                return
            }
            saveToPhotos([image])
        }
    }

    func saveToPhotos(_ images: [UIImage]) {
        guard !images.isEmpty else { return }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard let store = self else { return }
            guard status == .authorized || status == .limited else {
                Task { @MainActor in store.statusMessage = L10n.string("Allow photo access in Settings to save.") }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                for image in images {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
            } completionHandler: { success, _ in
                Task { @MainActor in
                    store.statusMessage = success
                        ? (images.count == 1
                            ? L10n.string("Saved to Photos")
                            : L10n.format("Saved %lld photos", Int64(images.count)))
                        : L10n.string("Couldn’t save these photos.")
                    if success { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                }
            }
        }
    }

    func saveFilesToPhotos(_ urls: [URL], completion: @escaping (Bool) -> Void) {
        guard !urls.isEmpty else {
            completion(false)
            return
        }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard let store = self else {
                Task { @MainActor in completion(false) }
                return
            }
            guard status == .authorized || status == .limited else {
                store.cleanExportFiles(urls)
                Task { @MainActor in
                    store.statusMessage = L10n.string("Allow photo access in Settings to save.")
                    completion(false)
                }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                for url in urls {
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, fileURL: url, options: nil)
                }
            } completionHandler: { success, _ in
                store.cleanExportFiles(urls)
                Task { @MainActor in
                    store.statusMessage = success
                        ? (urls.count == 1
                            ? L10n.string("Saved to Photos")
                            : L10n.format("Saved %lld photos", Int64(urls.count)))
                        : L10n.string("Couldn’t save these photos.")
                    if success { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                    completion(success)
                }
            }
        }
    }

    nonisolated func cleanExportFiles(_ urls: [URL]) {
        let directories = Set(urls.map { $0.deletingLastPathComponent() })
        for directory in directories {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private static func defaultSettings(
        preferredStyle: GradeStyle?,
        preferences: AppPreferences
    ) -> GradeSettings {
        var settings = GradeSettings()
        settings.style = preferredStyle
            ?? (preferences.rememberLastStyle ? preferences.lastGradeStyle : .pure)
        settings.stylePoint = CGPoint(x: 0.5, y: 0.5)
        settings.accentPoint = CGPoint(x: 0.5, y: 0.5)
        settings.accent = .warmGray
        settings.styleStrength = 0.78
        settings.accentStrength = 0.52
        return settings
    }

    private static func defaultStyleSession(
        style: GradeStyle,
        automaticAccent: AccentColor
    ) -> GradeStyleSession {
        var settings = GradeSettings()
        settings.style = style
        settings.stylePoint = CGPoint(x: 0.5, y: 0.5)
        settings.accentPoint = CGPoint(x: 0.5, y: 0.5)
        settings.styleStrength = 0.78
        settings.accentStrength = 0.52
        settings.accent = automaticAccent
        return GradeStyleSession(settings: settings, isAccentCustomized: false)
    }

    private func loadCurrentPhoto(expandStyleRail: Bool) {
        guard let photo = currentPhoto else {
            clearSessionState()
            return
        }
        settings = photo.settings
        automaticAccent = photo.automaticAccent
        isAccentCustomized = photo.isAccentCustomized
        activeSurface = .style
        isStyleRailExpanded = expandStyleRail
        isShowingOriginal = false
        thumbnails = [:]
        previewRenderer.load(photo.image, settings: settings)
        generateThumbnails(for: photo.thumbnail)
        resetHistoryCoalescing()
        refreshHistoryAvailability()
    }

    private func syncCurrentPhoto() {
        guard photos.indices.contains(currentIndex) else { return }
        photos[currentIndex].settings = settings
        photos[currentIndex].automaticAccent = automaticAccent
        photos[currentIndex].isAccentCustomized = isAccentCustomized
        photos[currentIndex].styleSessions[settings.style] = GradeStyleSession(
            settings: settings,
            isAccentCustomized: isAccentCustomized
        )
    }

    private func clearSessionState() {
        thumbnailToken?.cancel()
        currentIndex = 0
        thumbnails = [:]
        settings = Self.defaultSettings(preferredStyle: nil, preferences: preferences)
        automaticAccent = .warmGray
        isAccentCustomized = false
        activeSurface = .style
        isStyleRailExpanded = true
        isShowingOriginal = false
        statusMessage = nil
        previewRenderer.clear()
        resetHistoryCoalescing()
        refreshHistoryAvailability()
    }

    private func cancelBackgroundWork() {
        thumbnailToken?.cancel()
        thumbnailGeneration += 1
        analysisGeneration += 1
    }

    private var currentEditState: GradeEditState {
        GradeEditState(
            settings: settings,
            isAccentCustomized: isAccentCustomized,
            activeSurface: activeSurface
        )
    }

    private func recordUndo(coalescingKey: String? = nil) {
        guard let photoID = currentPhoto?.id else { return }
        let now = Date()
        let shouldCoalesce = coalescingKey != nil
            && lastCoalescingKey == coalescingKey
            && lastCoalescingPhotoID == photoID
            && now.timeIntervalSince(lastCoalescingTime) < 0.4

        lastCoalescingKey = coalescingKey
        lastCoalescingPhotoID = photoID
        lastCoalescingTime = now
        redoStacks[photoID] = []

        guard !shouldCoalesce else {
            refreshHistoryAvailability()
            return
        }

        var stack = undoStacks[photoID] ?? []
        let snapshot = currentEditState
        if stack.last != snapshot {
            stack.append(snapshot)
            undoStacks[photoID] = Array(stack.suffix(50))
        }
        refreshHistoryAvailability()
    }

    private func applyEditState(_ state: GradeEditState) {
        settings = state.settings
        isAccentCustomized = state.isAccentCustomized
        activeSurface = state.activeSurface
        preferences.lastGradeStyle = state.settings.style
        syncCurrentPhoto()
        render()
    }

    private func resetHistoryCoalescing() {
        lastCoalescingKey = nil
        lastCoalescingPhotoID = nil
        lastCoalescingTime = .distantPast
    }

    private func refreshHistoryAvailability() {
        guard let photoID = currentPhoto?.id else {
            canUndo = false
            canRedo = false
            return
        }
        canUndo = !(undoStacks[photoID] ?? []).isEmpty
        canRedo = !(redoStacks[photoID] ?? []).isEmpty
    }

    private func render() {
        previewRenderer.update(settings: settings)
    }

    private func analyzeAccents(for entries: [(UUID, UIImage)]) {
        analysisGeneration += 1
        let generation = analysisGeneration
        for (id, image) in entries {
            analysisQueue.async { [weak self] in
                let accent = autoreleasepool { AccentAnalyzer.analyze(image) }
                DispatchQueue.main.async {
                    guard let self, self.preferences.autoAccent,
                          generation == self.analysisGeneration,
                          let index = self.photos.firstIndex(where: { $0.id == id }) else { return }
                    var photo = self.photos[index]
                    photo.automaticAccent = accent
                    for style in photo.styleSessions.keys {
                        guard var session = photo.styleSessions[style], !session.isAccentCustomized else { continue }
                        session.settings.accent = accent
                        photo.styleSessions[style] = session
                    }
                    if !photo.isAccentCustomized {
                        photo.settings.accent = accent
                    }
                    self.photos[index] = photo
                    if index == self.currentIndex {
                        self.automaticAccent = accent
                        if !self.isAccentCustomized {
                            self.settings.accent = accent
                            self.syncCurrentPhoto()
                            self.render()
                        }
                    }
                }
            }
        }
    }

    private func generateThumbnails(for image: UIImage) {
        thumbnailGeneration += 1
        let generation = thumbnailGeneration
        thumbnailToken?.cancel()
        let token = RenderToken()
        thumbnailToken = token
        thumbnailQueue.async { [weak self] in
            guard !token.isCancelled else { return }
            let base = autoreleasepool { ImageRenderer.resizedImage(image, maxDimension: 320) } ?? image
            var result: [GradeStyle: UIImage] = [:]
            for style in GradeStyle.allCases {
                guard !token.isCancelled else { return }
                if let thumbnail = autoreleasepool(invoking: { ImageRenderer.styleThumbnail(base, style: style) }) {
                    result[style] = thumbnail
                }
            }
            DispatchQueue.main.async {
                guard let self, generation == self.thumbnailGeneration else { return }
                self.thumbnails = result
            }
        }
    }
}

nonisolated private final class RenderToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}
