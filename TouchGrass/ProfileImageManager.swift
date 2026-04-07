//
//  ProfileImageManager.swift
//  TouchGrass
//

import Foundation
import UIKit
import Observation
import FirebaseAuth
import FirebaseStorage

@Observable
class ProfileImageManager {
    static let shared = ProfileImageManager()

    var profileImage: UIImage?

    private init() {
        // Load the locally-cached copy immediately on first launch / fresh install.
        loadImage()

        // Re-download whenever a user signs in. This covers the sign-out → sign-in
        // flow: clearImage() wipes the local cache on sign-out, so the next sign-in
        // must trigger a fresh download from Firebase Storage.
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self, user != nil else { return }
            self.loadImage()
        }
    }

    /// Persists the image locally and uploads it to Firebase Storage.
    func saveImage(_ image: UIImage) {
        profileImage = image
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        do {
            try data.write(to: localURL, options: .atomic)
        } catch {
            print("[ProfileImageManager] local save failed: \(error)")
        }
        Task { await uploadToStorage(data: data) }
    }

    /// Clears the in-memory cache and local disk copy for the current session.
    ///
    /// The image is intentionally **not** deleted from Firebase Storage —
    /// it must survive across sign-out/sign-in so the next session can
    /// re-download it automatically.
    func clearImage() {
        profileImage = nil
        try? FileManager.default.removeItem(at: localURL)
    }

    // MARK: - Private

    private func loadImage() {
        // Fast path: serve from the on-disk cache without a network round-trip.
        if let data  = try? Data(contentsOf: localURL),
           let image = UIImage(data: data) {
            profileImage = image
            return
        }
        // No local copy — download from Storage (first install, or after sign-out).
        Task { await downloadFromStorage() }
    }

    private func uploadToStorage(data: Data) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let ref = Storage.storage().reference().child("profile_images/\(uid).jpg")
        do {
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"
            _ = try await ref.putDataAsync(data, metadata: metadata)
        } catch {
            print("[ProfileImageManager] upload failed: \(error)")
        }
    }

    private func downloadFromStorage() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let ref = Storage.storage().reference().child("profile_images/\(uid).jpg")
        do {
            let data  = try await ref.data(maxSize: 5 * 1024 * 1024)
            guard let image = UIImage(data: data) else { return }
            profileImage = image
            try? data.write(to: localURL, options: .atomic)
        } catch {
            // 404 is expected for users who haven't set a photo yet.
            let nsErr = error as NSError
            if nsErr.domain != StorageErrorDomain ||
               nsErr.code   != StorageErrorCode.objectNotFound.rawValue {
                print("[ProfileImageManager] download failed: \(error)")
            }
        }
    }

    private var localURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("profile_image.jpg")
    }
}
