//
//  SplashView.swift
//  TouchGrass
//

import SwiftUI

struct SplashView: View {
    @State private var scale: CGFloat = 0.82
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Image("AppLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 108, height: 108)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .shadow(color: .black.opacity(0.13), radius: 14, y: 5)

                Text("TouchGrass")
                    .font(.custom("Billabong", size: 58))
                    .foregroundColor(.primary)
            }
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) {
                    scale   = 1.0
                    opacity = 1.0
                }
            }
        }
    }
}
