//
//  ProfileImageManager.swift
//  TouchGrass
//

import Foundation
import UIKit
import Observation

@Observable
class ProfileImageManager {
    static let shared = ProfileImageManager()

    var profileImage: UIImage?

    private init() {
        loadImage()
    }

    func saveImage(_ image: UIImage) {
        profileImage = image
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        try? data.write(to: imageURL, options: .atomic)
    }

    func clearImage() {
        profileImage = nil
        try? FileManager.default.removeItem(at: imageURL)
    }

    private func loadImage() {
        guard let data = try? Data(contentsOf: imageURL),
              let image = UIImage(data: data) else { return }
        profileImage = image
    }

    private var imageURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("profile_image.jpg")
    }
}
