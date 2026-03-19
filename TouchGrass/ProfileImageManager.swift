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
        loadImage()
    }

    /// Saves the image locally and uploads it to Firebase Storage.
    func saveImage(_ image: UIImage) {
        profileImage = image
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        do {
            try data.write(to: imageURL, options: .atomic)
        } catch {
            print("[ProfileImageManager] local save failed: \(error)")
        }
        Task { await uploadToStorage(data: data) }
    }

    /// Removes the local file and deletes the image from Firebase Storage.
    func clearImage() {
        profileImage = nil
        try? FileManager.default.removeItem(at: imageURL)
        Task { await deleteFromStorage() }
    }

    // MARK: - Private

    private func loadImage() {
        // Use the locally cached copy when available (fast path)
        if let data = try? Data(contentsOf: imageURL),
           let image = UIImage(data: data) {
            profileImage = image
            return
        }
        // No local copy — try downloading from Storage (e.g. after a fresh install)
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
            let data = try await ref.data(maxSize: 5 * 1024 * 1024)
            guard let image = UIImage(data: data) else { return }
            profileImage = image
            try? data.write(to: imageURL, options: .atomic)
        } catch {
            // 404 is expected on first install — only log unexpected errors
            let nsErr = error as NSError
            if nsErr.domain != StorageErrorDomain || nsErr.code != StorageErrorCode.objectNotFound.rawValue {
                print("[ProfileImageManager] download failed: \(error)")
            }
        }
    }

    private func deleteFromStorage() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let ref = Storage.storage().reference().child("profile_images/\(uid).jpg")
        do {
            try await ref.delete()
        } catch {
            print("[ProfileImageManager] delete failed: \(error)")
        }
    }

    private var imageURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("profile_image.jpg")
    }
}
