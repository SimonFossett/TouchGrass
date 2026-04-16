//
//  LeaderboardService.swift
//  TouchGrass
//

import Foundation
import CoreLocation
import FirebaseAuth
import FirebaseFirestore
import Observation

// MARK: - Leaderboard Type

enum LeaderboardType: String, CaseIterable, Identifiable {
    case daily = "Daily Steps"
    case overall = "Step Score"
    var id: String { rawValue }
}

// MARK: - Leaderboard Entry

struct LeaderboardEntry: Identifiable, Equatable {
    let id: String          // Firebase UID
    let username: String
    let dailySteps: Int
    let totalStepScore: Int
    let dailyStreak: Int
    let isCurrentUser: Bool

    // Returns the relevant step value (daily steps or total score) for a given leaderboard type.
    func value(for type: LeaderboardType) -> Int {
        type == .daily ? dailySteps : totalStepScore
    }
}

// MARK: - Leaderboard Service

@Observable
class LeaderboardService {
    static let shared = LeaderboardService()

    /// Live leaderboard entries — updated in real time by Firestore listeners.
    var entries: [LeaderboardEntry] = []
    var isLoading = true
    var loadFailed = false

    private let db = Firestore.firestore()
    @ObservationIgnored private var listeners: [String: ListenerRegistration] = [:]
    @ObservationIgnored private var expectedCount = 0

    private init() {}
    deinit { stopListening() }

    // MARK: - Start / Stop

    /// Opens one Firestore snapshot listener per user (self + each friend).
    /// Any subsequent change to a user doc propagates immediately.
    // Opens one real-time Firestore listener per user (self + friends) and keeps entries updated live.
    func startListening(friendUIDs: [String]) {
        stopListening()
        guard let myUID = Auth.auth().currentUser?.uid else {
            isLoading = false
            return
        }

        let allUIDs = [myUID] + friendUIDs
        expectedCount = allUIDs.count
        entries = []
        isLoading = true
        loadFailed = false

        for uid in allUIDs {
            let isCurrentUser = uid == myUID
            let listener = db.collection("users").document(uid)
                .addSnapshotListener { [weak self] snapshot, error in
                    guard let self else { return }
                    if let error {
                        print("[LeaderboardService] listener error for \(uid): \(error)")
                        DispatchQueue.main.async {
                            self.loadFailed = true
                            self.isLoading = false
                        }
                        return
                    }
                    guard let data = snapshot?.data(),
                          let username = data["username"] as? String else { return }

                    let today = UserService.todayDateString()
                    let storedDate = data["dailyStepsDate"] as? String ?? ""
                    let dailySteps = storedDate == today ? (data["dailySteps"] as? Int ?? 0) : 0

                    let entry = LeaderboardEntry(
                        id: uid,
                        username: username,
                        dailySteps: dailySteps,
                        totalStepScore: data["stepScore"] as? Int ?? 0,
                        dailyStreak: data["dailyStreak"] as? Int ?? 0,
                        isCurrentUser: isCurrentUser
                    )

                    DispatchQueue.main.async {
                        if let idx = self.entries.firstIndex(where: { $0.id == uid }) {
                            self.entries[idx] = entry
                        } else {
                            self.entries.append(entry)
                        }
                        if self.isLoading && self.entries.count >= self.expectedCount {
                            self.isLoading = false
                        }
                    }
                }
            listeners[uid] = listener
        }
    }

    // Removes all active Firestore snapshot listeners and clears the listener registry.
    func stopListening() {
        listeners.values.forEach { $0.remove() }
        listeners.removeAll()
    }

    // MARK: - Friends for HomeView

    /// Returns the current user's accepted friends as Friend objects, ready for
    /// the HomeView list. Respects local pin state stored in UserDefaults.
    // Fetches all accepted friends as Friend objects for use in HomeView, with pin state applied.
    func fetchFriendsForHome() async -> [Friend] {
        let uids = (try? await FriendService.shared.friendUIDs()) ?? []
        let pinnedIDs = Set(UserDefaults.standard.stringArray(forKey: "pinnedFriendIDs") ?? [])

        return await withTaskGroup(of: Friend?.self) { group in
            for uid in uids {
                group.addTask { [weak self] in
                    guard let self,
                          let doc = try? await self.db.collection("users").document(uid).getDocument(),
                          let username = doc.data()?["username"] as? String else { return nil }
                    let lat = doc.data()?["latitude"] as? Double ?? 0
                    let lng = doc.data()?["longitude"] as? Double ?? 0
                    return Friend(
                        uid: uid,
                        name: username,
                        coordinate: .init(latitude: lat, longitude: lng),
                        stepScore: doc.data()?["stepScore"] as? Int ?? 0,
                        isPinned: pinnedIDs.contains(uid),
                        streak: doc.data()?["dailyStreak"] as? Int ?? 0
                    )
                }
            }
            var results: [Friend] = []
            for await friend in group { if let f = friend { results.append(f) } }
            return results.sorted { $0.name.lowercased() < $1.name.lowercased() }
        }
    }
}
