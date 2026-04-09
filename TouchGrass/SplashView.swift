//
//  SplashView.swift
//  TouchGrass
//

import SwiftUI

struct SplashView: View {
    @State private var scale: CGFloat = 0.82
    @State private var opacity: Double = 0

    // Logo width — text frame is set to match + a small overhang each side.
    private let logoSize: CGFloat = 108
    private let textWidth: CGFloat = 134   // ~13pt wider than logo on each side

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: logoSize, height: logoSize)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .shadow(color: .black.opacity(0.13), radius: 14, y: 5)

                // Start at a huge size so minimumScaleFactor can scale it
                // down precisely to fill `textWidth`. This guarantees the
                // text is always just slightly wider than the logo regardless
                // of the exact font metrics.
                Text("TouchGrass")
                    .font(.custom("Billabong", size: 400))
                    .minimumScaleFactor(0.01)
                    .lineLimit(1)
                    .frame(width: textWidth)
                    .foregroundColor(.primary)
            }
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                // DEBUG: prints the exact PostScript name to the Xcode console
                // so you can verify the font loaded correctly.
                #if DEBUG
                for family in UIFont.familyNames {
                    for name in UIFont.fontNames(forFamilyName: family)
                    where name.lowercased().contains("bill") || family.lowercased().contains("bill") {
                        print("[Font] family: \(family)  postScript: \(name)")
                    }
                }
                #endif

                withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
                    scale   = 1.0
                    opacity = 1.0
                }
            }
        }
    }
}
