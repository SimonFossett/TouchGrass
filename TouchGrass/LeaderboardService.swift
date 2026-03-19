//
//  LeaderboardService.swift
//  TouchGrass
//

import Foundation
import CoreLocation
import FirebaseAuth
import FirebaseFirestore

// MARK: - Leaderboard Type

enum LeaderboardType: String, CaseIterable, Identifiable {
    case daily = "Daily Steps"
    case overall = "Step Score"
    var id: String { rawValue }
}

// MARK: - Leaderboard Entry

struct LeaderboardEntry: Identifiable {
    let id: String          // Firebase UID
    let username: String
    let dailySteps: Int
    let totalStepScore: Int
    let dailyStreak: Int
    let overallStreak: Int
    let isCurrentUser: Bool

    func value(for type: LeaderboardType) -> Int {
        type == .daily ? dailySteps : totalStepScore
    }

    func streak(for type: LeaderboardType) -> Int {
        type == .daily ? dailyStreak : overallStreak
    }
}

// MARK: - Leaderboard Service

class LeaderboardService {
    static let shared = LeaderboardService()
    private let db = Firestore.firestore()
    private init() {}

    // MARK: Leaderboard entries (current user + all accepted friends)

    func fetchEntries() async throws -> [LeaderboardEntry] {
        guard let myUID = Auth.auth().currentUser?.uid else { return [] }

        let friendUIDs = (try? await FriendService.shared.friendUIDs()) ?? []
        let allUIDs = [myUID] + friendUIDs

        // Capture MainActor-isolated values before leaving the main actor
        let myDailySteps  = await MainActor.run { StepCounterManager.shared.dailySteps }
        let myTotalScore  = await MainActor.run { StepCounterManager.shared.totalStepScore }

        // Fetch all user docs in parallel
        return await withTaskGroup(of: LeaderboardEntry?.self) { group in
            for uid in allUIDs {
                group.addTask { [weak self] in
                    guard let self,
                          let doc = try? await self.db.collection("users").document(uid).getDocument(),
                          let username = doc.data()?["username"] as? String else { return nil }

                    let isCurrentUser = uid == myUID
                    // Use live values from StepCounterManager for the current user
                    let dailySteps   = isCurrentUser ? myDailySteps  : (doc.data()?["dailySteps"] as? Int ?? 0)
                    let totalScore   = isCurrentUser ? myTotalScore  : (doc.data()?["stepScore"]  as? Int ?? 0)

                    return LeaderboardEntry(
                        id: uid,
                        username: username,
                        dailySteps: dailySteps,
                        totalStepScore: totalScore,
                        dailyStreak: doc.data()?["dailyStreak"] as? Int ?? 0,
                        overallStreak: doc.data()?["overallStreak"] as? Int ?? 0,
                        isCurrentUser: isCurrentUser
                    )
                }
            }
            var results: [LeaderboardEntry] = []
            for await entry in group { if let e = entry { results.append(e) } }
            return results
        }
    }

    // MARK: Streak update (call after loading entries, runs in background)

    /// Checks whether the current user is leading either leaderboard today and
    /// increments their streak counters in Firestore accordingly.
    func updateStreaksIfNeeded(entries: [LeaderboardEntry]) async {
        guard let myUID = Auth.auth().currentUser?.uid,
              let me = entries.first(where: { $0.isCurrentUser }) else { return }

        let today = dateString(for: Date())

        let dailyLeader = entries.max { $0.dailySteps < $1.dailySteps }
        if dailyLeader?.id == myUID, me.dailySteps > 0 {
            await incrementStreak(uid: myUID, key: "daily", today: today)
        }

        let overallLeader = entries.max { $0.totalStepScore < $1.totalStepScore }
        if overallLeader?.id == myUID, me.totalStepScore > 0 {
            await incrementStreak(uid: myUID, key: "overall", today: today)
        }
    }

    private func incrementStreak(uid: String, key: String, today: String) async {
        let streakField      = "\(key)Streak"
        let lastUpdatedField = "\(key)StreakLastUpdated"
        let ref = db.collection("users").document(uid)

        guard let doc = try? await ref.getDocument() else { return }
        let lastUpdated   = doc.data()?[lastUpdatedField] as? String ?? ""
        let currentStreak = doc.data()?[streakField]       as? Int    ?? 0

        guard lastUpdated != today else { return }   // already recorded today

        let yesterday  = dateString(for: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
        let newStreak  = lastUpdated == yesterday ? currentStreak + 1 : 1

        try? await ref.updateData([streakField: newStreak, lastUpdatedField: today])
    }

    // MARK: Friends for HomeView (Firestore-backed, with streak data)

    /// Returns the current user's accepted friends as Friend objects, ready for
    /// the HomeView list. Respects local pin state stored in UserDefaults.
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

    // MARK: Helpers

    private func dateString(for date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }
}
