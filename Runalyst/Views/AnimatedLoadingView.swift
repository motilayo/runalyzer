import SwiftUI

struct AnimatedLoadingView: View {
    @State private var isPulsing = false

    var text: String = "Analyzing your run..."
    var isHorizontal: Bool = false
    var imageSize: CGFloat = 40
    var textFont: Font = .headline
    var textColor: Color = .secondary
    var iconColor: Color = .accentColor
    var spacing: CGFloat = 16

    var body: some View {
        Group {
            if isHorizontal {
                HStack(spacing: spacing) {
                    content
                }
            } else {
                VStack(spacing: spacing) {
                    content
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if #available(iOS 17.0, *) {
            Image(systemName: "figure.run")
                .font(.system(size: imageSize))
                .foregroundColor(iconColor)
                .symbolEffect(.bounce.up, options: .repeating)
        } else {
            Image(systemName: "figure.run")
                .font(.system(size: imageSize))
                .foregroundColor(iconColor)
        }

        Text(text)
            .font(textFont)
            .foregroundColor(textColor)
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

#Preview {
    VStack(spacing: 40) {
        AnimatedLoadingView()
        AnimatedLoadingView(text: "Syncing...", isHorizontal: true, imageSize: 16, textFont: .caption)
    }
}
