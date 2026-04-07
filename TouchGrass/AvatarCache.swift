//
//  AvatarCache.swift
//  TouchGrass
//
//  Shared, disk-backed cache for other users' profile pictures.
//  Images are written to Caches/avatars/{uid}.jpg so they survive
//  app restarts. On relaunch the image loads from disk (instant) instead
//  of re-downloading from Firebase Storage.
//

import UIKit
import FirebaseStorage

final class AvatarCache {
    static let shared = AvatarCache()

    private var memory: [String: UIImage] = [:]
    private let fm = FileManager.default
    private let cacheDir: URL

    private init() {
        cacheDir = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("avatars", isDirectory: true)
        try? fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    /// Returns a cached image immediately (memory → disk) without any network call.
    /// Safe to call synchronously; disk access only happens once per UID per session.
    func cached(uid: String) -> UIImage? {
        if let img = memory[uid] { return img }
        guard let data = try? Data(contentsOf: diskURL(for: uid)),
              let img = UIImage(data: data) else { return nil }
        memory[uid] = img
        return img
    }

    /// Returns the cached image if present, otherwise downloads from Firebase Storage,
    /// stores it in memory and on disk, then returns it.
    @discardableResult
    func fetch(uid: String) async -> UIImage? {
        if let img = cached(uid: uid) { return img }
        let ref = Storage.storage().reference().child("profile_images/\(uid).jpg")
        guard let data = try? await ref.data(maxSize: 5 * 1024 * 1024),
              let img = UIImage(data: data) else { return nil }
        memory[uid] = img
        try? data.write(to: diskURL(for: uid), options: .atomic)
        return img
    }

    /// Kicks off parallel background fetches for a list of UIDs, skipping any
    /// that are already cached. Call this as soon as the friends list is available
    /// so images are ready before the user scrolls to them.
    func prefetch(uids: [String]) {
        for uid in uids where cached(uid: uid) == nil {
            Task { await fetch(uid: uid) }
        }
    }

    private func diskURL(for uid: String) -> URL {
        cacheDir.appendingPathComponent("\(uid).jpg")
    }
}
