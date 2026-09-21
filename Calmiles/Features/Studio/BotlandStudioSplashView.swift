import SwiftUI

/// Branded cold-start splash — Botland Studio launch experience (not a network loader).
struct BotlandStudioSplashView: View {
    var body: some View {
        ZStack {
            CalmilesColor.slateIndigo
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(CalmilesColor.copper.opacity(0.18))
                        .frame(width: 96, height: 96)
                    Circle()
                        .strokeBorder(CalmilesColor.mist.opacity(0.22), lineWidth: 1)
                        .frame(width: 96, height: 96)
                    Image(systemName: "road.lanes")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(CalmilesColor.copperSoft)
                        .accessibilityHidden(true)
                }

                VStack(spacing: 6) {
                    Text("Botland Studio")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(CalmilesColor.mist)
                        .tracking(0.4)

                    Text("Calmiles")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(CalmilesColor.sand.opacity(0.9))
                }

                Spacer()

                Text("botland.studio")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(CalmilesColor.mist.opacity(0.45))
                    .padding(.bottom, 36)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Botland Studio, Calmiles")
    }
}
