//
//  LeaderboardStatsView.swift
//  TouchGrass
//

import SwiftUI

// MARK: - Leaderboard Stats View

struct LeaderboardStatsView: View {
    let firstPlace: Int
    let secondPlace: Int
    let thirdPlace: Int

    var body: some View {
        VStack(spacing: 0) {
            StatCell(count: firstPlace, label: "WINS")

            Rectangle()
                .fill(Color.primary.opacity(0.15))
                .frame(height: 1)
                .padding(.horizontal, 24)

            StatCell(count: secondPlace, label: "PLACES IN TOP 2")

            Rectangle()
                .fill(Color.primary.opacity(0.15))
                .frame(height: 1)
                .padding(.horizontal, 24)

            StatCell(count: thirdPlace, label: "PLACES IN TOP 3")
        }
        .frame(maxWidth: .infinity)
        .background(GlassBackground(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
    }
}

// MARK: - Stat Cell

private struct StatCell: View {
    let count: Int
    let label: String

    var body: some View {
        VStack(spacing: 10) {
            Text("\(count.formatted())")
                .font(.system(size: 46, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}
