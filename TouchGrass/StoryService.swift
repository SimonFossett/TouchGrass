//
//  StoryService.swift
//  TouchGrass
//

import Foundation
import UIKit
import Observation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

// MARK: - Story Error

enum StoryError: LocalizedError {
    case encodingFailed
    var errorDescription: String? {
        switch self {
        case .encodingFailed: return "Could not prepare the image for upload."
        }
    }
}

// MARK: - Story Model

struct Story: Identifiable {
    let id: String
    let uid: String
    let username: String
    let imageURL: String
    let createdAt: Date
    let expiresAt: Date
}

// MARK: - User Stories

struct UserStories: Identifiable {
    let uid: String
    let username: String
    var stories: [Story]
    var hasUnseenStory: Bool
    var id: String { uid }
}

// MARK: - Story Service

@Observable
class StoryService {
    static let shared = StoryService()

    /// Active stories from friends, sorted: unseen first, then by username.
    var userStories: [UserStories] = []

    /// The current user's own active stories.
    var myStories: [Story] = []

    private let db = Firestore.firestore()
    private var listeners: [ListenerRegistration] = []
    private var seenIDs: Set<String>

    private init() {
        seenIDs = Set(UserDefaults.standard.stringArray(forKey: "seenStoryIDs") ?? [])
    }

    deinit { listeners.forEach { $0.remove() } }

    // MARK: - Start / Stop Listening

    func startListening(friendUIDs: [String]) {
        listeners.forEach { $0.remove() }
        listeners.removeAll()

        // Immediately remove any cached stories for UIDs that are no longer in
        // the friend list. Without this, a singleton StoryService retains the
        // previous session's stories when a friendless account logs in (or when
        // a friend is removed), because no snapshot ever fires to clear them.
        let newSet = Set(friendUIDs)
        userStories.removeAll { !newSet.contains($0.uid) }

        guard let myUID = Auth.auth().currentUser?.uid else { return }

        // NOTE: We intentionally omit the expiresAt range filter here.
        // Combining whereField equality + range on a different field requires a
        // Firestore composite index. Skipping it avoids that requirement and lets
        // us filter expired stories client-side in parseStories().

        // My own stories
        let myListener = db.collection("stories")
            .whereField("uid", isEqualTo: myUID)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error { print("[StoryService] myStories error: \(error)"); return }
                let stories = self.parseStories(from: snapshot?.documents ?? [])
                DispatchQueue.main.async { self.myStories = stories }
            }
        listeners.append(myListener)

        // One listener per friend
        for uid in friendUIDs {
            let listener = db.collection("stories")
                .whereField("uid", isEqualTo: uid)
                .addSnapshotListener { [weak self] snapshot, error in
                    guard let self else { return }
                    if let error { print("[StoryService] friend \(uid) error: \(error)"); return }
                    let stories = self.parseStories(from: snapshot?.documents ?? [])
                    DispatchQueue.main.async {
                        if stories.isEmpty {
                            self.userStories.removeAll { $0.uid == uid }
                        } else {
                            let username = stories.first?.username ?? ""
                            let hasUnseen = stories.contains { !self.seenIDs.contains($0.id) }
                            let entry = UserStories(uid: uid, username: username, stories: stories, hasUnseenStory: hasUnseen)
                            if let idx = self.userStories.firstIndex(where: { $0.uid == uid }) {
                                self.userStories[idx] = entry
                            } else {
                                self.userStories.append(entry)
                                // Sort: unseen first, then alphabetical
                                self.userStories.sort {
                                    if $0.hasUnseenStory != $1.hasUnseenStory { return $0.hasUnseenStory }
                                    return $0.username.lowercased() < $1.username.lowercased()
                                }
                            }
                        }
                    }
                }
            listeners.append(listener)
        }
    }

    // MARK: - Post Story

    func postStory(image: UIImage) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        // Cap at 1920px on the long side — composite photos from the dual
        // camera can be 12 MP+, which produces 6–8 MB JPEGs and times out.
        let resized = downsampleForStory(image)
        guard let data = resized.jpegData(compressionQuality: 0.82) else {
            throw StoryError.encodingFailed
        }
        print("[Story] uploading \(data.count / 1024) KB for uid \(uid)")

        let storyID = UUID().uuidString
        let ref = Storage.storage().reference().child("stories/\(uid)/\(storyID).jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        do {
            _ = try await ref.putDataAsync(data, metadata: metadata)
        } catch {
            print("[Story] Storage upload FAILED: \(error.localizedDescription)")
            throw error
        }

        let downloadURL: URL
        do {
            downloadURL = try await ref.downloadURL()
        } catch {
            print("[Story] downloadURL FAILED: \(error.localizedDescription)")
            throw error
        }

        // Username is best-effort; story still posts even if fetch fails.
        let username = (try? await fetchUsername(uid: uid)) ?? "Unknown"
        let now      = Date()

        do {
            try await db.collection("stories").document(storyID).setData([
                "uid":       uid,
                "username":  username,
                "imageURL":  downloadURL.absoluteString,
                "createdAt": Timestamp(date: now),
                "expiresAt": Timestamp(date: now.addingTimeInterval(24 * 60 * 60))
            ])
            print("[Story] Firestore write succeeded (\(storyID))")
        } catch {
            print("[Story] Firestore write FAILED: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Image Helpers

    private func downsampleForStory(_ image: UIImage) -> UIImage {
        let maxDimension: CGFloat = 1920
        let px = CGSize(width:  image.size.width  * image.scale,
                        height: image.size.height * image.scale)
        let longest = max(px.width, px.height)
        guard longest > maxDimension else { return image }

        let scale      = maxDimension / longest
        let targetSize = CGSize(width: px.width * scale, height: px.height * scale)
        let format     = UIGraphicsImageRendererFormat()
        format.scale   = 1
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    // MARK: - Mark Seen

    func markSeen(storyID: String) {
        guard !seenIDs.contains(storyID) else { return }
        seenIDs.insert(storyID)
        UserDefaults.standard.set(Array(seenIDs), forKey: "seenStoryIDs")
        for i in userStories.indices {
            userStories[i].hasUnseenStory = userStories[i].stories.contains { !seenIDs.contains($0.id) }
        }
    }

    // MARK: - Load Story Image (cached)

    func loadImage(for story: Story) async -> UIImage? {
        if let cached = Self.imageCache[story.id] { return cached }
        guard let url = URL(string: story.imageURL),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data) else { return nil }
        Self.imageCache[story.id] = image
        return image
    }

    // MARK: - Private Helpers

    private func parseStories(from docs: [QueryDocumentSnapshot]) -> [Story] {
        let now = Date()
        return docs.compactMap { doc -> Story? in
            let data = doc.data()
            guard let uid      = data["uid"]       as? String,
                  let username = data["username"]  as? String,
                  let imageURL = data["imageURL"]  as? String,
                  let createdTS = data["createdAt"] as? Timestamp,
                  let expiresTS = data["expiresAt"] as? Timestamp else { return nil }
            return Story(
                id: doc.documentID,
                uid: uid,
                username: username,
                imageURL: imageURL,
                createdAt: createdTS.dateValue(),
                expiresAt: expiresTS.dateValue()
            )
        }
        .filter { $0.expiresAt > now }        // discard stories older than 24 h
        .sorted { $0.createdAt < $1.createdAt }
    }

    private func fetchUsername(uid: String) async throws -> String {
        let doc = try await db.collection("users").document(uid).getDocument()
        return doc.data()?["username"] as? String ?? "Unknown"
    }

    private static var imageCache: [String: UIImage] = [:]
}
