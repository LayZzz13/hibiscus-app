import PencilKit
import PhotosUI
import SwiftUI

struct GradeView: View {
    @ObservedObject var store: GradeStore
    @ObservedObject var preferences: AppPreferences
    let isActive: Bool
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showsPicker = false
    @State private var pickerReplacesSession = true
    @State private var pendingStyle: GradeStyle?
    @State private var shareFiles: [URL] = []
    @State private var polaroidRequest: PolaroidExportRequest?
    @State private var paletteRequest: PaletteExportRequest?
    @State private var styleRailPosition: GradeStyle?
    @State private var showsAccentPicker = false
    @State private var photoSwipeOffset: CGFloat = 0
    @State private var didCompleteShare = false
    @State private var pendingSharePhotoIDs: Set<UUID> = []
    @State private var exportedPhotoIDs: Set<UUID> = []
    @State private var showsCompletionPrompt = false

    var body: some View {
        ZStack(alignment: .top) {
            ZStack {
                Color(white: 0.075)
                if store.sourceImage != nil {
                    RadialGradient(
                        colors: [store.settings.style.tint.opacity(0.13), .clear],
                        center: .top,
                        startRadius: 30,
                        endRadius: 520
                    )
                }
            }
            .ignoresSafeArea()

            GeometryReader { proxy in
                let previewHeight = photoHeight(for: proxy.size.height - navigationClearance)
                ZStack(alignment: .top) {
                    VStack(spacing: 0) {
                        photoArea
                            .frame(height: previewHeight)

                        if store.sourceImage != nil {
                            editor(width: proxy.size.width)
                                .frame(maxHeight: .infinity, alignment: .top)
                        }
                    }
                    .padding(.bottom, navigationClearance)

                    if store.sourceImage != nil, store.isStyleRailExpanded {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.snappy(duration: 0.22)) {
                                    store.isStyleRailExpanded = false
                                }
                            }

                        styleRail
                            .frame(width: proxy.size.width)
                            .offset(y: previewHeight)
                            .zIndex(1)
                            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
                    }
                }
                .animation(.snappy(duration: 0.22), value: store.isStyleRailExpanded)
            }

            if let message = store.statusMessage {
                StatusPill(message: message)
                    .onTapGesture { store.statusMessage = nil }
            }

            if store.isExporting {
                ProgressView("Rendering")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .hibiscusGlass(in: Capsule())
                    .frame(maxHeight: .infinity, alignment: .center)
            }
        }
        .photosPicker(
            isPresented: $showsPicker,
            selection: $pickerItems,
            maxSelectionCount: photoPickerLimit,
            matching: .images
        )
        .onChange(of: pickerItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task { await importPhotos(from: newItems) }
        }
        .onChange(of: store.photos.map(\.id)) { _, photoIDs in
            exportedPhotoIDs.formIntersection(photoIDs)
            if photoIDs.isEmpty {
                pendingSharePhotoIDs = []
                didCompleteShare = false
            }
        }
        .sheet(
            isPresented: Binding(
                get: { !shareFiles.isEmpty },
                set: {
                    if !$0 {
                        store.cleanExportFiles(shareFiles)
                        shareFiles = []
                    }
                }
            ),
            onDismiss: {
                let completedPhotoIDs = pendingSharePhotoIDs
                pendingSharePhotoIDs = []
                guard didCompleteShare else { return }
                didCompleteShare = false
                registerCompletedExport(for: completedPhotoIDs)
            }
        ) {
            ShareSheet(items: shareFiles) { completed in
                didCompleteShare = completed
            }
            .ignoresSafeArea()
        }
        .sheet(item: $polaroidRequest) { request in
            PolaroidComposerSheet(
                photos: request.batch ? store.photos : store.currentPhoto.map { [$0] } ?? [],
                primaryActionShares: request.shares,
                showsMetadata: preferences.polaroidMetadata,
                showsMark: preferences.hibiscusMark,
                includesLocation: preferences.includeLocation,
                onComplete: { composition in
                    polaroidRequest = nil
                    performExport(
                        format: .polaroid,
                        batch: request.batch,
                        shares: request.shares,
                        polaroidComposition: composition
                    )
                }
            )
        }
        .sheet(item: $paletteRequest) { request in
            PaletteComposerSheet(
                photos: request.batch ? store.photos : store.currentPhoto.map { [$0] } ?? [],
                primaryActionShares: request.shares,
                onComplete: { composition in
                    paletteRequest = nil
                    performExport(
                        format: .palette,
                        batch: request.batch,
                        shares: request.shares,
                        paletteComposition: composition
                    )
                }
            )
        }
        .sheet(isPresented: $showsAccentPicker) {
            AccentColorPickerSheet(
                color: Binding(
                    get: { store.settings.accent.color },
                    set: store.setCustomAccent
                ),
                isAutomatic: !store.isAccentCustomized,
                canApplyToAll: store.batchCount > 1 && store.isAccentCustomized,
                onUseAutomatic: store.useAutomaticAccent,
                onApplyToAll: store.applyCustomAccentToAll
            )
        }
        .alert("Continue Editing?", isPresented: $showsCompletionPrompt) {
            Button("Continue Editing", role: .cancel) {}
            Button("Done", role: .destructive) {
                store.removeAllPhotos()
            }
        } message: {
            Text("Your export is complete. Keep this temporary Grade session open?")
        }
    }

    @ViewBuilder
    private var photoArea: some View {
        if let source = store.sourceImage {
            ZStack(alignment: .bottom) {
                GradeMetalPreview(
                    renderer: store.previewRenderer,
                    isActive: isActive && !store.isShowingOriginal
                )
                    .background(Color(uiColor: .secondarySystemBackground))
                    .contentShape(Rectangle())
                    .onLongPressGesture(
                        minimumDuration: 0.38,
                        maximumDistance: 10,
                        pressing: { pressing in
                            store.isShowingOriginal = pressing
                            if pressing { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
                        },
                        perform: {}
                    )
                    .simultaneousGesture(photoPagingGesture)

                PhotoFitView(image: source)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .opacity(store.isShowingOriginal ? 1 : 0)
                    .allowsHitTesting(false)

                topPhotoActions
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(12)

                if store.batchCount > 1 {
                    pageDots
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 12)
                }

                if store.isShowingOriginal {
                    Text("Original")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .hibiscusGlass(tint: .black.opacity(0.32), in: Capsule())
                        .padding(12)
                        .transition(.opacity)
                }
            }
            .offset(x: photoSwipeOffset)
        } else {
            VStack(spacing: 16) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Choose a photo to start")
                    .font(.title3.weight(.semibold))
                Button("Choose Photo") {
                    pendingStyle = nil
                    pickerReplacesSession = true
                    showsPicker = true
                }
                .hibiscusGlassButtonStyle(tint: .white)
                .foregroundStyle(.black)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func editor(width: CGFloat) -> some View {
        let padSize = max(1, (width - 40) / 2)

        return VStack(spacing: 11) {
            HStack(spacing: 10) {
                Button(action: store.undo) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .hibiscusGlass(interactive: true, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!store.canUndo)
                .accessibilityLabel("Undo grade edit")

                Button {
                    styleRailPosition = store.settings.style
                    withAnimation(.snappy(duration: 0.22)) { store.isStyleRailExpanded = true }
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(store.settings.style.tint).frame(width: 8, height: 8)
                        Text(store.settings.style.rawValue)
                        Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 13)
                    .frame(height: 34)
                    .hibiscusGlass(interactive: true, in: Capsule())
                }
                .buttonStyle(.plain)

                Button(action: store.redo) {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .hibiscusGlass(interactive: true, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!store.canRedo)
                .accessibilityLabel("Redo grade edit")
            }
            .frame(height: 36)

            HStack(alignment: .top, spacing: 12) {
                padColumn(kind: .style, size: padSize)
                padColumn(kind: .accent, size: padSize)
            }
            .padding(.horizontal, 14)

            VStack(spacing: 5) {
                HStack {
                    Text(store.activeSurface == .style ? "Style Strength" : "Accent Strength")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Text("\(Int(currentStrength * 100))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: Binding(get: { currentStrength }, set: store.updateStrength), in: 0...1)
                    .tint(store.activeSurface == .style ? store.settings.style.tint : store.settings.accent.color)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .hibiscusGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 14)
            .padding(.top, 6)

        }
        .padding(.top, 26)
        .padding(.bottom, 10)
    }

    private func padColumn(kind: ActiveGradeSurface, size: CGFloat) -> some View {
        return VStack(spacing: 6) {
            GradePad(
                kind: kind,
                style: store.settings.style,
                accent: store.settings.accent,
                point: kind == .style ? store.settings.stylePoint : store.settings.accentPoint,
                onActivate: { store.activate(kind) },
                onChange: kind == .style ? store.updateStylePoint : store.updateAccentPoint
            )
            .frame(width: size, height: size)

            HStack(spacing: 6) {
                Text(kind == .style ? store.settings.style.rawValue : "Accent")
                    .font(.caption.weight(.medium))
                if kind == .accent {
                    Button {
                        showsAccentPicker = true
                    } label: {
                        Circle()
                            .fill(store.settings.accent.color)
                            .frame(width: 22, height: 22)
                            .overlay { Circle().stroke(.primary.opacity(0.24), lineWidth: 0.5) }
                    }
                    .buttonStyle(.plain)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Select Accent color")
                }
            }
            .frame(height: 44)
            .foregroundStyle(.secondary)
        }
        .frame(width: size)
    }

    private var styleRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(GradeStyle.allCases) { style in
                    Button {
                        styleRailPosition = style
                        if store.sourceImage == nil {
                            pendingStyle = style
                            pickerReplacesSession = true
                            showsPicker = true
                        } else {
                            withAnimation(.snappy(duration: 0.22)) { store.selectStyle(style) }
                        }
                    } label: {
                        VStack(spacing: 5) {
                            Group {
                                if let thumbnail = store.thumbnails[style] {
                                    Image(uiImage: thumbnail)
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    LinearGradient(
                                        colors: [style.tint.opacity(0.35), style.tint],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                }
                            }
                            .frame(width: 60, height: 46)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(store.settings.style == style ? Color.primary : Color.primary.opacity(0.10), lineWidth: store.settings.style == style ? 1.5 : 0.5)
                            }
                            .hibiscusGlass(
                                .clear,
                                interactive: true,
                                isEnabled: store.settings.style == style,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )

                            Text(style.rawValue)
                                .font(.caption2.weight(store.settings.style == style ? .bold : .medium))
                                .foregroundStyle(store.settings.style == style ? Color.primary : Color.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .id(style)
                }
            }
            .padding(.horizontal, 14)
            .scrollTargetLayout()
        }
        .scrollPosition(id: $styleRailPosition, anchor: .center)
        .onAppear { styleRailPosition = store.settings.style }
        .frame(maxWidth: .infinity)
        .frame(height: 78)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .hibiscusGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 8)
    }

    private var topPhotoActions: some View {
        Menu {
            exportDestinationMenu(batch: false, shares: false)
            exportDestinationMenu(batch: false, shares: true)

            if store.batchCount > 1 {
                exportDestinationMenu(batch: true, shares: false)
                exportDestinationMenu(batch: true, shares: true)
            }

            Divider()

            if store.batchCount > 1 {
                Button {
                    store.applyStyleToAll()
                } label: {
                    Label("Apply Style to All", systemImage: "rectangle.on.rectangle")
                }
            }

            Button {
                pendingStyle = nil
                pickerReplacesSession = false
                showsPicker = true
            } label: {
                Label("Add Photos", systemImage: "photo.stack")
            }
            .disabled(store.batchCount >= 10)

            Button {
                pendingStyle = store.settings.style
                pickerReplacesSession = true
                showsPicker = true
            } label: {
                Label("Replace All", systemImage: "photo.on.rectangle")
            }

            Button(role: .destructive) {
                store.removePhoto()
            } label: {
                Label(store.batchCount > 1 ? "Remove Current" : "Remove", systemImage: "trash")
            }

            if store.batchCount > 1 {
                Button(role: .destructive) {
                    store.removeAllPhotos()
                } label: {
                    Label("Remove All", systemImage: "trash.slash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .bold))
                .frame(width: 19, height: 19)
        }
        .hibiscusGlassButtonStyle()
        .accessibilityLabel("Photo actions")
        .menuOrder(.fixed)
        .disabled(store.isExporting)
    }

    private func exportDestinationMenu(batch: Bool, shares: Bool) -> some View {
        Menu {
            ForEach(HibiscusExportFormat.allCases) { format in
                Button {
                    requestExport(format: format, batch: batch, shares: shares)
                } label: {
                    Label(format.rawValue, systemImage: format.systemImage)
                }
            }
        } label: {
            let action = shares ? "Share" : "Export"
            Label(
                batch ? "\(action) All" : "\(action) Current",
                systemImage: shares ? "square.and.arrow.up" : "square.and.arrow.down"
            )
        }
    }

    private func requestExport(format: HibiscusExportFormat, batch: Bool, shares: Bool) {
        switch format {
        case .polaroid:
            polaroidRequest = PolaroidExportRequest(batch: batch, shares: shares)
        case .palette:
            paletteRequest = PaletteExportRequest(batch: batch, shares: shares)
        case .photo:
            performExport(format: format, batch: batch, shares: shares)
        }
    }

    private func performExport(
        format: HibiscusExportFormat,
        batch: Bool,
        shares: Bool,
        polaroidComposition: PolaroidComposition = .empty,
        paletteComposition: PaletteComposition = .standard
    ) {
        Task {
            await Task.yield()
            let requestedPhotoIDs = batch
                ? store.photos.map(\.id)
                : store.currentPhoto.map { [$0.id] } ?? []
            let files = await store.exportFiles(
                format: format,
                batch: batch,
                polaroidComposition: polaroidComposition,
                paletteComposition: paletteComposition
            )
            guard !files.isEmpty else {
                store.statusMessage = "Couldn’t render this export."
                return
            }
            let completedPhotoIDs = files.count == requestedPhotoIDs.count
                ? Set(requestedPhotoIDs)
                : []
            if shares {
                pendingSharePhotoIDs = completedPhotoIDs
                shareFiles = files
            } else {
                store.saveFilesToPhotos(files) { success in
                    if success {
                        registerCompletedExport(for: completedPhotoIDs)
                    }
                }
            }
        }
    }

    private func registerCompletedExport(for photoIDs: Set<UUID>) {
        guard !photoIDs.isEmpty else { return }
        let sessionPhotoIDs = Set(store.photos.map(\.id))
        guard !sessionPhotoIDs.isEmpty else { return }
        exportedPhotoIDs.formUnion(photoIDs)
        exportedPhotoIDs.formIntersection(sessionPhotoIDs)
        showsCompletionPrompt = sessionPhotoIDs.isSubset(of: exportedPhotoIDs)
    }

    private var currentStrength: Double {
        store.activeSurface == .style ? store.settings.styleStrength : store.settings.accentStrength
    }

    private var pageDots: some View {
        GeometryReader { proxy in
            HStack(spacing: 6) {
                ForEach(store.photos.indices, id: \.self) { index in
                    Circle()
                        .fill(index == store.currentIndex ? Color.white : Color.white.opacity(0.38))
                        .frame(width: index == store.currentIndex ? 7 : 5, height: index == store.currentIndex ? 7 : 5)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard store.batchCount > 1 else { return }
                        let progress = min(1, max(0, value.location.x / max(1, proxy.size.width)))
                        let index = Int((progress * CGFloat(store.batchCount - 1)).rounded())
                        store.selectPhoto(at: index)
                    }
            )
        }
        .frame(width: max(48, CGFloat(store.batchCount) * 13), height: 28)
        .hibiscusGlass(tint: .black.opacity(0.24), in: Capsule())
        .accessibilityLabel("Photo selector")
        .accessibilityValue("Photo \(store.currentIndex + 1) of \(store.batchCount)")
    }

    private var photoPagingGesture: some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                guard store.batchCount > 1,
                      abs(value.translation.width) > abs(value.translation.height) else { return }
                photoSwipeOffset = value.translation.width * 0.28
            }
            .onEnded { value in
                defer {
                    withAnimation(.snappy(duration: 0.2)) { photoSwipeOffset = 0 }
                }
                guard store.batchCount > 1,
                      abs(value.translation.width) > abs(value.translation.height),
                      abs(value.predictedEndTranslation.width) > 45 else { return }
                let direction = value.predictedEndTranslation.width < 0 ? 1 : -1
                let nextIndex = min(store.batchCount - 1, max(0, store.currentIndex + direction))
                store.selectPhoto(at: nextIndex)
            }
    }

    // The floating tab bar consumes roughly the bottom safe-area height. Keeping
    // this clearance separate from the editor's own 10-point bottom padding
    // matches the Camera panel without letting Strength slip beneath the bar.
    private var navigationClearance: CGFloat { 34 }

    private var photoPickerLimit: Int {
        pickerReplacesSession ? 10 : max(1, 10 - store.batchCount)
    }

    private func photoHeight(for availableHeight: CGFloat) -> CGFloat {
        if store.sourceImage == nil { return availableHeight }
        let editorReserve: CGFloat = 368
        return min(availableHeight * 0.53, max(280, availableHeight - editorReserve), 438)
    }

    private func importPhotos(from items: [PhotosPickerItem]) async {
        var imports: [GradeImportItem] = []
        for item in items.prefix(10) {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = AccentAnalyzer.downsample(data, maxDimension: 4096) ?? UIImage(data: data) else {
                    continue
                }
                let thumbnail = AccentAnalyzer.downsample(data, maxDimension: 384)
                    ?? ImageRenderer.resizedImage(image, maxDimension: 384)
                    ?? image
                imports.append(
                    GradeImportItem(
                        image: image,
                        thumbnail: thumbnail,
                        metadata: PhotoMetadataExtractor.metadata(from: data)
                    )
                )
            } catch {
                continue
            }
        }
        await MainActor.run {
            if imports.isEmpty {
                store.statusMessage = "These photos couldn’t be opened."
            } else {
                store.loadBatch(imports, preferredStyle: pendingStyle, replacing: pickerReplacesSession)
            }
            pendingStyle = nil
            pickerItems = []
        }
    }
}

private struct PolaroidExportRequest: Identifiable {
    let id = UUID()
    let batch: Bool
    let shares: Bool
}

private struct PaletteExportRequest: Identifiable {
    let id = UUID()
    let batch: Bool
    let shares: Bool
}

private struct AccentColorPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var color: Color
    let isAutomatic: Bool
    let canApplyToAll: Bool
    let onUseAutomatic: () -> Void
    let onApplyToAll: () -> Void

    @State private var hue: Double
    @State private var saturation: Double
    @State private var brightness: Double

    init(
        color: Binding<Color>,
        isAutomatic: Bool,
        canApplyToAll: Bool,
        onUseAutomatic: @escaping () -> Void,
        onApplyToAll: @escaping () -> Void
    ) {
        _color = color
        self.isAutomatic = isAutomatic
        self.canApplyToAll = canApplyToAll
        self.onUseAutomatic = onUseAutomatic
        self.onApplyToAll = onApplyToAll

        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var alpha: CGFloat = 0
        UIColor(color.wrappedValue).getHue(
            &hue,
            saturation: &saturation,
            brightness: &brightness,
            alpha: &alpha
        )
        _hue = State(initialValue: Double(hue))
        _saturation = State(initialValue: Double(max(0.35, saturation)))
        _brightness = State(initialValue: Double(max(0.45, brightness)))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Circle()
                    .fill(color)
                    .frame(width: 54, height: 54)
                    .overlay { Circle().stroke(.primary.opacity(0.18), lineWidth: 0.5) }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Color")
                        .font(.subheadline.weight(.semibold))
                    AccentHueStrip(hue: $hue) {
                        saturation = max(0.58, saturation)
                        brightness = max(0.62, brightness)
                        updateColor()
                    }
                    .frame(height: 38)

                    Text("Saturation")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $saturation, in: 0...1)
                        .onChange(of: saturation) { _, _ in updateColor() }

                    Text("Lightness")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $brightness, in: 0.25...1)
                        .onChange(of: brightness) { _, _ in updateColor() }
                }
                .padding(16)
                .hibiscusGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                Button {
                    onUseAutomatic()
                    dismiss()
                } label: {
                    HStack {
                        Label("Automatic Accent", systemImage: "wand.and.stars")
                        Spacer()
                        if isAutomatic { Image(systemName: "checkmark") }
                    }
                    .frame(maxWidth: .infinity)
                }
                .hibiscusGlassButtonStyle()

                if canApplyToAll {
                    Button("Apply Custom Accent to All", action: onApplyToAll)
                        .hibiscusGlassButtonStyle()
                }

                Spacer()
            }
            .padding(18)
            .navigationTitle("Accent Color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func updateColor() {
        color = Color(
            uiColor: UIColor(
                hue: hue,
                saturation: saturation,
                brightness: brightness,
                alpha: 1
            )
        )
    }
}

private struct AccentHueStrip: View {
    @Binding var hue: Double
    let onChange: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                LinearGradient(
                    colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .clipShape(Capsule())

                Circle()
                    .fill(.white)
                    .frame(width: 24, height: 24)
                    .overlay { Circle().stroke(.black.opacity(0.26), lineWidth: 1) }
                    .shadow(color: .black.opacity(0.34), radius: 3, y: 1)
                    .offset(x: min(1, max(0, hue)) * max(0, proxy.size.width - 24))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        hue = min(1, max(0, value.location.x / max(1, proxy.size.width)))
                        onChange()
                    }
            )
        }
    }
}

private struct ComposerPageDots: View {
    let count: Int
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                Button {
                    guard selection != index else { return }
                    selection = index
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    Circle()
                        .fill(index == selection ? Color.white : Color.white.opacity(0.38))
                        .frame(width: index == selection ? 7 : 5, height: index == selection ? 7 : 5)
                        .frame(width: 22, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Photo \(index + 1)")
                .accessibilityValue(index == selection ? "Selected" : "Not selected")
            }
        }
        .frame(minWidth: 52)
        .frame(height: 28)
        .hibiscusGlass(in: Capsule())
        .animation(.snappy(duration: 0.18), value: selection)
        .frame(maxWidth: 380)
        .contentShape(Rectangle())
        .modifier(ComposerPageSwipeModifier(count: count, selection: $selection))
        .accessibilityLabel("Export photo selector")
        .accessibilityValue("Photo \(selection + 1) of \(count)")
    }
}

private struct ComposerPageSwipeModifier: ViewModifier {
    let count: Int
    @Binding var selection: Int
    var isEnabled = true

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.simultaneousGesture(pagingGesture)
        } else {
            content
        }
    }

    private var pagingGesture: some Gesture {
        DragGesture(minimumDistance: 18)
            .onEnded { value in
                guard count > 1,
                      abs(value.translation.width) > abs(value.translation.height),
                      abs(value.predictedEndTranslation.width) > 40 else { return }
                let direction = value.predictedEndTranslation.width < 0 ? 1 : -1
                let nextSelection = min(count - 1, max(0, selection + direction))
                guard nextSelection != selection else { return }
                selection = nextSelection
                UISelectionFeedbackGenerator().selectionChanged()
            }
    }
}

private struct PaletteComposerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let photos: [GradeSessionPhoto]
    let primaryActionShares: Bool
    let onComplete: (PaletteComposition) -> Void

    @State private var currentIndex = 0
    @State private var previewImage: UIImage?
    @State private var candidates: [AccentColor] = []
    @State private var selectedIndices: Set<Int> = []
    @State private var showsHexCodes = false
    @State private var selectionMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                GeometryReader { proxy in
                    let cardSize = fittedCardSize(in: proxy.size)
                    paletteCard(size: cardSize)
                        .frame(width: cardSize.width, height: cardSize.height)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .modifier(ComposerPageSwipeModifier(count: photos.count, selection: $currentIndex))

                if photos.count > 1 {
                    ComposerPageDots(count: photos.count, selection: $currentIndex)
                }

                VStack(spacing: 11) {
                    HStack {
                        Text("Choose 1–5 colors")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(selectedIndices.count) selected")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(candidates.enumerated()), id: \.offset) { index, color in
                                Button {
                                    toggleColor(at: index)
                                } label: {
                                    Circle()
                                        .fill(color.color)
                                        .frame(width: 42, height: 42)
                                        .overlay {
                                            Circle().stroke(.primary.opacity(0.20), lineWidth: 0.5)
                                            if selectedIndices.contains(index) {
                                                Image(systemName: "checkmark")
                                                    .font(.caption.weight(.bold))
                                                    .foregroundStyle(contrastingColor(for: color))
                                            }
                                        }
                                        .frame(width: 48, height: 48)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Color \(index + 1)")
                                .accessibilityValue(selectedIndices.contains(index) ? "Selected" : "Not selected")
                            }
                        }
                        .padding(.horizontal, 1)
                    }

                    Button {
                        showsHexCodes.toggle()
                    } label: {
                        HStack {
                            Text("Show hex codes")
                            Spacer()
                            Image(systemName: showsHexCodes ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(showsHexCodes ? Color.hibiscusAccent : Color.secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    if let selectionMessage {
                        Text(selectionMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if exportCount > 1 {
                        Text("Each photo keeps its own extracted colors.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(14)
                .hibiscusGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .frame(maxWidth: 420)

                Button {
                    let composition = PaletteComposition(
                        selectedIndices: selectedIndices.sorted(),
                        showsHexCodes: showsHexCodes
                    )
                    onComplete(composition)
                    dismiss()
                } label: {
                    Label(
                        primaryActionShares ? "Share" : "Export to Photos",
                        systemImage: primaryActionShares ? "square.and.arrow.up" : "square.and.arrow.down"
                    )
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: 420)
                .hibiscusGlassButtonStyle(tint: .white)
                .foregroundStyle(.black)
                .disabled(selectedIndices.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .navigationTitle("Palette")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .task(id: currentPhoto?.id) {
            previewImage = nil
            guard let photoID = currentPhoto?.id, let sourceImage else { return }
            let settings = currentSettings
            let result = await Task.detached(priority: .userInitiated) {
                autoreleasepool { () -> (UIImage?, [AccentColor]) in
                    let rendered = ImageRenderer.gradeImage(sourceImage, settings: settings, maxDimension: 1800)
                    let analysisImage = rendered ?? sourceImage
                    return (rendered, PaletteAnalyzer.colors(from: analysisImage, count: 5))
                }
            }.value
            guard currentPhoto?.id == photoID else { return }
            previewImage = result.0
            candidates = result.1
            let availableSelection = selectedIndices.filter { $0 < result.1.count }
            selectedIndices = availableSelection.isEmpty
                ? Set(0..<min(5, result.1.count))
                : Set(availableSelection)
        }
    }

    private var currentPhoto: GradeSessionPhoto? {
        photos.indices.contains(currentIndex) ? photos[currentIndex] : nil
    }

    private var sourceImage: UIImage? { currentPhoto?.image }
    private var currentSettings: GradeSettings { currentPhoto?.settings ?? GradeSettings() }
    private var exportCount: Int { photos.count }

    private func paletteCard(size: CGSize) -> some View {
        let image = previewImage ?? sourceImage
        let photoHeight = size.width * photoHeightRatio(for: image)
        let colorHeight = size.width * (150 / 1800)
        let brandHeight = size.width * (180 / 1800)
        let selectedColors = selectedIndices.sorted().compactMap { index in
            candidates.indices.contains(index) ? candidates[index] : nil
        }
        let hexTextColor = Color(uiColor: HibiscusExportRenderer.paletteHexTextColor(for: selectedColors))

        return VStack(spacing: 0) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Color.secondary.opacity(0.16)
                }
            }
            .frame(width: size.width, height: photoHeight)

            HStack(spacing: 0) {
                ForEach(Array(selectedColors.enumerated()), id: \.offset) { _, color in
                    ZStack {
                        color.color
                        if showsHexCodes {
                            Text(hexString(for: color))
                                .font(.system(size: max(7, size.width * 0.016), weight: .semibold, design: .monospaced))
                                .foregroundStyle(hexTextColor)
                                .minimumScaleFactor(0.5)
                                .lineLimit(1)
                                .padding(.horizontal, 2)
                        }
                    }
                }
            }
            .frame(height: colorHeight)

            VStack(spacing: size.width * 0.006) {
                HibiscusAppIcon()
                    .frame(width: size.width * 0.042, height: size.width * 0.042)
                Text("Hibiscus")
                    .font(.system(size: size.width * 0.019, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.66))
            }
            .frame(width: size.width, height: brandHeight)
        }
        .frame(width: size.width, height: size.height)
        .background(Color(red: 0.965, green: 0.958, blue: 0.938))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(.black.opacity(0.08), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.20), radius: 12, y: 6)
    }

    private func fittedCardSize(in available: CGSize) -> CGSize {
        let ratio = photoHeightRatio(for: previewImage ?? sourceImage) + (330 / 1800)
        let aspect = 1 / ratio
        let width = min(available.width, available.height * aspect)
        return CGSize(width: width, height: width / aspect)
    }

    private func photoHeightRatio(for image: UIImage?) -> CGFloat {
        guard let image else { return 0.75 }
        let ratio = image.size.width / max(1, image.size.height)
        return max(0.55, min(1.8, 1 / max(0.01, ratio)))
    }

    private func toggleColor(at index: Int) {
        if selectedIndices.contains(index) {
            guard selectedIndices.count > 1 else {
                selectionMessage = "Keep at least one color."
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                return
            }
            selectedIndices.remove(index)
        } else {
            guard selectedIndices.count < 5 else {
                selectionMessage = "A Palette can contain up to five colors."
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                return
            }
            selectedIndices.insert(index)
        }
        selectionMessage = nil
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func hexString(for color: AccentColor) -> String {
        String(
            format: "#%02X%02X%02X",
            Int(min(1, max(0, color.red)) * 255),
            Int(min(1, max(0, color.green)) * 255),
            Int(min(1, max(0, color.blue)) * 255)
        )
    }

    private func contrastingColor(for color: AccentColor) -> Color {
        let luminance = 0.2126 * color.red + 0.7152 * color.green + 0.0722 * color.blue
        return luminance > 0.24 ? .black.opacity(0.82) : .white.opacity(0.92)
    }
}

private struct PolaroidComposerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let photos: [GradeSessionPhoto]
    let primaryActionShares: Bool
    let showsMetadata: Bool
    let showsMark: Bool
    let includesLocation: Bool
    let onComplete: (PolaroidComposition) -> Void

    @State private var currentIndex = 0
    @State private var previewImage: UIImage?
    @State private var drawing = PKDrawing()
    @State private var drawingCanvasSize: CGSize = .zero
    @State private var mode: PolaroidComposerMode = .crop
    @State private var cropScale = 1.0
    @State private var cropScaleStart = 1.0
    @State private var cropOffset = CGPoint.zero
    @State private var cropOffsetStart = CGPoint.zero
    @State private var hasPrinted = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                GeometryReader { proxy in
                    let cardSize = fittedCardSize(in: proxy.size)
                    polaroidCard(size: cardSize)
                        .frame(width: cardSize.width, height: cardSize.height)
                        .offset(y: hasPrinted ? 0 : -cardSize.height * 0.86)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    .clipped()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if photos.count > 1 {
                    ComposerPageDots(count: photos.count, selection: $currentIndex)
                }

                Text(composerHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)

                Button {
                    let composition = PolaroidComposition(
                        drawingData: drawing.dataRepresentation(),
                        drawingCanvasSize: drawingCanvasSize,
                        cropScale: cropScale,
                        cropOffset: cropOffset,
                        showsMetadata: showsMetadata,
                        showsMark: showsMark,
                        includesLocation: includesLocation
                    )
                    onComplete(composition)
                    dismiss()
                } label: {
                    Label(
                        primaryActionShares ? "Share" : "Export to Photos",
                        systemImage: primaryActionShares ? "square.and.arrow.up" : "square.and.arrow.down"
                    )
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: 380)
                .hibiscusGlassButtonStyle(tint: .white)
                .foregroundStyle(.black)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .navigationTitle("Polaroid")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        mode = .crop
                    } label: {
                        Image(systemName: "crop")
                    }
                    .tint(mode == .crop ? .primary : .secondary)
                    .accessibilityLabel("Adjust photo crop")

                    Button {
                        mode = mode == .draw ? .crop : .draw
                    } label: {
                        Image(systemName: mode == .draw ? "checkmark" : "pencil.tip")
                    }
                    .tint(mode == .draw ? .primary : .secondary)
                    .accessibilityLabel(mode == .draw ? "Finish drawing" : "Draw with PencilKit")

                    if mode == .crop, cropScale != 1 || cropOffset != .zero {
                        Button {
                            withAnimation(.snappy(duration: 0.2)) {
                                cropScale = 1
                                cropScaleStart = 1
                                cropOffset = .zero
                                cropOffsetStart = .zero
                            }
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .accessibilityLabel("Reset crop")
                    }
                }
            }
        }
        .presentationDetents([.large])
        .task {
            guard !hasPrinted else { return }
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.spring(response: 0.75, dampingFraction: 0.88)) {
                hasPrinted = true
            }
        }
        .task(id: currentPhoto?.id) {
            previewImage = nil
            guard let photoID = currentPhoto?.id, let sourceImage else { return }
            let settings = currentSettings
            let rendered = await Task.detached(priority: .userInitiated) {
                autoreleasepool {
                    ImageRenderer.gradeImage(sourceImage, settings: settings, maxDimension: 1800)
                }
            }.value
            guard currentPhoto?.id == photoID else { return }
            previewImage = rendered
        }
    }

    private var currentPhoto: GradeSessionPhoto? {
        photos.indices.contains(currentIndex) ? photos[currentIndex] : nil
    }

    private var sourceImage: UIImage? { currentPhoto?.image }
    private var currentSettings: GradeSettings { currentPhoto?.settings ?? GradeSettings() }
    private var settings: GradeSettings { currentSettings }
    private var metadata: PhotoMetadata { currentPhoto?.metadata ?? PhotoMetadata() }
    private var exportCount: Int { photos.count }

    private func polaroidCard(size: CGSize) -> some View {
        let inset = size.width * 0.05
        let photoSize = size.width * 0.9
        return ZStack(alignment: .topLeading) {
            Color(red: 0.955, green: 0.947, blue: 0.918)

            Group {
                if let image = previewImage ?? sourceImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: photoSize, height: photoSize)
                        .scaleEffect(cropScale)
                        .offset(x: cropOffset.x * photoSize, y: cropOffset.y * photoSize)
                } else {
                    Color.secondary.opacity(0.16)
                }
            }
            .frame(width: photoSize, height: photoSize)
            .clipped()
            .offset(x: inset, y: inset)
            .contentShape(Rectangle())
            .allowsHitTesting(mode == .crop)
            .gesture(cropDragGesture(photoSize: photoSize))
            .simultaneousGesture(cropMagnificationGesture)

            if showsMetadata {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(polaroidMetadataLines, id: \.self) { line in
                        Text(line)
                    }
                }
                .font(.system(size: max(6, size.width * 0.012), weight: .medium, design: .monospaced))
                .foregroundStyle(.black.opacity(0.58))
                .frame(width: size.width * 0.61, alignment: .leading)
                .position(x: size.width * 0.36, y: size.height * 0.855)
                .allowsHitTesting(false)
            }

            if showsMark {
                VStack(spacing: size.width * 0.018) {
                    HibiscusAppIcon()
                        .frame(width: size.width * 0.073, height: size.width * 0.073)
                    Text("Hibiscus")
                        .font(.system(size: size.width * 0.027, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.66))
                }
                .position(x: showsMetadata ? size.width * 0.86 : size.width / 2, y: size.height * 0.865)
                .allowsHitTesting(false)
            }

            PencilCanvasView(drawing: $drawing, isActive: mode == .draw)
                .onAppear { drawingCanvasSize = size }
                .onChange(of: size) { _, newSize in drawingCanvasSize = newSize }
                .allowsHitTesting(mode == .draw)

            if photos.count > 1, mode != .draw {
                let pagingAreaTop = inset + photoSize
                Color.clear
                    .frame(width: size.width, height: max(1, size.height - pagingAreaTop))
                    .contentShape(Rectangle())
                    .offset(y: pagingAreaTop)
                    .modifier(ComposerPageSwipeModifier(count: photos.count, selection: $currentIndex))
                    .accessibilityLabel("Swipe between Polaroid photos")
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(.black.opacity(0.08), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.22), radius: 14, y: 7)
    }

    private func fittedCardSize(in available: CGSize) -> CGSize {
        let aspect = 1800.0 / 2320.0
        let width = min(available.width, available.height * aspect)
        return CGSize(width: width, height: width / aspect)
    }

    private func cropDragGesture(photoSize: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let proposed = CGPoint(
                    x: cropOffsetStart.x + value.translation.width / max(1, photoSize),
                    y: cropOffsetStart.y + value.translation.height / max(1, photoSize)
                )
                cropOffset = clampedCropOffset(proposed, scale: cropScale)
            }
            .onEnded { _ in cropOffsetStart = cropOffset }
    }

    private var cropMagnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                cropScale = min(3, max(1, cropScaleStart * value))
                cropOffset = clampedCropOffset(cropOffset, scale: cropScale)
            }
            .onEnded { _ in
                cropScaleStart = cropScale
                cropOffsetStart = cropOffset
            }
    }

    private func clampedCropOffset(_ offset: CGPoint, scale: Double) -> CGPoint {
        guard let image = previewImage ?? sourceImage else { return .zero }
        let ratio = image.size.width / max(1, image.size.height)
        let baseWidth = max(1, ratio)
        let baseHeight = max(1, 1 / ratio)
        let maxX = max(0, (baseWidth * scale - 1) / 2)
        let maxY = max(0, (baseHeight * scale - 1) / 2)
        return CGPoint(
            x: min(maxX, max(-maxX, offset.x)),
            y: min(maxY, max(-maxY, offset.y))
        )
    }

    private var composerHint: String {
        switch mode {
        case .crop:
            "Drag and pinch the photo to choose its crop."
        case .draw:
            exportCount > 1
                ? "Draw anywhere. The same drawing is added to all \(exportCount) cards."
                : "Use the system PencilKit tools to draw anywhere on the card."
        }
    }

    private var polaroidMetadataLines: [String] {
        var lines: [String] = []
        if let date = metadata.date {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "MMM d yyyy · HH:mm"
            lines.append(formatter.string(from: date).uppercased())
        }
        if includesLocation, let location = metadata.location { lines.append(location.uppercased()) }
        let camera = metadata.cameraCharacter.map { "\($0.glyph) \($0.name.uppercased()) · " } ?? ""
        lines.append("\(camera)\(settings.style.rawValue.uppercased())")
        return Array(lines.prefix(3))
    }

}

private enum PolaroidComposerMode {
    case crop
    case draw
}

private struct PencilCanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    let isActive: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(drawing: $drawing)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .anyInput
        canvas.tool = PKInkingTool(.pen, color: .black, width: 4)
        canvas.delegate = context.coordinator
        canvas.alwaysBounceHorizontal = false
        canvas.alwaysBounceVertical = false
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        if canvas.drawing != drawing { canvas.drawing = drawing }
        canvas.isUserInteractionEnabled = isActive
        context.coordinator.updateToolPicker(for: canvas, isActive: isActive)
    }

    static func dismantleUIView(_ canvas: PKCanvasView, coordinator: Coordinator) {
        coordinator.updateToolPicker(for: canvas, isActive: false)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        private var drawing: Binding<PKDrawing>
        private let toolPicker = PKToolPicker()
        private var isToolPickerActive = false

        init(drawing: Binding<PKDrawing>) {
            self.drawing = drawing
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawing.wrappedValue = canvasView.drawing
        }

        func updateToolPicker(for canvas: PKCanvasView, isActive: Bool) {
            guard isActive != isToolPickerActive else { return }
            isToolPickerActive = isActive
            if isActive {
                canvas.tool = PKInkingTool(.pen, color: .black, width: 4)
                toolPicker.addObserver(canvas)
                toolPicker.setVisible(true, forFirstResponder: canvas)
                DispatchQueue.main.async { canvas.becomeFirstResponder() }
            } else {
                toolPicker.setVisible(false, forFirstResponder: canvas)
                toolPicker.removeObserver(canvas)
                canvas.resignFirstResponder()
            }
        }
    }
}

private struct HibiscusAppIcon: View {
    var body: some View {
        Group {
            if let icon = HibiscusBrand.appIcon() {
                Image(uiImage: icon)
                    .resizable()
                    .scaledToFit()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityHidden(true)
    }
}
