//
//  MonthlyStepGridView.swift
//  TouchGrass
//

import SwiftUI
import Observation

// MARK: - Step Grid Manager

/// Persists and retrieves per-day step counts (keyed by date) in UserDefaults.
/// Acts as the single source of truth for the monthly grid.
@Observable
final class StepGridManager {
    static let shared = StepGridManager()

    private let defaults    = UserDefaults.standard
    private let keyPrefix   = "stepGrid_"
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private init() {}

    // MARK: - Save / Load

    /// Saves `steps` for `date`, only if the new value is higher than what's already stored.
    // Persists the step count for a given date, only overwriting if the new value is higher.
    func saveSteps(_ steps: Int, for date: Date) {
        guard steps > 0 else { return }
        let key = keyPrefix + formatter.string(from: date)
        let existing = defaults.integer(forKey: key)
        if steps > existing {
            defaults.set(steps, forKey: key)
        }
    }

    // Returns the stored step count for the given date, or 0 if no data has been saved.
    func steps(for date: Date) -> Int {
        let key = keyPrefix + formatter.string(from: date)
        return defaults.integer(forKey: key)
    }

    // MARK: - Monthly Data

    /// Returns one cell per calendar slot for the given month's grid.
    /// Slots before the 1st and after the last day of the month have `date == nil`.
    // Builds the full 7-column calendar grid for the given month, padding with nil dates before the 1st and after the last day.
    func gridCells(for month: Date) -> [(date: Date?, steps: Int)] {
        let cal = Calendar.current
        let firstDay = cal.startOfMonth(for: month)
        guard let range = cal.range(of: .day, in: .month, for: firstDay) else { return [] }

        // weekday offset: Sunday = 0, Monday = 1, …, Saturday = 6
        let offset     = cal.component(.weekday, from: firstDay) - 1
        let daysInMonth = range.count
        let totalCells  = Int(ceil(Double(offset + daysInMonth) / 7.0)) * 7

        return (0..<totalCells).map { i in
            let dayIndex = i - offset
            guard dayIndex >= 0, dayIndex < daysInMonth,
                  let date = cal.date(byAdding: .day, value: dayIndex, to: firstDay)
            else { return (nil, 0) }
            return (date, steps(for: date))
        }
    }

    /// Sum of all saved step counts within the given month.
    // Sums all saved step counts for every day in the given month.
    func monthlyTotal(for month: Date) -> Int {
        let cal = Calendar.current
        let firstDay = cal.startOfMonth(for: month)
        guard let range = cal.range(of: .day, in: .month, for: firstDay) else { return 0 }
        return range.reduce(0) { total, day in
            guard let date = cal.date(byAdding: .day, value: day - 1, to: firstDay) else { return total }
            return total + steps(for: date)
        }
    }
}

// MARK: - Calendar Helper

extension Calendar {
    /// The first instant of the month containing `date`.
    // Returns the first instant (midnight) of the month containing the given date.
    func startOfMonth(for date: Date) -> Date {
        let comps = dateComponents([.year, .month], from: date)
        return self.date(from: comps) ?? date
    }
}

// MARK: - Step → Color Mapping

// Maps a step count to a green intensity color, ranging from dark gray (0) to brightest green (10k+).
private func stepColor(for steps: Int) -> Color {
    switch steps {
    case 0:              return Color(UIColor.systemGray5)                      // no activity
    case 1..<1_000:      return Color(red: 0.054, green: 0.267, blue: 0.161)   // very dark green
    case 1_000..<5_000:  return Color(red: 0.000, green: 0.427, blue: 0.196)   // dark green
    case 5_000..<7_500:  return Color(red: 0.149, green: 0.651, blue: 0.255)   // medium green
    case 7_500..<10_000: return Color(red: 0.224, green: 0.827, blue: 0.325)   // light green
    default:             return Color(red: 0.341, green: 1.000, blue: 0.541)   // brightest green
    }
}

// MARK: - Monthly Step Grid View

struct MonthlyStepGridView: View {
    /// When non-nil, the grid renders in read-only "friend" mode: today's cell
    /// shows `friendTodaySteps` and every other day is empty. Friend daily
    /// history isn't stored in Firestore, so earlier days always read as 0.
    var friendTodaySteps: Int? = nil

    private let gridManager = StepGridManager.shared
    private let stepManager = StepCounterManager.shared

    @State private var displayedMonth: Date = Calendar.current.startOfMonth(for: Date())
    @State private var selectedCellIndex: Int? = nil

    private let maxMonthsBack = 12
    private let calendar      = Calendar.current
    private let dayLabels     = ["S", "M", "T", "W", "T", "F", "S"]

    private var isFriendMode: Bool { friendTodaySteps != nil }

    private var cells: [(date: Date?, steps: Int)] {
        let base = gridManager.gridCells(for: displayedMonth)
        guard let todaySteps = friendTodaySteps else { return base }
        return base.map { cell in
            guard let date = cell.date else { return cell }
            let steps = calendar.isDateInToday(date) ? todaySteps : 0
            return (date, steps)
        }
    }

    private var monthlyTotal: Int {
        if let todaySteps = friendTodaySteps {
            let today = Date()
            let monthStart = calendar.startOfMonth(for: displayedMonth)
            let todayMonthStart = calendar.startOfMonth(for: today)
            return monthStart == todayMonthStart ? todaySteps : 0
        }
        return gridManager.monthlyTotal(for: displayedMonth)
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: displayedMonth)
    }

    private var canGoBack: Bool {
        guard let limit = calendar.date(
            byAdding: .month, value: -maxMonthsBack,
            to: calendar.startOfMonth(for: Date())
        ) else { return false }
        return displayedMonth > limit
    }

    private var canGoForward: Bool {
        displayedMonth < calendar.startOfMonth(for: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            // ── Header ───────────────────────────────────────────────────
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(monthlyTotal.formatted()) steps")
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("in \(monthTitle)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                HStack(spacing: 6) {
                    navButton(systemImage: "chevron.left", enabled: canGoBack) {
                        displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
                    }
                    navButton(systemImage: "chevron.right", enabled: canGoForward) {
                        displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
                    }
                }
            }

            // ── Day-of-week labels ────────────────────────────────────────
            HStack(spacing: 4) {
                ForEach(Array(dayLabels.enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // ── Calendar grid ─────────────────────────────────────────────
            let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                    StepGridCell(
                        date: cell.date,
                        steps: cell.steps,
                        isSelected: selectedCellIndex == index
                    )
                    .onTapGesture {
                        guard cell.date != nil else { return }
                        selectedCellIndex = selectedCellIndex == index ? nil : index
                    }
                    .popover(
                        isPresented: Binding(
                            get: { selectedCellIndex == index },
                            set: { if !$0 { selectedCellIndex = nil } }
                        )
                    ) {
                        StepDayPopover(date: cell.date!, steps: cell.steps)
                            .presentationCompactAdaptation(.popover)
                    }
                }
            }

            // ── Legend ────────────────────────────────────────────────────
            HStack(spacing: 5) {
                Spacer()
                Text("Less")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                ForEach([0, 500, 2500, 6000, 8500, 10_000], id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(stepColor(for: level))
                        .frame(width: 12, height: 12)
                }
                Text("More")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        .onAppear {
            // Persist current step count whenever the tab is opened (current user only)
            if !isFriendMode, stepManager.dailySteps > 0 {
                gridManager.saveSteps(stepManager.dailySteps, for: Date())
            }
        }
        .onChange(of: stepManager.dailySteps) { _, newValue in
            guard !isFriendMode else { return }
            gridManager.saveSteps(newValue, for: Date())
        }
        .onChange(of: displayedMonth) { _, _ in
            selectedCellIndex = nil
        }
    }

    // MARK: - Navigation Button

    // Renders a circular chevron button that triggers the given action, dimmed when disabled.
    @ViewBuilder
    private func navButton(systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { action() }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(enabled ? .primary : Color(UIColor.systemGray3))
                .frame(width: 30, height: 30)
                .background(Color(UIColor.systemGray5))
                .clipShape(Circle())
        }
        .disabled(!enabled)
    }
}

// MARK: - Grid Cell

private struct StepGridCell: View {
    let date: Date?
    let steps: Int
    var isSelected: Bool = false

    private var isToday: Bool {
        guard let date else { return false }
        return Calendar.current.isDateInToday(date)
    }

    var body: some View {
        GeometryReader { geo in
            let side = geo.size.width
            if date != nil {
                RoundedRectangle(cornerRadius: 3)
                    .fill(stepColor(for: steps))
                    .frame(width: side, height: side)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(
                                isSelected
                                    ? Color.white
                                    : (isToday ? Color.white.opacity(0.55) : Color.clear),
                                lineWidth: isSelected ? 2 : 1.5
                            )
                    )
            } else {
                Color.clear.frame(width: side, height: side)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Day Popup

private struct StepDayPopover: View {
    let date: Date
    let steps: Int

    private var dayString: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM d"
        return f.string(from: date)
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(dayString)
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(spacing: 6) {
                Circle()
                    .fill(stepColor(for: steps))
                    .frame(width: 10, height: 10)
                Text(steps == 0 ? "No steps recorded" : "\(steps.formatted()) steps")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
