import SwiftUI

struct CameraView: View {
    @ObservedObject var preferences: AppPreferences
    @StateObject private var camera: CameraService
    @State private var showsExposure = false
    @State private var isSelectionPanelExpanded = true
    @State private var focusPoint: CGPoint?
    @State private var focusIndicatorTask: Task<Void, Never>?
    let isActive: Bool
    let sendToGrade: (UIImage, CameraCharacter, Date?) -> Void

    init(
        preferences: AppPreferences,
        isActive: Bool,
        sendToGrade: @escaping (UIImage, CameraCharacter, Date?) -> Void
    ) {
        self.preferences = preferences
        self.isActive = isActive
        self.sendToGrade = sendToGrade
        _camera = StateObject(wrappedValue: CameraService(preferences: preferences))
    }

    var body: some View {
        ZStack(alignment: .top) {
            ZStack {
                Color(white: 0.065)
                LinearGradient(
                    colors: [Color.black.opacity(0.45), cameraSurfaceTint.opacity(0.12), Color(white: 0.065)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea()

            if let captured = camera.capturedImage {
                captureResult(captured)
            } else {
                liveCamera
            }

            if let status = camera.statusMessage {
                StatusPill(message: status)
                    .onTapGesture { camera.statusMessage = nil }
            }
        }
        .onAppear { if isActive { camera.start() } }
        .onChange(of: isActive) { _, active in
            active ? camera.start() : camera.stop()
        }
        .onDisappear { camera.stop() }
    }

    private var liveCamera: some View {
        GeometryReader { proxy in
            let previewHeight = min(proxy.size.height, proxy.size.width / camera.selectedRatio.portraitRatio)

            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    cameraPreview
                        .frame(width: proxy.size.width, height: previewHeight)
                        .clipped()
                        .overlay(alignment: .bottom) {
                            LinearGradient(
                                colors: [.clear, Color(white: 0.065).opacity(0.38)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 24)
                            .allowsHitTesting(false)
                        }
                    Spacer(minLength: 0)
                }

                if camera.authorizationState == .authorized {
                    if preferences.cameraGridEnabled {
                        CameraGrid()
                            .frame(width: proxy.size.width, height: previewHeight)
                            .allowsHitTesting(false)
                    }

                    CameraInteractionOverlay(
                        onFocus: { point, locked in
                            focusPoint = point
                            camera.focus(at: point, lock: locked)
                            focusIndicatorTask?.cancel()
                            guard !locked else { return }
                            focusIndicatorTask = Task { @MainActor in
                                try? await Task.sleep(for: .seconds(1.4))
                                guard !Task.isCancelled, !camera.focusLocked else { return }
                                withAnimation(.easeOut(duration: 0.2)) { focusPoint = nil }
                            }
                        },
                        onExposureDrag: { deltaY, dragPoint in
                            guard let focusPoint,
                                  hypot(focusPoint.x - dragPoint.x, focusPoint.y - dragPoint.y) < 0.28 else { return }
                            camera.adjustExposure(by: -Double(deltaY) / 80)
                        },
                        onPinch: { scale in
                            camera.changeZoom(by: scale)
                        }
                    )
                    .frame(width: proxy.size.width, height: previewHeight)

                    if let focusPoint {
                        FocusIndicator(isLocked: camera.focusLocked, exposure: camera.exposure)
                            .position(x: focusPoint.x * proxy.size.width, y: focusPoint.y * previewHeight)
                            .allowsHitTesting(false)
                            .transition(.opacity.combined(with: .scale(scale: 0.85)))
                    }

                    cameraTopBar
                        .padding(.horizontal, 12)
                        .padding(.top, 12)

                    zoomControl
                        .offset(y: max(70, previewHeight - 50))

                    if let countdown = camera.countdown {
                        Text("\(countdown)")
                            .font(.system(size: 72, weight: .light, design: .rounded))
                            .contentTransition(.numericText())
                            .shadow(color: .black.opacity(0.55), radius: 12)
                            .frame(width: proxy.size.width, height: previewHeight)
                    }

                    cameraControls
                        .padding(.horizontal, 10)
                        .padding(.bottom, 10)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
        }
    }

    private var zoomControl: some View {
        Button(action: camera.cycleLens) {
            Text(camera.lensLabel)
                .font(.caption.weight(.bold))
                .frame(minWidth: 38, minHeight: 26)
                .contentShape(Capsule())
                .hibiscusGlass(interactive: true, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Zoom \(camera.lensLabel)")
        .accessibilityHint("Tap for the next available lens")
        .frame(width: 280, height: 30)
        .zIndex(2)
    }

    @ViewBuilder
    private var cameraPreview: some View {
        switch camera.authorizationState {
        case .authorized:
            CameraMetalPreview(
                renderer: camera.previewRenderer,
                isActive: isActive,
                onPreviewLayerReady: camera.attachPreviewLayer
            )
                .background(Color(white: 0.025))
        case .unknown:
            ZStack {
                Color(white: 0.04)
                VStack(spacing: 12) {
                    ProgressView().tint(.white)
                    Text("Preparing camera…").font(.footnote)
                }
                .foregroundStyle(.white.opacity(0.8))
            }
        case .denied:
            permissionState(
                title: "Camera access is off",
                message: "Allow camera access in Settings to shoot with Hibiscus.",
                showsSettings: true
            )
        case .unavailable:
            permissionState(
                title: "Camera unavailable",
                message: "A camera isn’t available on this device.",
                showsSettings: false
            )
        }
    }

    private var cameraTopBar: some View {
        HibiscusGlassContainer(spacing: 7) {
            HStack(spacing: 7) {
                Menu {
                    Picker("Flash", selection: $camera.flashMode) {
                        ForEach(CaptureFlashMode.allCases) { mode in
                            Label(mode.rawValue, systemImage: mode.systemImage).tag(mode)
                        }
                    }
                } label: {
                    Image(systemName: camera.flashMode.systemImage)
                        .frame(width: 18, height: 18)
                }
                .hibiscusGlassButtonStyle()
                .disabled(!camera.flashAvailable)
                .opacity(camera.flashAvailable ? 1 : 0.46)

                Spacer()

                Menu {
                    Section("Ratio") {
                        Picker("Photo Ratio", selection: $camera.selectedRatio) {
                            ForEach(CameraAspectRatio.allCases) { ratio in
                                Text(ratio.rawValue).tag(ratio)
                            }
                        }
                    }
                    Section("Timer") {
                        Picker("Timer", selection: $camera.selectedTimer) {
                            ForEach(CaptureTimerOption.allCases) { timer in
                                Text(timer.rawValue).tag(timer)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(camera.selectedRatio.rawValue)
                        if camera.selectedTimer != .off {
                            Image(systemName: "timer")
                            Text(camera.selectedTimer.rawValue)
                        }
                    }
                    .font(.caption2.weight(.bold))
                    .frame(minHeight: 18)
                }
                .hibiscusGlassButtonStyle()

                Menu {
                    Section("HEIF") {
                        ForEach(camera.availableMegapixels, id: \.self) { megapixels in
                            Button("\(megapixels) MP") {
                                camera.selectCapture(format: .processed, megapixels: megapixels)
                            }
                        }
                    }
                    Section("RAW") {
                        ForEach(camera.availableRawMegapixels, id: \.self) { megapixels in
                            Button("RAW \(megapixels) MP") {
                                camera.selectCapture(format: .raw, megapixels: megapixels)
                            }
                        }
                    }
                } label: {
                    topSettingLabel(
                        camera.selectedFormat == .raw
                            ? "RAW \(camera.selectedMegapixels)"
                            : "\(camera.selectedMegapixels) MP"
                    )
                }
                .hibiscusGlassButtonStyle()
            }
        }
    }

    private func topSettingLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .lineLimit(1)
            .frame(minWidth: 24, minHeight: 18)
    }

    private var cameraControls: some View {
        HibiscusGlassContainer(spacing: 6) {
            VStack(spacing: 6) {
                Button {
                    withAnimation(.snappy(duration: 0.28)) {
                        isSelectionPanelExpanded.toggle()
                    }
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    HStack(spacing: 6) {
                        CameraCharacterIcon(character: camera.selectedCharacter, size: 27, fontSize: 17)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(camera.selectedCharacter.name)
                                .font(.subheadline.weight(.semibold))
                            Text(camera.selectedCharacter.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(isSelectionPanelExpanded ? "Hide" : "Controls")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Image(systemName: isSelectionPanelExpanded ? "chevron.down" : "chevron.up")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isSelectionPanelExpanded {
                    expandedCameraSelections
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                if showsExposure {
                    exposureControl
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))
                }

                shutterRow
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .hibiscusGlass(
                tint: cameraSurfaceTint.opacity(0.075),
                in: RoundedRectangle(cornerRadius: 26, style: .continuous)
            )
        }
    }

    private var cameraSurfaceTint: Color {
        camera.selectedCharacter.identityColor
    }

    private var expandedCameraSelections: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 7) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(CameraCharacter.allCases) { character in
                            Button {
                                camera.selectedCharacter = character
                                UISelectionFeedbackGenerator().selectionChanged()
                            } label: {
                                VStack(spacing: 5) {
                                    CameraCharacterIcon(character: character, size: 36, fontSize: 23)
                                    .overlay {
                                        Circle()
                                            .stroke(.white.opacity(camera.selectedCharacter == character ? 0.72 : 0), lineWidth: 1)
                                            .padding(1.5)
                                    }
                                    .scaleEffect(camera.selectedCharacter == character ? 1.035 : 1)
                                    .shadow(
                                        color: .black.opacity(camera.selectedCharacter == character ? 0.30 : 0.16),
                                        radius: camera.selectedCharacter == character ? 3 : 2,
                                        y: 2
                                    )

                                    Text(character.name)
                                        .font(.caption2.weight(camera.selectedCharacter == character ? .bold : .medium))
                                        .foregroundStyle(.white.opacity(camera.selectedCharacter == character ? 1 : 0.72))
                                        .lineLimit(1)
                                }
                                .frame(width: 52)
                                .animation(.snappy(duration: 0.18), value: camera.selectedCharacter)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                }

                Button {
                    preferences.cameraGridEnabled.toggle()
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    Label("Grid", systemImage: preferences.cameraGridEnabled ? "grid" : "square")
                        .frame(maxWidth: .infinity)
                }
                .hibiscusGlassButtonStyle(.clear)
                .font(.caption.weight(.semibold))
            }
        }
        .frame(maxHeight: 108)
    }

    private var exposureControl: some View {
        HStack(spacing: 9) {
            Image(systemName: "minus")
            Slider(value: Binding(get: { camera.exposure }, set: camera.setExposure), in: -2...2)
                .tint(.white)
            Image(systemName: "plus")
        }
        .font(.caption2)
        .padding(.horizontal, 20)
        .frame(height: 30)
    }

    private var shutterRow: some View {
        HStack {
            Button {
                withAnimation(.snappy(duration: 0.22)) { showsExposure.toggle() }
            } label: {
                Image(systemName: "plusminus.circle")
                    .font(.system(size: 21, weight: .medium))
                    .frame(width: 28, height: 28)
            }
            .hibiscusGlassButtonStyle(.clear)

            Spacer()

            Button(action: camera.capture) {
                Circle()
                    .fill(.white)
                    .frame(width: 58, height: 58)
                    .overlay { Circle().stroke(.black.opacity(0.78), lineWidth: 3).padding(5) }
            }
            .buttonStyle(.plain)
            .hibiscusGlass(.clear, interactive: true, in: Circle())
            .disabled(!camera.isRunning || camera.countdown != nil || camera.isCapturing)

            Spacer()

            Button(action: camera.switchCamera) {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 21, weight: .medium))
                    .frame(width: 28, height: 28)
            }
            .hibiscusGlassButtonStyle(.clear)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
    }

    private func permissionState(title: String, message: String, showsSettings: Bool) -> some View {
        ZStack {
            Color(white: 0.04)
            VStack(spacing: 10) {
                Image(systemName: "camera.fill").font(.title)
                Text(title).font(.headline)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
                if showsSettings {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .hibiscusGlassButtonStyle(tint: .white)
                    .foregroundStyle(.black)
                }
            }
            .foregroundStyle(.white)
            .padding(24)
            .hibiscusGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(20)
        }
    }

    private func captureResult(_ image: UIImage) -> some View {
        GeometryReader { proxy in
            let displayImage = camera.capturedPreviewImage ?? image
            let imageRatio = max(0.01, displayImage.size.width / displayImage.size.height)
            let maximumWidth = max(1, proxy.size.width - 24)
            let maximumHeight = max(1, proxy.size.height - 170)
            let photoWidth = min(maximumWidth, maximumHeight * imageRatio)
            let photoHeight = photoWidth / imageRatio

            VStack(spacing: 10) {
                PhotoFillView(image: displayImage)
                    .frame(width: photoWidth, height: photoHeight)
                    .background(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(.white.opacity(0.10), lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.26), radius: 10, y: 4)

                captureMetadata

                Spacer(minLength: 0)

                HibiscusGlassContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        resultButton("Retake", systemImage: "arrow.counterclockwise", action: camera.retake)
                        resultButton("Grade", systemImage: "circle.lefthalf.filled") {
                            if let result = camera.capturedImage {
                                sendToGrade(result, camera.selectedCharacter, camera.capturedDate)
                            }
                        }
                        .disabled(camera.isProcessingCapture)
                        .opacity(camera.isProcessingCapture ? 0.52 : 1)
                        resultButton("Save", systemImage: "square.and.arrow.down", action: camera.saveCapture)
                            .disabled(camera.isProcessingCapture)
                            .opacity(camera.isProcessingCapture ? 0.52 : 1)
                    }
                }
                .frame(height: 46)
            }
            .padding(.top, 22)
            .padding(.horizontal, 12)
            .padding(.bottom, 26)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
    }

    private var captureMetadata: some View {
        HStack(spacing: 9) {
            CameraCharacterIcon(character: camera.selectedCharacter, size: 28, fontSize: 15)

            VStack(alignment: .leading, spacing: 1) {
                Text(camera.selectedCharacter.name)
                    .font(.caption.weight(.semibold))
                Text(camera.selectedCharacter.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 2) {
                if camera.isProcessingCapture {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text("Finishing")
                    }
                } else {
                    Text("Ready")
                }
                Text("\(camera.selectedMegapixels) MP · \(camera.selectedFormat.rawValue) · \(camera.selectedRatio.rawValue)")
                    .foregroundStyle(.secondary)
            }
            .font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 11)
        .frame(height: 46)
        .hibiscusGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .frame(maxWidth: .infinity)
    }

    private func resultButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .hibiscusGlassButtonStyle()
    }
}

private struct CameraGrid: View {
    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                Spacer()
                Rectangle().fill(.white.opacity(0.22)).frame(width: 0.5)
                Spacer()
                Rectangle().fill(.white.opacity(0.22)).frame(width: 0.5)
                Spacer()
            }
            VStack(spacing: 0) {
                Spacer()
                Rectangle().fill(.white.opacity(0.22)).frame(height: 0.5)
                Spacer()
                Rectangle().fill(.white.opacity(0.22)).frame(height: 0.5)
                Spacer()
            }
        }
        .shadow(color: .black.opacity(0.22), radius: 1)
    }
}

private struct FocusIndicator: View {
    let isLocked: Bool
    let exposure: Double

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(.white.opacity(0.92), lineWidth: 1)
                .frame(width: 48, height: 48)
                .shadow(color: .black.opacity(0.4), radius: 2)
            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
            }
            if abs(exposure) > 0.05 {
                Text(String(format: "%+.1f EV", exposure))
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(.black.opacity(0.38), in: Capsule())
                    .offset(y: 36)
            }
        }
    }
}

private struct CameraInteractionOverlay: UIViewRepresentable {
    let onFocus: (CGPoint, Bool) -> Void
    let onExposureDrag: (CGFloat, CGPoint) -> Void
    let onPinch: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.longPress(_:)))
        longPress.minimumPressDuration = 0.48
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch(_:)))

        tap.require(toFail: longPress)
        pan.delegate = context.coordinator
        pinch.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(longPress)
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(pinch)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: CameraInteractionOverlay

        init(parent: CameraInteractionOverlay) {
            self.parent = parent
        }

        @objc func tap(_ recognizer: UITapGestureRecognizer) {
            guard let view = recognizer.view else { return }
            parent.onFocus(normalizedPoint(recognizer.location(in: view), in: view), false)
        }

        @objc func longPress(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began, let view = recognizer.view else { return }
            parent.onFocus(normalizedPoint(recognizer.location(in: view), in: view), true)
        }

        @objc func pan(_ recognizer: UIPanGestureRecognizer) {
            guard recognizer.state == .changed, let view = recognizer.view else { return }
            let translation = recognizer.translation(in: view)
            let point = normalizedPoint(recognizer.location(in: view), in: view)
            parent.onExposureDrag(translation.y, point)
            recognizer.setTranslation(.zero, in: view)
        }

        @objc func pinch(_ recognizer: UIPinchGestureRecognizer) {
            guard recognizer.state == .changed else { return }
            parent.onPinch(recognizer.scale)
            recognizer.scale = 1
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            gestureRecognizer is UIPinchGestureRecognizer || otherGestureRecognizer is UIPinchGestureRecognizer
        }

        private func normalizedPoint(_ point: CGPoint, in view: UIView) -> CGPoint {
            CGPoint(
                x: min(1, max(0, point.x / max(1, view.bounds.width))),
                y: min(1, max(0, point.y / max(1, view.bounds.height)))
            )
        }
    }
}
