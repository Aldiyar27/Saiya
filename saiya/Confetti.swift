import SwiftUI

/// Короткий салют из конфетти. Показывается поверх экрана и не мешает нажатиям.
struct ConfettiView: View {
    private struct Piece: Identifiable {
        let id = UUID()
        let x = CGFloat.random(in: 0...1)
        let width = CGFloat.random(in: 6...10)
        let color: Color
        let delay = Double.random(in: 0...0.7)
        let duration = Double.random(in: 1.6...2.6)
        let spin = Double.random(in: 180...720)
        let drift = CGFloat.random(in: -70...70)
    }

    private static func makePieces() -> [Piece] {
        let colors: [Color] = [Theme.mint, Theme.lime, Theme.peach, Theme.rose, Theme.blue]
        return (0..<48).map { _ in Piece(color: colors.randomElement() ?? Theme.mint) }
    }

    @State private var pieces = ConfettiView.makePieces()
    @State private var fall = false

    var body: some View {
        GeometryReader { geo in
            ForEach(pieces) { p in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(p.color)
                    .frame(width: p.width, height: p.width * 1.6)
                    .rotationEffect(.degrees(fall ? p.spin : 0))
                    .position(x: p.x * geo.size.width + (fall ? p.drift : 0),
                              y: fall ? geo.size.height + 40 : -20)
                    .animation(.easeIn(duration: p.duration).delay(p.delay), value: fall)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear { fall = true }
    }
}

/// Плашка сверху: «Новый уровень», «Запись сохранена» и т. п.
struct ToastView: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18).padding(.vertical, 11)
            .background(Theme.primary, in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
            .padding(.horizontal)
    }
}
