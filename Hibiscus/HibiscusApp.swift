//
//  HibiscusApp.swift
//  Hibiscus
//
//  Created by Zhengyang Hu on 8/28/26.
//

import SwiftUI

@main
struct HibiscusApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var languageManager = LanguageManager.shared
    @StateObject private var remoteContent = RemoteContentManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(languageManager)
                .environmentObject(remoteContent)
                .environment(\.locale, languageManager.locale)
                .task {
                    remoteContent.refreshInBackground()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        languageManager.refreshSystemLanguage()
                        remoteContent.refreshInBackground()
                    }
                }
        }
    }
}
