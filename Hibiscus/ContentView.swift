import SwiftUI

struct ContentView: View {
    @State private var destination: AppDestination = .camera
    @StateObject private var preferences: AppPreferences
    @StateObject private var gradeStore: GradeStore
#if DEBUG && targetEnvironment(simulator)
    @StateObject private var simulatorDemoMode: SimulatorDemoMode
#endif

    init() {
        let preferences = AppPreferences()
        _preferences = StateObject(wrappedValue: preferences)
        _gradeStore = StateObject(wrappedValue: GradeStore(preferences: preferences))
#if DEBUG && targetEnvironment(simulator)
        _simulatorDemoMode = StateObject(wrappedValue: SimulatorDemoMode())
#endif
    }

    @ViewBuilder
    var body: some View {
#if DEBUG && targetEnvironment(simulator)
        appTabs
            .environmentObject(simulatorDemoMode)
            .task(id: simulatorDemoMode.gradeImportRequest?.id) {
                guard let request = simulatorDemoMode.gradeImportRequest else { return }
                simulatorDemoMode.beginPreparingGradeImport(request.id)
                let imports = await Task.detached(priority: .userInitiated) {
                    request.photos.compactMap { $0.loadGradeImport() }
                }.value
                if imports.isEmpty {
                    gradeStore.statusMessage = L10n.string("These photos couldn’t be opened.")
                } else {
                    gradeStore.loadBatch(imports, replacing: true)
                    destination = .grade
                }
                simulatorDemoMode.finishGradeImport(request.id)
            }
#else
        appTabs
#endif
    }

    private var appTabs: some View {
        TabView(selection: $destination) {
            CameraView(preferences: preferences, isActive: destination == .camera) { image, character, date in
                gradeStore.load(
                    image,
                    metadata: PhotoMetadata(date: date, location: nil, cameraCharacter: character)
                )
                destination = .grade
            }
            .tag(AppDestination.camera)
            .tabItem {
                Label {
                    Text(LocalizedStringKey(AppDestination.camera.rawValue))
                } icon: {
                    Image(systemName: AppDestination.camera.symbol)
                }
            }

            GradeView(store: gradeStore, preferences: preferences, isActive: destination == .grade)
                .tag(AppDestination.grade)
                .tabItem {
                    Label {
                        Text(LocalizedStringKey(AppDestination.grade.rawValue))
                    } icon: {
                        Image(systemName: AppDestination.grade.symbol)
                    }
                }

            SettingsView(preferences: preferences)
                .tag(AppDestination.settings)
                .tabItem {
                    Label {
                        Text(LocalizedStringKey(AppDestination.settings.rawValue))
                    } icon: {
                        Image(systemName: AppDestination.settings.symbol)
                    }
                }
        }
        .tint(.hibiscusAccent)
        .preferredColorScheme(.dark)
    }
}
