//
//  SplashView.swift
//  ExpenseTracker
//

import SwiftUI

/// Launch animation: the icon-style ₹ (dashed, fading tail) crossfades into a
/// bold solid ₹, then `onFinished` is called so the app can reveal the Daily view.
struct SplashView: View {
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBold = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.brandYellow, .brandLightYellow],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ZStack {
                RupeeGlyph(style: .icon)
                    .opacity(isBold ? 0 : 1)
                RupeeGlyph(style: .bold)
                    .opacity(isBold ? 1 : 0)
                    .scaleEffect(isBold || reduceMotion ? 1 : 0.9)
            }
            .frame(width: 160)
        }
        .task {
            // Hold the icon look briefly, morph to bold, hold, then hand off.
            try? await Task.sleep(for: .seconds(0.5))
            withAnimation(.easeInOut(duration: reduceMotion ? 0.3 : 0.6)) {
                isBold = true
            }
            try? await Task.sleep(for: .seconds(0.9))
            onFinished()
        }
    }
}

#Preview {
    SplashView(onFinished: {})
}
