//
//  NotificationManager.swift
//  TouchGrass
//

import Foundation
import UIKit
import UserNotifications
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging

/// Manages push notification permissions, FCM token registration,
/// and foreground notification presentation.
class NotificationManager: NSObject {
    static let shared = NotificationManager()
    private let db = Firestore.firestore()

    private override init() {}

    /// Call once at app launch (after FirebaseApp.configure).
    func setup(application: UIApplication) {
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self

        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                guard granted else { return }
                DispatchQueue.main.async { application.registerForRemoteNotifications() }
            }
    }

    /// Forward APNs device token to Firebase Messaging.
    func setAPNSToken(_ deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    /// Saves the latest FCM token to Firestore for the current user.
    func saveFCMToken(_ token: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("users").document(uid).updateData(["fcmToken": token]) { _ in }
    }
}

extension NotificationManager: UNUserNotificationCenterDelegate {
    /// Show notifications even when the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

extension NotificationManager: MessagingDelegate {
    // Called by Firebase Messaging when a new FCM registration token is available; saves it to Firestore.
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        saveFCMToken(token)
    }
}
