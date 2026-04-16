import SwiftUI

/// A text view that counts up from 0 to `value` with an ease-out animation,
/// finishing with a small spring "pop". Each instance animates independently
/// and only triggers once per appearance (not on re-renders or scroll bounces).
struct AnimatedStepCounter: View {
    let value: Int
    var font: Font = .body
    var color: Color = .primary
    /// Optional leading delay in seconds (used for staggered leaderboard rows).
    var delay: Double = 0

    @State private var displayedValue: Double = 0
    @State private var scale: CGFloat = 1.0
    @State private var hasAnimated = false

    var body: some View {
        Text(Int(displayedValue).formatted())
            .font(font)
            .foregroundColor(color)
            .monospacedDigit()
            .scaleEffect(scale)
            .onAppear {
                guard !hasAnimated else { return }
                hasAnimated = true
                guard value > 0 else {
                    displayedValue = Double(value)
                    return
                }
                let duration = animationDuration(for: value)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(.easeOut(duration: duration)) {
                        displayedValue = Double(value)
                    }
                    // Subtle scale pop when counting finishes
                    DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                        withAnimation(.spring(response: 0.18, dampingFraction: 0.45)) {
                            scale = 1.08
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                            withAnimation(.spring(response: 0.18, dampingFraction: 0.7)) {
                                scale = 1.0
                            }
                        }
                    }
                }
            }
            .onChange(of: value) { _, newVal in
                // If the real data updates mid-animation, smoothly transition to the new value.
                withAnimation(.easeOut(duration: 0.5)) {
                    displayedValue = Double(newVal)
                }
            }
    }

    private func animationDuration(for steps: Int) -> Double {
        // 0.8s for small counts, scales up to 1.5s for 20k+ steps
        let t = Double(steps) / 20_000.0
        return 0.8 + min(t, 1.0) * 0.7
    }
}
