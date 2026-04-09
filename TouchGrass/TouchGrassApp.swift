//
//  TouchGrassApp.swift
//  TouchGrass
//
//  Created by Simon Fossett on 3/15/26.
//

import SwiftUI
import FirebaseCore
import FirebaseMessaging
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()
        NotificationManager.shared.setup(application: application)
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NotificationManager.shared.setAPNSToken(deviceToken)
    }
}

@main
struct TouchGrassApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                if showSplash {
                    SplashView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .task {
                // Show for at least 2 seconds so Firebase auth state
                // has time to resolve before the splash disappears.
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                withAnimation(.easeOut(duration: 0.5)) {
                    showSplash = false
                }
            }
        }
    }
}
