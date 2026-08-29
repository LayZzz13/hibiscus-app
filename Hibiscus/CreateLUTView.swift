import PhotosUI
import SwiftUI
import UIKit

struct CreateLUTView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pickerItem: PhotosPickerItem?
    @State private var basePicture: UIImage?
    @State private var settings = GradeSettings()
    @State private var automaticAccent = AccentColor.warmGray
    @State private var isAccentCustomized = false
    @State private var showsAccentPicker = false
    @State private var isStyleRailExpanded = true
    @State private var styleRailPosition: GradeStyle? = .pure
    @State private var styleAdjustments: [GradeStyle: LUTStyleAdjustment] = [:]
    @State private var thumbnails: [GradeStyle: UIImage] = [:]
    @State private var thumbnailGeneration = UUID()
    @State private var pictureLoadGeneration = UUID()
    @State private var isLoadingPicture = false
    @State private var isAnalyzingAccent = false
    @State private var isCreating = false
    @State private var lutName = "Hibiscus Pure"
    @State private var shareRequest: LUTShareRequest?
    @State private var temporaryFileURL: URL?
    @State private var errorMessage: String?
    @State private var showsExitConfirmation = false
    @State private var previewRenderer = GradePreviewRenderer()

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                basePictureArea

                if basePicture != nil {
                    styleSection
                    padsSection
                    strengthControls
                    lutDetails
                } else {
                    Text("Select a Base Picture to begin.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }

                createButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .background(Color(white: 0.075).ignoresSafeArea())
        .navigationTitle("Create LUT")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    if basePicture == nil {
                        dismiss()
                    } else {
                        showsExitConfirmation = true
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                }
                .accessibilityLabel("Back")
            }
        }
        .onChange(of: pickerItem) { _, newItem in
            guard let newItem else { return }
            Task { await loadBasePicture(from: newItem) }
        }
        .onChange(of: settings) { _, newSettings in
            previewRenderer.update(settings: newSettings)
        }
        .sheet(isPresented: $showsAccentPicker) {
            AccentColorPickerSheet(
                color: Binding(
                    get: { settings.accent.color },
                    set: setCustomAccent
                ),
                isAutomatic: !isAccentCustomized,
                onUseAutomatic: useAutomaticAccent
            )
        }
        .sheet(item: $shareRequest, onDismiss: cleanTemporaryFile) { request in
            ShareSheet(items: [request.url]) { _ in }
                .ignoresSafeArea()
        }
        .alert("Couldn’t Create LUT", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Couldn’t create the LUT.")
        }
        .alert("Keep LUT Configuration?", isPresented: $showsExitConfirmation) {
            Button("Keep Configuration", role: .cancel) {}
            Button("Done", role: .destructive) { dismiss() }
        } message: {
            Text("Your Base Picture and LUT configuration are temporary. Keep editing or finish and discard them.")
        }
    }

    private var basePictureArea: some View {
        ZStack {
            if basePicture != nil {
                GradeMetalPreview(renderer: previewRenderer, isActive: true)
                    .background(Color(uiColor: .secondarySystemBackground))

                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Replace Base Picture", systemImage: "photo.badge.arrow.down")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .hibiscusGlass(interactive: true, in: Capsule())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(12)
            } else {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 36, weight: .light))
                        Text("Add Base Picture")
                            .font(.headline)
                    }
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if isLoadingPicture {
                ProgressView("Loading Photo…")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .hibiscusGlass(in: Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 250)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .hibiscusGlass(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Base Picture")
    }

    private var styleSection: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Style")
                    .font(.headline)
                Spacer()
                Button {
                    styleRailPosition = settings.style
                    withAnimation(.snappy(duration: 0.22)) {
                        isStyleRailExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(settings.style.tint)
                            .frame(width: 8, height: 8)
                        Text(settings.style.rawValue)
                        Image(systemName: isStyleRailExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.bold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 13)
                    .frame(height: 34)
                    .hibiscusGlass(interactive: true, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            if isStyleRailExpanded {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(GradeStyle.allCases) { style in
                            Button { selectStyle(style) } label: {
                                VStack(spacing: 5) {
                                    Group {
                                        if let thumbnail = thumbnails[style] {
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
                                    .frame(width: 62, height: 48)
                                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .stroke(
                                                settings.style == style ? Color.primary : Color.primary.opacity(0.10),
                                                lineWidth: settings.style == style ? 1.5 : 0.5
                                            )
                                    }

                                    Text(style.rawValue)
                                        .font(.caption2.weight(settings.style == style ? .bold : .medium))
                                        .foregroundStyle(settings.style == style ? Color.primary : Color.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .id(style)
                        }
                    }
                    .padding(.horizontal, 12)
                    .scrollTargetLayout()
                }
                .scrollPosition(id: $styleRailPosition, anchor: .center)
                .frame(height: 82)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .hibiscusGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .animation(.snappy(duration: 0.22), value: isStyleRailExpanded)
    }

    private var padsSection: some View {
        HStack(alignment: .top, spacing: 12) {
            padColumn(kind: .style)
            padColumn(kind: .accent)
        }
    }

    private func padColumn(kind: ActiveGradeSurface) -> some View {
        VStack(spacing: 7) {
            GradePad(
                kind: kind,
                style: settings.style,
                accent: settings.accent,
                point: kind == .style ? settings.stylePoint : settings.accentPoint,
                onActivate: {},
                onChange: { point in
                    if kind == .style {
                        settings.stylePoint = point
                        styleAdjustments[settings.style] = LUTStyleAdjustment(
                            point: point,
                            strength: settings.styleStrength
                        )
                    } else {
                        settings.accentPoint = point
                    }
                }
            )

            if kind == .style {
                Text(settings.style.rawValue)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(height: 44)
            } else {
                Button { showsAccentPicker = true } label: {
                    HStack(spacing: 6) {
                        Text("Accent")
                        Circle()
                            .fill(settings.accent.color)
                            .frame(width: 12, height: 12)
                            .overlay { Circle().stroke(.primary.opacity(0.24), lineWidth: 0.5) }
                        if isAnalyzingAccent {
                            ProgressView().controlSize(.mini)
                        } else if !isAccentCustomized {
                            Image(systemName: "wand.and.stars")
                                .font(.caption2)
                        }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Select Accent color")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var strengthControls: some View {
        VStack(spacing: 12) {
            strengthControl(
                title: "Style Strength",
                value: Binding(
                    get: { settings.styleStrength },
                    set: { value in
                        settings.styleStrength = value
                        styleAdjustments[settings.style] = LUTStyleAdjustment(
                            point: settings.stylePoint,
                            strength: value
                        )
                    }
                ),
                tint: settings.style.tint
            )
            strengthControl(
                title: "Accent Strength",
                value: Binding(
                    get: { settings.accentStrength },
                    set: { settings.accentStrength = $0 }
                ),
                tint: settings.accent.color
            )
        }
    }

    private func strengthControl(
        title: LocalizedStringKey,
        value: Binding<Double>,
        tint: Color
    ) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(Int(value.wrappedValue * 100))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: 0...1)
                .tint(tint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .hibiscusGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var lutDetails: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("LUT Name")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(verbatim: "33 × 33 × 33 .cube")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            TextField("LUT Name", text: $lutName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .frame(height: 44)
                .hibiscusGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(.top, 2)
    }

    private var createButton: some View {
        Button {
            createLUT()
        } label: {
            HStack(spacing: 8) {
                if isCreating {
                    ProgressView()
                        .tint(.black)
                } else {
                    Image(systemName: "cube.transparent")
                }
                Text("Create LUT")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
        }
        .hibiscusGlassButtonStyle(tint: .white)
        .foregroundStyle(.black)
        .disabled(basePicture == nil || lutName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
    }

    @MainActor
    private func loadBasePicture(from item: PhotosPickerItem) async {
        let generation = UUID()
        pictureLoadGeneration = generation
        isLoadingPicture = true
        isAnalyzingAccent = false
        defer {
            if pictureLoadGeneration == generation { isLoadingPicture = false }
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw LUTPictureError.unavailable
            }
            let image = await Task.detached(priority: .userInitiated) {
                AccentAnalyzer.downsample(data, maxDimension: 2400)
            }.value
            guard pictureLoadGeneration == generation, let image else { return }

            basePicture = image
            previewRenderer.load(image, settings: settings)
            generateThumbnails(from: image)
            isLoadingPicture = false
            isAnalyzingAccent = true
            let accent = await Task.detached(priority: .userInitiated) {
                AccentAnalyzer.analyze(image)
            }.value
            guard pictureLoadGeneration == generation else { return }
            automaticAccent = accent
            if !isAccentCustomized { settings.accent = accent }
            isAnalyzingAccent = false
        } catch {
            guard pictureLoadGeneration == generation else { return }
            isAnalyzingAccent = false
            errorMessage = L10n.string("Couldn’t load the Base Picture.")
        }
    }

    private func generateThumbnails(from image: UIImage) {
        let generation = UUID()
        thumbnailGeneration = generation
        DispatchQueue.global(qos: .utility).async {
            let source = autoreleasepool { ImageRenderer.resizedImage(image, maxDimension: 320) } ?? image
            var result: [GradeStyle: UIImage] = [:]
            for style in GradeStyle.allCases {
                if let thumbnail = autoreleasepool(invoking: { ImageRenderer.styleThumbnail(source, style: style) }) {
                    result[style] = thumbnail
                }
            }
            DispatchQueue.main.async {
                guard thumbnailGeneration == generation else { return }
                thumbnails = result
            }
        }
    }

    private func selectStyle(_ style: GradeStyle) {
        guard style != settings.style else {
            withAnimation(.snappy(duration: 0.22)) { isStyleRailExpanded = false }
            return
        }
        let previousStyle = settings.style
        styleAdjustments[previousStyle] = LUTStyleAdjustment(
            point: settings.stylePoint,
            strength: settings.styleStrength
        )
        let adjustment = styleAdjustments[style] ?? .default
        settings.style = style
        settings.stylePoint = adjustment.point
        settings.styleStrength = adjustment.strength
        styleRailPosition = style
        if lutName == defaultLUTName(for: previousStyle) {
            lutName = defaultLUTName(for: style)
        }
        withAnimation(.snappy(duration: 0.22)) { isStyleRailExpanded = false }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func setCustomAccent(_ color: Color) {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return }
        settings.accent = AccentColor(red: Double(red), green: Double(green), blue: Double(blue))
        isAccentCustomized = true
    }

    private func useAutomaticAccent() {
        settings.accent = automaticAccent
        isAccentCustomized = false
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func createLUT() {
        guard basePicture != nil, !isCreating else { return }
        isCreating = true
        errorMessage = nil
        let exportSettings = settings
        let exportName = lutName
        Task {
            do {
                let url = try await Task.detached(priority: .userInitiated) {
                    try CubeLUTExporter.createFile(settings: exportSettings, name: exportName)
                }.value
                temporaryFileURL = url
                shareRequest = LUTShareRequest(url: url)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                errorMessage = L10n.string("Couldn’t create the LUT.")
            }
            isCreating = false
        }
    }

    private func cleanTemporaryFile() {
        guard let url = temporaryFileURL else { return }
        CubeLUTExporter.removeTemporaryFile(at: url)
        temporaryFileURL = nil
    }

    private func defaultLUTName(for style: GradeStyle) -> String {
        "Hibiscus \(style.rawValue)"
    }
}

nonisolated private struct LUTStyleAdjustment: Sendable {
    var point: CGPoint
    var strength: Double

    static let `default` = LUTStyleAdjustment(point: CGPoint(x: 0.5, y: 0.5), strength: 0.78)
}

private struct LUTShareRequest: Identifiable {
    let id = UUID()
    let url: URL
}

nonisolated private enum LUTPictureError: Error {
    case unavailable
}
