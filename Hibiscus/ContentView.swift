import SwiftUI

struct ContentView: View {
    @State private var destination: AppDestination = .camera
    @StateObject private var preferences: AppPreferences
    @StateObject private var gradeStore: GradeStore

    init() {
        let preferences = AppPreferences()
        _preferences = StateObject(wrappedValue: preferences)
        _gradeStore = StateObject(wrappedValue: GradeStore(preferences: preferences))
    }

    var body: some View {
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
        .tint(.white)
        .preferredColorScheme(.dark)
    }
}
