import SwiftUI
import UIKit

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

enum Theme {
    static let background = Color(red: 0.96, green: 0.97, blue: 0.95)
    static let primary = Color(red: 0.12, green: 0.25, blue: 0.22)
    static let mint = Color(red: 0.24, green: 0.63, blue: 0.52)
    static let lime = Color(red: 0.72, green: 0.84, blue: 0.36)
    static let peach = Color(red: 0.98, green: 0.61, blue: 0.34)
    static let rose = Color(red: 0.91, green: 0.38, blue: 0.39)
    static let blue = Color(red: 0.28, green: 0.52, blue: 0.86)
    static let card = Color.white

    static let gradient = LinearGradient(colors: [mint, primary], startPoint: .topLeading, endPoint: .bottomTrailing)
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 14, y: 7)
    }
}

struct Nav<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        NavigationView { content }
            .navigationViewStyle(.stack)
    }
}

struct SectionTitle: View {
    let title: String
    let subtitle: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(.title3, design: .rounded).weight(.bold))
            if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
        }
    }
}
