//
//  SplashView.swift
//  TouchGrass
//

import SwiftUI

struct SplashView: View {
    @State private var scale: CGFloat = 0.82
    @State private var opacity: Double = 0
    @State private var resolvedFontName: String = "Billabong"

    private let logoSize: CGFloat = 108
    private let textWidth: CGFloat = 240

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

                Text("TouchGrass")
                    .font(.custom(resolvedFontName, size: 400))
                    .minimumScaleFactor(0.01)
                    .lineLimit(1)
                    .frame(width: textWidth)
                    .foregroundColor(.primary)
            }
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                let candidates = ["Billabong", "Billabong-Regular", "BillabongRegular"]
                for candidate in candidates {
                    if UIFont(name: candidate, size: 12) != nil {
                        resolvedFontName = candidate
                        break
                    }
                }

                withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
                    scale   = 1.0
                    opacity = 1.0
                }
            }
        }
    }
}
