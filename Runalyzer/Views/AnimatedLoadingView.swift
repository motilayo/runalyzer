import SwiftUI

struct AnimatedLoadingView: View {
    @State private var isBouncing = false
    @State private var isPulsing = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.run")
                .font(.system(size: 40))
                .foregroundColor(.accentColor)
                .offset(y: isBouncing ? -10 : 0)
                .rotationEffect(.degrees(isBouncing ? 15 : -5))
                .onAppear {
                    withAnimation(
                        .easeInOut(duration: 0.3)
                        .repeatForever(autoreverses: true)
                    ) {
                        isBouncing = true
                    }
                }

            Text("Analyzing your run...")
                .font(.headline)
                .foregroundColor(.secondary)
                .opacity(isPulsing ? 1.0 : 0.4)
                .onAppear {
                    withAnimation(
                        .easeInOut(duration: 1.0)
                        .repeatForever(autoreverses: true)
                    ) {
                        isPulsing = true
                    }
                }
        }
    }
}

#Preview {
    AnimatedLoadingView()
}
