//
//  FriendProfileView.swift
//  TouchGrass
//

import SwiftUI
import Charts
import UIKit
import FirebaseFirestore

private enum FriendProfileTab: CaseIterable {
    case activity, grid, stats
}

struct FriendProfileView: View {
    let friend: Friend

    @Environment(\.dismiss) private var dismiss
    @State private var profileImage: UIImage? = nil
    @State private var selectedTab: FriendProfileTab = .activity
    /// Starts as an empty dict (friend mode, loading). Populated once Firestore
    /// responds. Keys are "yyyy-MM-dd"; today's live count is merged in after fetch.
    @State private var stepHistory: [String: Int] = [:]

    private let leaderboardService = LeaderboardService.shared
    private let db = Firestore.firestore()

    private var entry: LeaderboardEntry? {
        leaderboardService.entries.first(where: { $0.id == friend.uid })
    }

    private var dailySteps: Int {
        entry?.dailySteps ?? 0
    }

    private var stepScore: Int {
        entry?.totalStepScore ?? friend.stepScore
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(spacing: 28) {

                    // MARK: Profile picture
                    ZStack {
                        if let img = profileImage {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 120, height: 120)
                                .clipShape(Circle())
                                .overlay(Circle().strokeBorder(Color(UIColor.systemGray4), lineWidth: 1))
                        } else {
                            Circle()
                                .fill(Color(UIColor.systemGray3))
                                .frame(width: 120, height: 120)
                            Image(systemName: "person.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.top, 48)

                    // MARK: Username + step score
                    VStack(spacing: 4) {
                        Text(friend.name)
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("\(stepScore.formatted()) step score")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    // MARK: Profile tab bar (matches ProfileView)
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            ForEach(FriendProfileTab.allCases, id: \.self) { tab in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        selectedTab = tab
                                    }
                                } label: {
                                    VStack(spacing: 6) {
                                        Group {
                                            switch tab {
                                            case .activity:
                                                Image(systemName: "chart.bar.fill")
                                                    .font(.system(size: 20))
                                                    .foregroundColor(selectedTab == tab ? .primary : .secondary)
                                            case .grid:
                                                StepGridTabIcon()
                                                    .opacity(selectedTab == tab ? 1 : 0.4)
                                            case .stats:
                                                Image(systemName: "trophy.fill")
                                                    .font(.system(size: 20))
                                                    .foregroundColor(selectedTab == tab ? .primary : .secondary)
                                            }
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.top, 10)
                                        .padding(.bottom, 6)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        GeometryReader { geo in
                            let tabCount = CGFloat(FriendProfileTab.allCases.count)
                            let tabWidth = geo.size.width / tabCount
                            let index = CGFloat(FriendProfileTab.allCases.firstIndex(of: selectedTab) ?? 0)
                            Rectangle()
                                .fill(Color.primary)
                                .frame(width: tabWidth, height: 1.5)
                                .offset(x: tabWidth * index)
                                .animation(.easeInOut(duration: 0.2), value: selectedTab)
                        }
                        .frame(height: 1.5)
                    }

                    // MARK: Tab content
                    if selectedTab == .activity {
                        StepMetricCard(
                            value: dailySteps.formatted(),
                            label: "Daily Steps",
                            icon: "figure.walk",
                            color: .green
                        )
                        .padding(.horizontal, 24)

                        FriendDailyStepsChartView(entry: entry, displayName: friend.name)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 32)
                    } else if selectedTab == .grid {
                        MonthlyStepGridView(friendStepHistory: stepHistory)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 32)
                    } else {
                        LeaderboardStatsView(
                            firstPlace:  entry?.firstPlace  ?? 0,
                            secondPlace: entry?.secondPlace ?? 0,
                            thirdPlace:  entry?.thirdPlace  ?? 0
                        )
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 24) }
        }
        .background(Color(UIColor.systemBackground).ignoresSafeArea())
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                    .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
            }
            .padding(.leading, 20)
            .padding(.top, 16)
        }
        .task(id: friend.uid) {
            async let img = AvatarCache.shared.fetch(uid: friend.uid)
            async let history = fetchStepHistory(uid: friend.uid)
            let (loadedImage, loadedHistory) = await (img, history)
            profileImage = loadedImage
            applyStepHistory(loadedHistory)
        }
        .onChange(of: dailySteps) { _, newSteps in
            // Keep today's cell live as the friend's step count updates.
            let todayKey = UserService.todayDateString()
            if newSteps > (stepHistory[todayKey] ?? 0) {
                stepHistory[todayKey] = newSteps
            }
        }
    }

    // MARK: - Helpers

    private func fetchStepHistory(uid: String) async -> [String: Int] {
        guard let doc = try? await db.collection("users").document(uid).getDocument(),
              let history = doc.data()?["stepHistory"] as? [String: Int] else { return [:] }
        return history
    }

    private func applyStepHistory(_ history: [String: Int]) {
        var merged = history
        // Overlay today's live step count so the current day is always accurate.
        let todayKey = UserService.todayDateString()
        let live = dailySteps
        if live > 0 {
            merged[todayKey] = max(live, merged[todayKey] ?? 0)
        }
        stepHistory = merged
    }
}

// MARK: - Single-line Daily Steps Chart (friend view)

struct FriendDailyStepsChartView: View {
    let entry: LeaderboardEntry?
    let displayName: String

    private var chartPoints: [StepChartPoint] {
        guard let entry else { return [] }
        let label = displayName
        var points: [StepChartPoint] = [
            StepChartPoint(hour: 0, cumulativeSteps: 0, label: label)
        ]
        let currentHour = Calendar.current.component(.hour, from: Date())

        if !entry.hourlySteps.isEmpty {
            // Forward-fill so gaps between hourly snapshots produce a
            // monotonically increasing staircase rather than dips to zero.
            var filled = entry.hourlySteps
            for h in 1..<filled.count {
                if filled[h] == 0 { filled[h] = filled[h - 1] }
            }
            for h in 0...min(currentHour, filled.count - 1) where filled[h] > 0 {
                points.append(StepChartPoint(hour: h + 1, cumulativeSteps: filled[h], label: label))
            }
            if entry.dailySteps > 0 {
                let lastPlotted = points.last?.cumulativeSteps ?? 0
                if entry.dailySteps > lastPlotted {
                    points.append(StepChartPoint(hour: currentHour + 1, cumulativeSteps: entry.dailySteps, label: label))
                }
            }
        } else if entry.dailySteps > 0 {
            // Fallback: linear projection when no hourly data is synced yet.
            for hour in 0...currentHour {
                let fraction = Double(hour + 1) / Double(currentHour + 1)
                let projected = Int(Double(entry.dailySteps) * fraction)
                points.append(StepChartPoint(hour: hour + 1, cumulativeSteps: projected, label: label))
            }
        }
        return points
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Today")
                .font(.headline)

            Chart(chartPoints) { point in
                LineMark(
                    x: .value("Hour", point.hour),
                    y: .value("Steps", point.cumulativeSteps)
                )
                .foregroundStyle(Color.green)
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2.5))
            }
            .chartXScale(domain: 0...24)
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18, 24]) { value in
                    if let hour = value.as(Int.self) {
                        AxisValueLabel { Text(hourLabel(hour)).font(.caption2) }
                        AxisGridLine()
                    }
                }
            }
            .chartYScale(domain: .automatic(includesZero: true))
            .chartYAxis {
                AxisMarks { value in
                    if let steps = value.as(Int.self) {
                        AxisValueLabel {
                            Text(steps >= 1000 ? "\(steps / 1000)k" : "\(steps)")
                                .font(.caption2)
                        }
                        AxisGridLine()
                    }
                }
            }
            .frame(height: 160)
        }
        .padding(16)
        .background(GlassBackground(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
    }

    private func hourLabel(_ hour: Int) -> String {
        if hour == 0 || hour == 24 { return "12a" }
        if hour < 12 { return "\(hour)a" }
        if hour == 12 { return "12p" }
        return "\(hour - 12)p"
    }
}
