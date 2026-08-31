@preconcurrency import AVFoundation
import Combine
import CoreImage
import Photos
import SwiftUI
import UIKit

enum CameraAuthorizationState {
    case unknown
    case authorized
    case denied
    case unavailable
}

nonisolated struct CameraLensOption: Identifiable, Equatable, Sendable {
    let factor: Double
    let label: String

    var id: String { label }
}

nonisolated private struct CameraLensTarget {
    let displayFactor: CGFloat
    let device: AVCaptureDevice
    let deviceZoomFactor: CGFloat
}

@MainActor
final class CameraService: NSObject, ObservableObject {
    @Published private(set) var capturedImage: UIImage?
    @Published private(set) var capturedPreviewImage: UIImage?
    @Published private(set) var capturedDate: Date?
    @Published private(set) var authorizationState: CameraAuthorizationState = .unknown
    @Published private(set) var isRunning = false
    @Published private(set) var flashAvailable = false
    @Published var flashMode: CaptureFlashMode = .auto
    @Published private(set) var lensLabel = "1×"
    @Published private(set) var lensOptions = [CameraLensOption(factor: 1, label: "1×")]
    @Published private(set) var exposure: Double = 0
    @Published var selectedCharacter: CameraCharacter = .alpha {
        didSet {
            renderCharacter = selectedCharacter
#if DEBUG && targetEnvironment(simulator)
            refreshSimulatorDemoPreview()
#endif
            if !isApplyingSessionDefaults {
                preferences.lastCameraCharacter = selectedCharacter
            }
        }
    }
    @Published var selectedRatio: CameraAspectRatio = .standard {
        didSet { captureAspectRatio = selectedRatio.portraitRatio }
    }
    @Published var selectedTimer: CaptureTimerOption = .off
    @Published private(set) var availableMegapixels: [Int] = [12]
    @Published private(set) var availableRawMegapixels: [Int] = []
    @Published private(set) var selectedMegapixels = 12
    @Published var selectedFormat: CaptureFormatOption = .processed {
        didSet { captureFormat = selectedFormat }
    }
    @Published private(set) var isRAWAvailable = false
    @Published private(set) var isCapturing = false
    @Published private(set) var isProcessingCapture = false
    @Published private(set) var countdown: Int?
    @Published var statusMessage: String?

    nonisolated let previewRenderer = CameraPreviewRenderer()
    nonisolated(unsafe) private let session = AVCaptureSession()
    nonisolated(unsafe) private let photoOutput = AVCapturePhotoOutput()
    nonisolated(unsafe) private let videoOutput = AVCaptureVideoDataOutput()
    nonisolated private let sessionQueue = DispatchQueue(label: "dev.hibiscus.camera-session", qos: .userInitiated)
    nonisolated private let videoQueue = DispatchQueue(label: "dev.hibiscus.camera-preview", qos: .userInteractive)
    nonisolated private let photoProcessingQueue = DispatchQueue(label: "dev.hibiscus.camera-processing", qos: .userInitiated)
    nonisolated(unsafe) private var cameraInput: AVCaptureDeviceInput?
    nonisolated(unsafe) private var position: AVCaptureDevice.Position = .back
    nonisolated(unsafe) private var lensFactors: [CGFloat] = [1]
    nonisolated(unsafe) private var lensIndex = 0
    nonisolated(unsafe) private var renderCharacter: CameraCharacter = .alpha
    nonisolated(unsafe) private var captureAspectRatio: CGFloat = CameraAspectRatio.standard.portraitRatio
    nonisolated(unsafe) private var captureFormat: CaptureFormatOption = .processed
    nonisolated private let resolutionLock = NSLock()
    nonisolated(unsafe) private var supportedPhotoDimensions: [CMVideoDimensions] = []
    nonisolated(unsafe) private var capturePhotoDimensions = CMVideoDimensions(width: 0, height: 0)
    nonisolated(unsafe) private var captureTargetMegapixels = 12
    nonisolated(unsafe) private var pendingProcessedImage: UIImage?
    nonisolated(unsafe) private var pendingPreviewImage: UIImage?
    nonisolated(unsafe) private var pendingRawData: Data?
    nonisolated(unsafe) private var captureProcessingToken = UUID()
    private var previewLayer: CALayer?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var previewRotationObservation: NSKeyValueObservation?
    private var timerTask: Task<Void, Never>?
    private let preferences: AppPreferences
    private var isApplyingSessionDefaults = false
#if DEBUG && targetEnvironment(simulator)
    nonisolated(unsafe) private var isSimulatorDemoCameraEnabled = false
    private var simulatorDemoSourceImage: UIImage?
#endif

    init(preferences: AppPreferences) {
        self.preferences = preferences
        super.init()
        isApplyingSessionDefaults = true
        let initialCharacter = preferences.defaultCamera == .lastUsed
            ? preferences.lastCameraCharacter
            : .alpha
        selectedCharacter = initialCharacter
        renderCharacter = initialCharacter
        selectedRatio = preferences.defaultAspectRatio
        captureAspectRatio = preferences.defaultAspectRatio.portraitRatio
        exposure = preferences.rememberExposure ? preferences.lastExposure : 0
        isApplyingSessionDefaults = false
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: authorizationState = .authorized
        case .denied, .restricted: authorizationState = .denied
        case .notDetermined: authorizationState = .unknown
        @unknown default: authorizationState = .denied
        }
    }

#if DEBUG && targetEnvironment(simulator)
    func configureSimulatorDemoCamera(enabled: Bool, image: UIImage?) {
        let wasEnabled = isSimulatorDemoCameraEnabled
        isSimulatorDemoCameraEnabled = enabled
        simulatorDemoSourceImage = image

        if enabled {
            authorizationState = .authorized
            flashAvailable = true
            lensOptions = [
                CameraLensOption(factor: 0.5, label: "0.5×"),
                CameraLensOption(factor: 1, label: "1×"),
                CameraLensOption(factor: 2, label: "2×"),
                CameraLensOption(factor: 4, label: "4×"),
                CameraLensOption(factor: 8, label: "8×")
            ]
            if !lensOptions.contains(where: { $0.label == lensLabel }) {
                lensLabel = "1×"
            }
            availableMegapixels = [12, 24, 48]
            availableRawMegapixels = []
            isRAWAvailable = false
            selectedFormat = .processed
            if !availableMegapixels.contains(selectedMegapixels) {
                selectedMegapixels = 24
            }
            sessionQueue.async { [weak self] in
                guard let self, self.session.isRunning else { return }
                self.session.stopRunning()
            }
            if isRunning || wasEnabled {
                startSimulatorDemoCamera()
            }
        } else if wasEnabled {
            previewRenderer.clear()
            isRunning = false
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: authorizationState = .authorized
            case .denied, .restricted: authorizationState = .denied
            case .notDetermined: authorizationState = .unknown
            @unknown default: authorizationState = .denied
            }
        }
    }
#endif

    func start() {
        previewRenderer.resume()
        isApplyingSessionDefaults = true
        selectedCharacter = preferences.defaultCamera == .lastUsed
            ? preferences.lastCameraCharacter
            : .alpha
        selectedRatio = preferences.defaultAspectRatio
        isApplyingSessionDefaults = false
        capturedImage = nil
        capturedPreviewImage = nil
        capturedDate = nil
        if cameraInput != nil {
            setExposure(preferences.rememberExposure ? preferences.lastExposure : 0)
        } else if !preferences.rememberExposure {
            exposure = 0
        }
#if DEBUG && targetEnvironment(simulator)
        if isSimulatorDemoCameraEnabled {
            startSimulatorDemoCamera()
            return
        }
#endif
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: authorizationState = .authorized
        case .denied, .restricted: authorizationState = .denied
        case .notDetermined: authorizationState = .unknown
        @unknown default: authorizationState = .denied
        }
        switch authorizationState {
        case .authorized:
            configureAndStartIfNeeded()
        case .unknown:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let service = self else { return }
                Task { @MainActor in
                    service.authorizationState = granted ? .authorized : .denied
                    if granted { service.configureAndStartIfNeeded() }
                }
            }
        case .denied, .unavailable:
            break
        }
    }

    func stop() {
        timerTask?.cancel()
        timerTask = nil
        countdown = nil
        previewRenderer.clear()
#if DEBUG && targetEnvironment(simulator)
        if isSimulatorDemoCameraEnabled {
            isRunning = false
            return
        }
#endif
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
            Task { @MainActor in self.isRunning = false }
        }
    }

    func capture() {
        guard isRunning, countdown == nil, !isCapturing else { return }
        let seconds = selectedTimer.seconds
        guard seconds > 0 else {
            captureNow()
            return
        }
        timerTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for remaining in stride(from: seconds, through: 1, by: -1) {
                guard !Task.isCancelled else { return }
                countdown = remaining
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                try? await Task.sleep(for: .seconds(1))
            }
            guard !Task.isCancelled else { return }
            countdown = nil
            captureNow()
        }
    }

    private func captureNow() {
        // Lock the most recently presented Metal frame at shutter time. Still-photo
        // processing can then continue without the viewfinder drifting afterward.
        previewRenderer.freeze()
        isCapturing = true
        isProcessingCapture = true
        capturedDate = Date()
        pendingProcessedImage = nil
        pendingPreviewImage = nil
        pendingRawData = nil
        captureProcessingToken = UUID()

#if DEBUG && targetEnvironment(simulator)
        if isSimulatorDemoCameraEnabled {
            captureSimulatorDemoPhoto()
            return
        }
#endif

        let codec: AVVideoCodecType = photoOutput.availablePhotoCodecTypes.contains(.hevc) ? .hevc : .jpeg
        let processedFormat: [String: Any] = [AVVideoCodecKey: codec]
        let settings: AVCapturePhotoSettings
        let rawTypes = photoOutput.availableRawPhotoPixelFormatTypes
        let preferredRawType = rawTypes.first(where: AVCapturePhotoOutput.isAppleProRAWPixelFormat) ?? rawTypes.first
        if captureFormat == .raw, let rawType = preferredRawType {
            settings = AVCapturePhotoSettings(rawPixelFormatType: rawType, processedFormat: processedFormat)
            if AVCapturePhotoOutput.isBayerRAWPixelFormat(rawType) {
                // Full-sensor RAW requires the physical lens at its native zoom.
                // AVFoundation requires speed prioritization for Bayer RAW.
                settings.photoQualityPrioritization = .speed
                if let device = cameraInput?.device, device.videoZoomFactor != 1 {
                    do {
                        try device.lockForConfiguration()
                        device.videoZoomFactor = 1
                        device.unlockForConfiguration()
                    } catch { }
                }
            } else {
                settings.photoQualityPrioritization = .quality
            }
        } else {
            settings = AVCapturePhotoSettings(format: processedFormat)
            settings.photoQualityPrioritization = .quality
        }
        let photoDimensions = selectedPhotoDimensions()
        if photoDimensions.width > 0, photoDimensions.height > 0 {
            settings.maxPhotoDimensions = photoDimensions
        }
        if flashAvailable {
            settings.flashMode = switch flashMode {
            case .auto: .auto
            case .on: .on
            case .off: .off
            }
        }
        let captureAngle = rotationCoordinator?.videoRotationAngleForHorizonLevelCapture ?? 90
        if let connection = photoOutput.connection(with: .video),
           connection.isVideoRotationAngleSupported(captureAngle) {
            connection.videoRotationAngle = captureAngle
        }
        photoOutput.capturePhoto(with: settings, delegate: self)
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.9)
    }

    func retake() {
        previewRenderer.resume()
        capturedImage = nil
        capturedPreviewImage = nil
        capturedDate = nil
        pendingProcessedImage = nil
        pendingPreviewImage = nil
        pendingRawData = nil
        isProcessingCapture = false
        captureProcessingToken = UUID()
        statusMessage = nil
#if DEBUG && targetEnvironment(simulator)
        if isSimulatorDemoCameraEnabled {
            startSimulatorDemoCamera()
            return
        }
#endif
        startSessionOnly()
    }

    func switchCamera() {
        guard capturedImage == nil else { return }
#if DEBUG && targetEnvironment(simulator)
        if isSimulatorDemoCameraEnabled {
            position = position == .back ? .front : .back
            UISelectionFeedbackGenerator().selectionChanged()
            return
        }
#endif
        position = position == .back ? .front : .back
        sessionQueue.async { [weak self] in self?.replaceCameraInput() }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func selectLens(_ option: CameraLensOption) {
#if DEBUG && targetEnvironment(simulator)
        if isSimulatorDemoCameraEnabled {
            lensLabel = option.label
            UISelectionFeedbackGenerator().selectionChanged()
            return
        }
#endif
        if position == .back {
            lensLabel = option.label
            sessionQueue.async { [weak self] in
                self?.selectRearLens(displayFactor: CGFloat(option.factor))
            }
            UISelectionFeedbackGenerator().selectionChanged()
            return
        }
        guard let device = cameraInput?.device,
              let factor = lensFactors.min(by: {
                  abs(Double($0) - option.factor) < abs(Double($1) - option.factor)
              }) else { return }
        setDeviceZoom(factor, on: device)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func selectNextLens() {
        guard !lensOptions.isEmpty else { return }
        let currentIndex = lensOptions.firstIndex(where: { $0.label == lensLabel }) ?? 0
        selectLens(lensOptions[(currentIndex + 1) % lensOptions.count])
    }

    func setExposure(_ value: Double) {
#if DEBUG && targetEnvironment(simulator)
        if isSimulatorDemoCameraEnabled {
            exposure = min(2, max(-2, value))
            if preferences.rememberExposure { preferences.lastExposure = exposure }
            refreshSimulatorDemoPreview()
            return
        }
#endif
        guard let device = cameraInput?.device else { return }
        let maximum = min(2, Double(device.maxExposureTargetBias))
        let minimum = max(-2, Double(device.minExposureTargetBias))
        exposure = min(maximum, max(minimum, value))
        if preferences.rememberExposure { preferences.lastExposure = exposure }
        do {
            try device.lockForConfiguration()
            device.setExposureTargetBias(Float(exposure))
            device.unlockForConfiguration()
        } catch {
            statusMessage = L10n.string("Exposure adjustment isn’t available.")
        }
    }

    func attachPreviewLayer(_ layer: CALayer) {
        guard previewLayer !== layer else { return }
        previewLayer = layer
        if let device = cameraInput?.device {
            configureRotationCoordinator(for: device)
        }
    }

    func selectCapture(format: CaptureFormatOption, megapixels: Int) {
        guard format == .processed || isRAWAvailable else { return }
        resolutionLock.lock()
        let selected: CMVideoDimensions?
        if megapixels == 24, format == .processed {
            // Native 24 MP delivery is deferred and cannot receive Hibiscus's
            // full-resolution character processing. Capture the 48 MP source and
            // produce a true 24 MP processed result locally instead.
            selected = supportedPhotoDimensions.last
        } else {
            selected = supportedPhotoDimensions.min {
                abs(Self.megapixels(for: $0) - megapixels) < abs(Self.megapixels(for: $1) - megapixels)
            }
        }
        if let selected { capturePhotoDimensions = selected }
        captureTargetMegapixels = megapixels
        resolutionLock.unlock()
        selectedFormat = format
        selectedMegapixels = megapixels
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func saveCapture() {
        guard let capturedImage else { return }
        let rawData = pendingRawData
        let processedData = capturedImage.jpegData(compressionQuality: 0.98)
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard let service = self else { return }
            guard status == .authorized || status == .limited else {
                Task { @MainActor in service.statusMessage = L10n.string("Allow photo access in Settings to save.") }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                if let rawData, let processedData {
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, data: processedData, options: nil)
                    request.addResource(with: .alternatePhoto, data: rawData, options: nil)
                } else {
                    PHAssetChangeRequest.creationRequestForAsset(from: capturedImage)
                }
            } completionHandler: { success, _ in
                Task { @MainActor in
                    service.statusMessage = success
                        ? L10n.string("Saved to Photos")
                        : L10n.string("Couldn’t save this photo.")
                    if success { UINotificationFeedbackGenerator().notificationOccurred(.success) }
                }
            }
        }
    }

#if DEBUG && targetEnvironment(simulator)
    private func startSimulatorDemoCamera() {
        guard isSimulatorDemoCameraEnabled else { return }
        authorizationState = .authorized
        isRunning = simulatorDemoSourceImage != nil
        statusMessage = simulatorDemoSourceImage == nil
            ? "No Simulator demo photo is available."
            : nil
        refreshSimulatorDemoPreview()
    }

    private func refreshSimulatorDemoPreview() {
        guard isSimulatorDemoCameraEnabled,
              !isCapturing,
              let sourceImage = simulatorDemoSourceImage,
              var source = ImageRenderer.sourceCIImage(sourceImage) else { return }
        if exposure != 0 {
            source = source.applyingFilter("CIExposureAdjust", parameters: [
                kCIInputEVKey: exposure
            ])
        }
        previewRenderer.resume()
        previewRenderer.submit(source, character: selectedCharacter)
    }

    private func captureSimulatorDemoPhoto() {
        guard let sourceImage = simulatorDemoSourceImage else {
            isCapturing = false
            isProcessingCapture = false
            previewRenderer.resume()
            statusMessage = "No Simulator demo photo is available."
            return
        }

        let character = selectedCharacter
        let aspectRatio = captureAspectRatio
        let targetMegapixels = selectedMegapixels
        let inputExposureEV = exposure
        let token = captureProcessingToken
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.9)

        photoProcessingQueue.async { [weak self] in
            let preview = autoreleasepool {
                ImageRenderer.cameraImage(
                    sourceImage,
                    character: character,
                    aspectRatio: aspectRatio,
                    targetMegapixels: min(2, targetMegapixels),
                    inputExposureEV: inputExposureEV
                ) ?? sourceImage
            }
            Task { @MainActor [weak self] in
                guard let self, self.captureProcessingToken == token else { return }
                self.pendingPreviewImage = preview
                self.pendingProcessedImage = preview
                self.capturedPreviewImage = preview
                self.capturedImage = preview
                self.isCapturing = false
                self.isRunning = false
            }

            let processed = autoreleasepool {
                ImageRenderer.cameraImage(
                    sourceImage,
                    character: character,
                    aspectRatio: aspectRatio,
                    targetMegapixels: targetMegapixels,
                    inputExposureEV: inputExposureEV
                ) ?? sourceImage
            }
            Task { @MainActor [weak self] in
                guard let self, self.captureProcessingToken == token else { return }
                self.pendingProcessedImage = processed
                self.capturedImage = processed
                self.capturedPreviewImage = processed
                self.isProcessingCapture = false
            }
        }
    }
#endif

    private func configureAndStartIfNeeded() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
#if DEBUG && targetEnvironment(simulator)
            guard !self.isSimulatorDemoCameraEnabled else { return }
#endif
            if self.cameraInput == nil { self.configureSession() }
            if let device = self.cameraInput?.device {
                Task { @MainActor in self.configureRotationCoordinator(for: device) }
            }
            self.refreshRAWAvailability()
            self.startSessionOnlyFromQueue()
        }
    }

    nonisolated private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        defer { session.commitConfiguration() }

        guard let device = preferredDevice(position: position) else {
            Task { @MainActor in self.authorizationState = .unavailable }
            return
        }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { return }
            session.addInput(input)
            cameraInput = input
            selectHighestResolutionPhotoFormat(for: device)

            videoOutput.alwaysDiscardsLateVideoFrames = true
            // The .photo preset otherwise allows AVFoundation to hand the data
            // output a deliberately small proxy buffer. Hibiscus renders that
            // buffer directly, so request the active format's full video stream
            // and let Core Image scale it to the Metal drawable instead.
            videoOutput.automaticallyConfiguresOutputBufferDimensions = false
            videoOutput.deliversPreviewSizedOutputBuffers = false
            let preferredPixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            if videoOutput.availableVideoPixelFormatTypes.contains(preferredPixelFormat) {
                videoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: preferredPixelFormat
                ]
            }
            videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
            if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
            if session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
                photoOutput.maxPhotoQualityPrioritization = .quality
                enableAppleProRAWIfSupported()
                updateMaximumPhotoDimensions(for: device)
            }

            configureVideoConnectionFallback(for: device)
            updateDeviceState(device)
        } catch {
            Task { @MainActor in
                self.authorizationState = .unavailable
                self.statusMessage = L10n.string("Hibiscus couldn’t start the camera.")
            }
        }
    }

    nonisolated private func replaceCameraInput() {
        guard let device = preferredDevice(position: position) else { return }
        replaceCameraInput(with: device)
    }

    nonisolated private func replaceCameraInput(
        with device: AVCaptureDevice,
        requestedZoomFactor: CGFloat? = nil,
        requestedDisplayFactor: CGFloat? = nil
    ) {
        session.beginConfiguration()
        if let cameraInput { session.removeInput(cameraInput) }
        do {
            let newInput = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(newInput) {
                session.addInput(newInput)
                cameraInput = newInput
                selectHighestResolutionPhotoFormat(for: device)
                enableAppleProRAWIfSupported()
                updateMaximumPhotoDimensions(for: device)
                configureVideoConnectionFallback(for: device)
                updateDeviceState(
                    device,
                    requestedZoomFactor: requestedZoomFactor,
                    requestedDisplayFactor: requestedDisplayFactor
                )
            }
        } catch {
            Task { @MainActor in self.statusMessage = L10n.string("Couldn’t switch cameras.")
            }
        }
        session.commitConfiguration()
        refreshRAWAvailability()
        Task { @MainActor in
            self.configureRotationCoordinator(for: device)
            self.isRunning = self.session.isRunning
        }
    }

    nonisolated private func refreshRAWAvailability() {
        enableAppleProRAWIfSupported()
        let rawAvailable = !photoOutput.availableRawPhotoPixelFormatTypes.isEmpty
        let rawMegapixels = rawAvailable ? supportedRAWPhotoMegapixels() : []
        Task { @MainActor in
#if DEBUG && targetEnvironment(simulator)
            guard !self.isSimulatorDemoCameraEnabled else { return }
#endif
            self.isRAWAvailable = rawAvailable
            self.availableRawMegapixels = rawMegapixels
            if !rawAvailable { self.selectedFormat = .processed }
        }
    }

    nonisolated private func enableAppleProRAWIfSupported() {
        if photoOutput.isAppleProRAWSupported && !photoOutput.isAppleProRAWEnabled {
            photoOutput.isAppleProRAWEnabled = true
        }
    }

    /// Chooses a true photo format with the largest still-photo dimensions.
    /// Do not require a 30 fps range here: on high-resolution sensors that can
    /// discard the only format exposing the native 48 MP photo dimensions.
    /// Among equivalent still formats, prefer the largest video stream so the
    /// Metal preview is not fed a low-resolution rear-camera buffer.
    nonisolated private func selectHighestResolutionPhotoFormat(for device: AVCaptureDevice) {
        guard let best = highestResolutionPhotoFormat(for: device), best !== device.activeFormat else { return }
        do {
            try device.lockForConfiguration()
            device.activeFormat = best
            device.unlockForConfiguration()
        } catch { }
    }

    nonisolated private func highestResolutionPhotoFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        let formatsWithPhotoDimensions = device.formats.filter {
            !$0.supportedMaxPhotoDimensions.isEmpty
        }
        let highestQualityFormats = formatsWithPhotoDimensions.filter(\.isHighestPhotoQualitySupported)
        let candidates = highestQualityFormats.isEmpty ? formatsWithPhotoDimensions : highestQualityFormats
        return candidates.max { lhs, rhs in
            let lhsPhotoPixels = Self.maximumPhotoPixels(for: lhs)
            let rhsPhotoPixels = Self.maximumPhotoPixels(for: rhs)
            if lhsPhotoPixels != rhsPhotoPixels { return lhsPhotoPixels < rhsPhotoPixels }
            let lhsVideo = CMVideoFormatDescriptionGetDimensions(lhs.formatDescription)
            let rhsVideo = CMVideoFormatDescriptionGetDimensions(rhs.formatDescription)
            let lhsVideoPixels = Int64(lhsVideo.width) * Int64(lhsVideo.height)
            let rhsVideoPixels = Int64(rhsVideo.width) * Int64(rhsVideo.height)
            return lhsVideoPixels < rhsVideoPixels
        }
    }

    nonisolated private func updateMaximumPhotoDimensions(for device: AVCaptureDevice) {
        let supported = device.activeFormat.supportedMaxPhotoDimensions.sorted(by: {
            Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height)
        })
        guard let maximum = supported.last else { return }
        photoOutput.maxPhotoDimensions = maximum

        var distinct: [CMVideoDimensions] = []
        for dimensions in supported where !distinct.contains(where: {
            Self.megapixels(for: $0) == Self.megapixels(for: dimensions)
        }) {
            distinct.append(dimensions)
        }
        if distinct.isEmpty { distinct = [maximum] }
        let maximumMegapixels = Self.megapixels(for: maximum)
        var values = distinct.map(Self.megapixels(for:)).filter { $0 > 0 }
        if maximumMegapixels >= 24, !values.contains(24) { values.append(24) }
        values = Array(Set(values)).sorted()
        if values.isEmpty { values = [maximumMegapixels] }
        let preferredMegapixels = values.contains(24) ? 24 : values[0]
        let preferred = preferredMegapixels == 24 ? maximum : (distinct.min {
            abs(Self.megapixels(for: $0) - preferredMegapixels) < abs(Self.megapixels(for: $1) - preferredMegapixels)
        } ?? maximum)
        resolutionLock.lock()
        supportedPhotoDimensions = distinct
        capturePhotoDimensions = preferred
        captureTargetMegapixels = preferredMegapixels
        resolutionLock.unlock()
        let publishedValues = values
        let publishedMegapixels = preferredMegapixels
        Task { @MainActor in
#if DEBUG && targetEnvironment(simulator)
            guard !self.isSimulatorDemoCameraEnabled else { return }
#endif
            self.availableMegapixels = publishedValues
            self.selectedMegapixels = publishedMegapixels
        }
    }

    nonisolated private func selectedPhotoDimensions() -> CMVideoDimensions {
        resolutionLock.lock()
        defer { resolutionLock.unlock() }
        return capturePhotoDimensions
    }

    nonisolated private func selectedTargetMegapixels() -> Int {
        resolutionLock.lock()
        defer { resolutionLock.unlock() }
        return captureTargetMegapixels
    }

    nonisolated private static func megapixels(for dimensions: CMVideoDimensions) -> Int {
        let measured = Double(dimensions.width) * Double(dimensions.height) / 1_000_000
        let nativeLabels = [12, 24, 48]
        if let label = nativeLabels.min(by: { abs(Double($0) - measured) < abs(Double($1) - measured) }),
           abs(Double(label) - measured) < 3 {
            return label
        }
        return Int(measured.rounded())
    }

    nonisolated private static func maximumPhotoPixels(for format: AVCaptureDevice.Format) -> Int64 {
        format.supportedMaxPhotoDimensions.map {
            Int64($0.width) * Int64($0.height)
        }.max() ?? 0
    }

    nonisolated private func supportedRAWPhotoMegapixels() -> [Int] {
        resolutionLock.lock()
        let values = supportedPhotoDimensions.map(Self.megapixels(for:))
        resolutionLock.unlock()
        // Surface every photo dimension the active camera format reports. RAW
        // selection then requests that exact native dimension rather than using
        // the processed 24 MP downsampling path.
        return Array(Set(values.filter { $0 > 0 })).sorted()
    }

    nonisolated private func preferredDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = position == .back
            // Virtual multi-camera devices currently cap photo delivery below
            // the native resolution of their 48 MP constituents. Use the main
            // physical camera and switch physical inputs for discrete lenses.
            ? [.builtInWideAngleCamera, .builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera]
            : [.builtInWideAngleCamera, .builtInTrueDepthCamera]
        for type in types {
            if let device = AVCaptureDevice.DiscoverySession(
                deviceTypes: [type],
                mediaType: .video,
                position: position
            ).devices.first {
                return device
            }
        }
        return nil
    }

    nonisolated private func configureVideoConnectionFallback(for device: AVCaptureDevice) {
        guard let connection = videoOutput.connection(with: .video) else { return }
        if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = device.position == .front
    }

    private func configureRotationCoordinator(for device: AVCaptureDevice) {
        guard let previewLayer else { return }
        previewRotationObservation = nil

        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotationCoordinator = coordinator
        applyPreviewRotation(coordinator.videoRotationAngleForHorizonLevelPreview, position: device.position)

        previewRotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelPreview,
            options: [.new]
        ) { [weak self, weak coordinator] _, change in
            guard let coordinator, let angle = change.newValue else { return }
            Task { @MainActor [weak self] in
                guard let self, self.rotationCoordinator === coordinator else { return }
                self.applyPreviewRotation(angle, position: device.position)
            }
        }
    }

    private func applyPreviewRotation(_ angle: CGFloat, position: AVCaptureDevice.Position) {
        sessionQueue.async { [weak self] in
            guard let self, let connection = self.videoOutput.connection(with: .video) else { return }
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = position == .front
        }
    }

    nonisolated private func selectRearLens(displayFactor: CGFloat) {
        guard let target = rearLensTargets().min(by: {
            abs($0.displayFactor - displayFactor) < abs($1.displayFactor - displayFactor)
        }) else { return }

        if cameraInput?.device.uniqueID == target.device.uniqueID {
            updateDeviceState(
                target.device,
                requestedZoomFactor: target.deviceZoomFactor,
                requestedDisplayFactor: target.displayFactor
            )
        } else {
            replaceCameraInput(
                with: target.device,
                requestedZoomFactor: target.deviceZoomFactor,
                requestedDisplayFactor: target.displayFactor
            )
        }
    }

    /// Builds the native rear-camera rail from the physical constituents. The
    /// virtual device provides Apple's display-space focal-length mapping, while
    /// each physical device keeps access to its full still-photo dimensions.
    nonisolated private func rearLensTargets() -> [CameraLensTarget] {
        let virtualTypes: [AVCaptureDevice.DeviceType] = [
            .builtInTripleCamera,
            .builtInDualWideCamera,
            .builtInDualCamera
        ]
        let virtualDevice = virtualTypes.lazy.compactMap { type in
            AVCaptureDevice.DiscoverySession(
                deviceTypes: [type],
                mediaType: .video,
                position: .back
            ).devices.first
        }.first

        var physicalDevices = virtualDevice?.constituentDevices ?? []
        if physicalDevices.isEmpty {
            physicalDevices = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInUltraWideCamera, .builtInWideAngleCamera, .builtInTelephotoCamera],
                mediaType: .video,
                position: .back
            ).devices
        }
        var seenDeviceIDs = Set<String>()
        physicalDevices = physicalDevices.filter { seenDeviceIDs.insert($0.uniqueID).inserted }
        physicalDevices.sort {
            Self.videoFieldOfView(for: $0) > Self.videoFieldOfView(for: $1)
        }
        guard !physicalDevices.isEmpty else { return [] }

        var nativeDisplayFactors: [CGFloat] = []
        if let virtualDevice {
            let multiplier = displayZoomMultiplier(for: virtualDevice)
            nativeDisplayFactors = [virtualDevice.minAvailableVideoZoomFactor]
            nativeDisplayFactors.append(contentsOf: virtualDevice.virtualDeviceSwitchOverVideoZoomFactors.map {
                CGFloat(truncating: $0)
            })
            nativeDisplayFactors = nativeDisplayFactors.map { $0 * multiplier }.sorted()
        }
        if nativeDisplayFactors.count != physicalDevices.count {
            nativeDisplayFactors = physicalDevices.enumerated().map { index, device in
                switch device.deviceType {
                case .builtInUltraWideCamera: 0.5
                case .builtInWideAngleCamera: 1
                case .builtInTelephotoCamera: index > 1 ? 3 : 2
                default: CGFloat(index + 1)
                }
            }
        }

        var targets = zip(physicalDevices, nativeDisplayFactors).map { device, displayFactor in
            CameraLensTarget(displayFactor: displayFactor, device: device, deviceZoomFactor: 1)
        }
        for (device, baseDisplayFactor) in zip(physicalDevices, nativeDisplayFactors) {
            let format = highestResolutionPhotoFormat(for: device) ?? device.activeFormat
            for zoomFactor in format.secondaryNativeResolutionZoomFactors {
                let displayFactor = baseDisplayFactor * zoomFactor
                guard zoomFactor >= device.minAvailableVideoZoomFactor,
                      zoomFactor <= device.maxAvailableVideoZoomFactor,
                      !targets.contains(where: { abs($0.displayFactor - displayFactor) < 0.025 }) else { continue }
                targets.append(CameraLensTarget(
                    displayFactor: displayFactor,
                    device: device,
                    deviceZoomFactor: zoomFactor
                ))
            }
        }
        return targets.sorted { $0.displayFactor < $1.displayFactor }
    }

    nonisolated private static func videoFieldOfView(for device: AVCaptureDevice) -> Float {
        device.formats.map(\.videoFieldOfView).max() ?? device.activeFormat.videoFieldOfView
    }

    nonisolated private func updateDeviceState(
        _ device: AVCaptureDevice,
        requestedZoomFactor: CGFloat? = nil,
        requestedDisplayFactor: CGFloat? = nil
    ) {
        let multiplier = displayZoomMultiplier(for: device)
        let minimum = device.minAvailableVideoZoomFactor
        let maximum = device.maxAvailableVideoZoomFactor
        let selectedFactor: CGFloat
        let selectedLabel: String
        let publishedOptions: [CameraLensOption]

        if device.position == .back {
            let targets = rearLensTargets()
            let selectedTarget = targets.min(by: { lhs, rhs in
                if let requestedDisplayFactor {
                    return abs(lhs.displayFactor - requestedDisplayFactor) < abs(rhs.displayFactor - requestedDisplayFactor)
                }
                let lhsMatchesDevice = lhs.device.uniqueID == device.uniqueID
                let rhsMatchesDevice = rhs.device.uniqueID == device.uniqueID
                if lhsMatchesDevice != rhsMatchesDevice { return lhsMatchesDevice }
                return abs(lhs.displayFactor - 1) < abs(rhs.displayFactor - 1)
            })
            selectedFactor = max(minimum, min(requestedZoomFactor ?? selectedTarget?.deviceZoomFactor ?? 1, maximum))
            let displayFactor = requestedDisplayFactor ?? selectedTarget?.displayFactor ?? 1
            selectedLabel = formatLens(displayFactor)
            publishedOptions = targets.map {
                CameraLensOption(factor: Double($0.displayFactor), label: formatLens($0.displayFactor))
            }
            lensFactors = [selectedFactor]
            lensIndex = 0
        } else {
            var factors: [CGFloat] = [minimum, 1 / multiplier]
            factors.append(contentsOf: device.activeFormat.secondaryNativeResolutionZoomFactors)
            factors = factors
                .filter { $0 >= minimum && $0 <= maximum }
                .sorted()
                .reduce(into: []) { result, factor in
                    if result.last.map({ abs($0 - factor) > 0.025 }) ?? true {
                        result.append(factor)
                    }
                }
            if factors.isEmpty { factors = [minimum] }
            lensFactors = factors
            lensIndex = factors.enumerated().min(by: {
                abs($0.element * multiplier - 1) < abs($1.element * multiplier - 1)
            })?.offset ?? 0
            selectedFactor = factors[lensIndex]
            selectedLabel = formatLens(selectedFactor * multiplier)
            publishedOptions = factors.map {
                CameraLensOption(factor: Double($0), label: formatLens($0 * multiplier))
            }
        }

        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            } else if device.isFocusModeSupported(.autoFocus) {
                device.focusMode = .autoFocus
            }
            if device.isSmoothAutoFocusSupported {
                device.isSmoothAutoFocusEnabled = true
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            } else if device.isExposureModeSupported(.autoExpose) {
                device.exposureMode = .autoExpose
            }
            device.isSubjectAreaChangeMonitoringEnabled = true
            device.videoZoomFactor = selectedFactor
            device.unlockForConfiguration()
        } catch { }
        Task { @MainActor in
#if DEBUG && targetEnvironment(simulator)
            guard !self.isSimulatorDemoCameraEnabled else { return }
#endif
            self.flashAvailable = device.hasFlash && device.position == .back
            self.lensLabel = selectedLabel
            self.lensOptions = publishedOptions
            self.setExposure(self.preferences.rememberExposure ? self.preferences.lastExposure : 0)
        }
    }

    private func setDeviceZoom(_ requestedFactor: CGFloat, on device: AVCaptureDevice) {
        let factor = max(device.minAvailableVideoZoomFactor, min(requestedFactor, device.maxAvailableVideoZoomFactor))
        do {
            try device.lockForConfiguration()
            device.cancelVideoZoomRamp()
            device.videoZoomFactor = factor
            device.unlockForConfiguration()
            let displayFactor = Double(factor * displayZoomMultiplier(for: device))
            lensLabel = formatLens(CGFloat(displayFactor))
            lensIndex = lensFactors.enumerated().min(by: {
                abs($0.element - factor) < abs($1.element - factor)
            })?.offset ?? 0
        } catch {
            statusMessage = L10n.string("Zoom isn’t available right now.")
        }
    }

    nonisolated private func displayZoomMultiplier(for device: AVCaptureDevice) -> CGFloat {
        if #available(iOS 18.0, *) {
            return max(0.01, device.displayVideoZoomFactorMultiplier)
        }
        return device.constituentDevices.contains(where: { $0.deviceType == .builtInUltraWideCamera }) ? 0.5 : 1
    }

    private func startSessionOnly() {
        sessionQueue.async { [weak self] in self?.startSessionOnlyFromQueue() }
    }

    nonisolated private func startSessionOnlyFromQueue() {
#if DEBUG && targetEnvironment(simulator)
        guard !isSimulatorDemoCameraEnabled else { return }
#endif
        guard !session.isRunning, cameraInput != nil else { return }
        session.startRunning()
        Task { @MainActor in self.isRunning = true }
    }

    nonisolated private func formatLens(_ factor: CGFloat) -> String {
        factor == floor(factor) ? "\(Int(factor))×" : "\(String(format: "%.1f", Double(factor)))×"
    }
}

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
#if DEBUG && targetEnvironment(simulator)
        guard !isSimulatorDemoCameraEnabled else { return }
#endif
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        // The video connection delivers physically rotated portrait buffers.
        // Front-camera mirroring is also applied at the connection level.
        let image = CIImage(cvPixelBuffer: buffer)
        let character = renderCharacter
        previewRenderer.submit(image, character: character)
    }
}

extension CameraService: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else {
            return
        }
        if photo.isRawPhoto {
            pendingRawData = data
            return
        }
        guard let image = UIImage(data: data) else { return }
        let character = renderCharacter
        let aspectRatio = captureAspectRatio
        let targetMegapixels = selectedTargetMegapixels()
        let token = captureProcessingToken
        let preview = ImageRenderer.cameraImage(
            image,
            character: character,
            aspectRatio: aspectRatio,
            targetMegapixels: min(2, targetMegapixels)
        ) ?? image
        pendingPreviewImage = preview
        pendingProcessedImage = preview

        photoProcessingQueue.async { [weak self] in
            let processed = autoreleasepool {
                ImageRenderer.cameraImage(
                    image,
                    character: character,
                    aspectRatio: aspectRatio,
                    targetMegapixels: targetMegapixels
                ) ?? image
            }
            Task { @MainActor [weak self] in
                guard let self, self.captureProcessingToken == token else { return }
                self.pendingProcessedImage = processed
                if self.capturedImage != nil {
                    self.capturedImage = processed
                    self.capturedPreviewImage = processed
                }
                self.isProcessingCapture = false
            }
        }
    }

    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {
        let processed = pendingProcessedImage
        let preview = pendingPreviewImage
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isCapturing = false
            guard error == nil, let processed else {
                self.isProcessingCapture = false
                self.previewRenderer.resume()
                self.statusMessage = L10n.string("Couldn’t capture this photo.")
                return
            }
            self.capturedImage = processed
            self.capturedPreviewImage = preview ?? processed
            self.stop()
        }
    }
}
