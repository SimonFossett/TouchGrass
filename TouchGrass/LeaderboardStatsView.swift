//
//  LeaderboardStatsView.swift
//  TouchGrass
//

import SwiftUI

// MARK: - Leaderboard Stats View

/// Displays a user's lifetime leaderboard placement counters (1st / 2nd / 3rd).
/// Data comes from the Firestore `leaderboardStats` map, updated nightly by the
/// midnightReset Cloud Function. Used by both ProfileView and FriendProfileView.
struct LeaderboardStatsView: View {
    let firstPlace: Int
    let secondPlace: Int
    let thirdPlace: Int

    var body: some View {
        VStack(spacing: 14) {
            PlacementCard(
                count: firstPlace,
                unit: firstPlace == 1 ? "Win" : "Wins"
            )
            PlacementCard(
                count: secondPlace,
                unit: "Top 2"
            )
            PlacementCard(
                count: thirdPlace,
                unit: "Top 3"
            )
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
    }
}

// MARK: - Placement Card

private struct PlacementCard: View {
    let count: Int
    let unit: String

    var body: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(count.formatted()) \(unit)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .monospacedDigit()
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(GlassBackground(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
    }
}
